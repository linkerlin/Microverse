extends Node

# 单例实例
static var instance = null

# API URLs现在通过APIConfig统一管理

# 当前设置（从SettingsManager获取）
var current_settings = {}

# Cache 监控统计
var _cache_stats: Dictionary = {"hits": 0, "misses": 0, "total_tokens_in": 0, "total_tokens_out": 0, "requests": 0, "cache_hit_tokens_total": 0}
var _cost_per_token_in: float = 0.001  # ¥/K tokens, DeepSeek 默认
var _cost_per_token_out: float = 0.002

# 获取单例实例
static func get_instance() -> APIManager:
	if instance == null:
		instance = Engine.get_singleton("APIManager")
		if instance == null:
			print("[APIManager] 创建新的APIManager实例")
			instance = APIManager.new()
	return instance

func _enter_tree():
	# 设置单例实例
	if instance == null:
		instance = self
	
	add_to_group("api_manager")

# 在_ready中连接设置管理器
func _ready():
	# 连接设置变化信号
	SettingsManager.settings_changed.connect(_on_settings_changed)
	# 获取当前设置
	current_settings = SettingsManager.get_settings()
	print("[APIManager] 已连接设置管理器，当前设置 - API类型：", current_settings.api_type, "，模型：", current_settings.model)

# 设置变化回调
func _on_settings_changed(new_settings: Dictionary):
	current_settings = new_settings.duplicate()
	print("[APIManager] 设置已更新 - API类型：", current_settings.api_type, "，模型：", current_settings.model)

# 生成对话（支持角色独立AI设置）
func generate_dialog(prompt: String, character_name: String = "") -> HTTPRequest:
	# 确保节点已经初始化
	if not is_inside_tree():
		push_error("APIManager is not properly initialized!")
		return null
	
	# 等待三帧以确保完全初始化
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	
	# 创建新的HTTPRequest节点，不清理之前的节点
	var http_request = HTTPRequest.new()
	# 为每个请求设置唯一名称
	http_request.name = "HTTPRequest_" + str(Time.get_unix_time_from_system()) + "_" + str(randi())
	add_child(http_request)
	
	# 设置请求完成后自动清理
	http_request.request_completed.connect(func(result, response_code, headers, body):
		# 延迟清理，确保回调函数执行完毕
		get_tree().create_timer(1.0).timeout.connect(func():
			if http_request and is_instance_valid(http_request):
				remove_child(http_request)
				http_request.queue_free()
		)
	)
	# 获取角色对应的AI设置
	var ai_settings = current_settings
	if character_name != "":
		ai_settings = SettingsManager.get_character_ai_settings(character_name)
		print("[APIManager] 为角色 ", character_name, " 使用AI设置 - API类型：", ai_settings.api_type, "，模型：", ai_settings.model)
	else:
		print("[APIManager] 使用默认AI设置 - API类型：", ai_settings.api_type, "，模型：", ai_settings.model)
	
	# 使用APIConfig构建请求
	var headers = APIConfig.build_headers(ai_settings.api_type, ai_settings.api_key)
	var data = JSON.stringify(APIConfig.build_request_data(ai_settings.api_type, ai_settings.model, prompt))
	var url = APIConfig.get_url(ai_settings.api_type, ai_settings.model)
	
	print("[APIManager] 发送请求到 ", ai_settings.api_type, " API，模型：", ai_settings.model)
	
	print("[APIManager] 请求URL：", url)
	print("[APIManager] 创建HTTPRequest节点：", http_request.name)
	var request_error = http_request.request(url, headers, HTTPClient.METHOD_POST, data)
	if request_error != OK:
		push_error("[APIManager] 请求发起失败: " + str(request_error))
		# 立即触发 request_completed 信号（带错误结果），使 await 不挂起
		http_request.emit_signal("request_completed", request_error, 0, PackedStringArray(), PackedByteArray())
	return http_request

# 生成三段式对话(Context Cache)
func generate_tiered_dialog(tier1: String, tier2: String, tier3: String, character_name: String = "") -> HTTPRequest:
	if not is_inside_tree():
		push_error("APIManager is not properly initialized!")
		return null
	
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	
	var http_request = HTTPRequest.new()
	http_request.name = "HTTPRequest_Tiered_" + str(Time.get_unix_time_from_system()) + "_" + str(randi())
	add_child(http_request)
	
	http_request.request_completed.connect(func(result, response_code, headers, body):
		get_tree().create_timer(1.0).timeout.connect(func():
			if http_request and is_instance_valid(http_request):
				remove_child(http_request)
				http_request.queue_free()
		)
	)
	
	var ai_settings = current_settings
	if character_name != "":
		ai_settings = SettingsManager.get_character_ai_settings(character_name)
		print("[APIManager] Tiered request for ", character_name, " - API:", ai_settings.api_type, " Model:", ai_settings.model)
	
	var headers = APIConfig.build_headers(ai_settings.api_type, ai_settings.api_key)
	var data = JSON.stringify(APIConfig.build_tiered_request(ai_settings.api_type, ai_settings.model, tier1, tier2, tier3))
	var url = APIConfig.get_url(ai_settings.api_type, ai_settings.model)
	
	print("[APIManager] Tiered request to ", ai_settings.api_type, " URL:", url)
	var request_error = http_request.request(url, headers, HTTPClient.METHOD_POST, data)
	if request_error != OK:
		push_error("[APIManager] 请求发起失败: " + str(request_error))
		# 立即触发 request_completed 信号（带错误结果），使 await 不挂起
		http_request.emit_signal("request_completed", request_error, 0, PackedStringArray(), PackedByteArray())
	_cache_stats.requests += 1
	return http_request

# 记录 cache 使用情况(从 LLM 响应中提取)
func log_cache_usage(response_body: Dictionary, api_type: String = "") -> void:
	var usage = response_body.get("usage", {})
	_cache_stats.total_tokens_in += int(usage.get("prompt_tokens", 0))
	_cache_stats.total_tokens_out += int(usage.get("completion_tokens", 0))
	
	# 计算 Cache 命中 tokens（用于计算命中率）
	# DeepSeek 格式：prompt_cache_hit_tokens（命中 Cache 的 tokens 数）
	# Anthropic 格式：cache_read_input_tokens（命中 Cache 的 tokens 数）
	var cache_hit_tokens = int(usage.get("prompt_cache_hit_tokens", 0))
	if cache_hit_tokens == 0:
		cache_hit_tokens = int(usage.get("cache_read_input_tokens", 0))
	
	# 累加 Cache 命中 tokens（用于更精确计算命中率）
	_cache_stats.cache_hit_tokens_total += cache_hit_tokens
	
	# 调试信息：打印 usage 字段，以明 API 实际返回何种 cache 字段
	print("[APIManager] log_cache_usage: api_type=", api_type, " usage=", usage, " cache_hit_tokens=", cache_hit_tokens)
	# 若无 cache 字段，则不计入 hit/miss（不惩罚）
	
	var total = _cache_stats.hits + _cache_stats.misses
	if total > 0:
		print("[APIManager] Cache 命中率: %d/%d (%.1f%%) | 总 token: in=%d out=%d | 预估费用: ¥%.2f" % [
			_cache_stats.hits, total, 100.0 * _cache_stats.hits / total,
			_cache_stats.total_tokens_in, _cache_stats.total_tokens_out,
			_estimate_cost()
		])

# 获取 cache 统计(给 GodUI 用)
func get_cache_stats() -> Dictionary:
	# 基于 tokens 的 Cache 命中率（更精确）
	var hit_rate = 0.0
	if _cache_stats.total_tokens_in > 0:
		hit_rate = 100.0 * _cache_stats.cache_hit_tokens_total / _cache_stats.total_tokens_in
	
	return {
		"hits": _cache_stats.hits,
		"misses": _cache_stats.misses,
		"hit_rate": hit_rate,  # 基于 tokens 的命中率
		"cache_hit_tokens_total": _cache_stats.cache_hit_tokens_total,
		"total_tokens_in": _cache_stats.total_tokens_in,
		"total_tokens_out": _cache_stats.total_tokens_out,
		"requests": _cache_stats.requests,
		"estimated_cost": _estimate_cost()
	}

func _estimate_cost() -> float:
	return _cache_stats.total_tokens_in * _cost_per_token_in / 1000.0 + _cache_stats.total_tokens_out * _cost_per_token_out / 1000.0

# 生成AI决策
func generate_decision(prompt: String, character_name: String = "") -> HTTPRequest:
	return await generate_dialog(prompt, character_name)
