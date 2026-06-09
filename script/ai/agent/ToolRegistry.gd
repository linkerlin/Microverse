class_name ToolRegistry
extends RefCounted

# 工具注册中心 — Gen 2 的 JSON tool call dispatch 层
# 每个 handler 最终调用 AgentSandbox 的同名方法
# Gen 3 直接让 LLM 写 GDScript 调 AgentSandbox,两条路径复用同一套业务逻辑

class ToolDef:
	var name: String
	var description: String
	var parameters: Dictionary
	var handler: Callable

var _tools: Dictionary = {}
var _sandbox: AgentSandbox = null

func _init(sandbox: AgentSandbox = null):
	_sandbox = sandbox
	_register_all()

func set_sandbox(sandbox: AgentSandbox) -> void:
	_sandbox = sandbox

func _register_all() -> void:
	_reg("move_to",
		"移动到目标位置。target 可以是 'x,y' 坐标或房间名。",
		{
			"type": "object",
			"properties": {
				"target": {"type": "string", "description": "'x,y' 坐标或房间名"},
				"reason": {"type": "string", "description": "移动原因(可选)"}
			},
			"required": ["target"]
		},
		_handler_move_to)

	_reg("talk_to",
		"与某人开始对话。对方必须在附近或同一房间。",
		{
			"type": "object",
			"properties": {
				"name": {"type": "string", "description": "对方名字"},
				"message": {"type": "string", "description": "开场白(可选)"}
			},
			"required": ["name"]
		},
		_handler_talk_to)

	_reg("think",
		"内心独白。只有你自己知道,不会显示给其他角色。",
		{
			"type": "object",
			"properties": {
				"content": {"type": "string", "description": "思考内容"}
			},
			"required": ["content"]
		},
		_handler_think)

	_reg("complete_task",
		"标记一个任务为已完成。task_id 可以是任务描述或创建时间戳。",
		{
			"type": "object",
			"properties": {
				"task_id": {"type": "string", "description": "任务 ID(描述或时间戳)"}
			},
			"required": ["task_id"]
		},
		_handler_complete_task)

	_reg("adjust_tasks",
		"调整任务优先级或新增任务。actions 是操作数组。",
		{
			"type": "object",
			"properties": {
				"actions": {
					"type": "array",
					"description": "操作列表,每项含 op 字段:add/reorder/set_priority/complete"
				}
			},
			"required": ["actions"]
		},
		_handler_adjust_tasks)

	_reg("remember",
		"把一条信息写入长期记忆。",
		{
			"type": "object",
			"properties": {
				"content": {"type": "string", "description": "记忆内容"},
				"importance": {"type": "integer", "description": "1-10,默认 5"}
			},
			"required": ["content"]
		},
		_handler_remember)

	_reg("observe",
		"仔细观察某人或某物,获取详细信息。不传 target 则观察自己。",
		{
			"type": "object",
			"properties": {
				"target": {"type": "string", "description": "目标名字(可选)"}
			},
			"required": []
		},
		_handler_observe)

	_reg("change_mood",
		"主动调整自己的心情。",
		{
			"type": "object",
			"properties": {
				"mood": {"type": "string", "description": "新心情"},
				"reason": {"type": "string", "description": "原因"}
			},
			"required": ["mood", "reason"]
		},
		_handler_change_mood)

	_reg("wait",
		"本回合什么都不做,等待。",
		{
			"type": "object",
			"properties": {
				"reason": {"type": "string", "description": "等待原因(可选)"}
			},
			"required": []
		},
		_handler_wait)

# === 公开接口 ===

func execute(tool_name: String, args: Dictionary) -> Dictionary:
	if not _tools.has(tool_name):
		return {"ok": false, "error": "unknown_tool:" + tool_name}
	return _tools[tool_name].handler.call(args)

func get_tool_descriptions() -> String:
	var lines: Array = []
	for name in _tools:
		var t = _tools[name]
		var param_str = JSON.stringify(t.parameters)
		lines.append("- %s: %s\n  参数:%s" % [t.name, t.description, param_str])
	return "\n".join(lines)

func get_tool_names() -> Array:
	return _tools.keys()

func has_tool(name: String) -> bool:
	return _tools.has(name)

# === 注册辅助 ===

func _reg(name: String, desc: String, params: Dictionary, handler: Callable) -> void:
	var tool = ToolDef.new()
	tool.name = name
	tool.description = desc
	tool.parameters = params
	tool.handler = handler
	_tools[name] = tool

# === Handler — 全部转发到 AgentSandbox ===

func _handler_move_to(args: Dictionary) -> Dictionary:
	if not _sandbox:
		return {"ok": false, "error": "sandbox_not_initialized"}
	if not args.has("target") or str(args.get("target", "")).is_empty():
		return {"ok": false, "error": "missing_required_param:target"}
	return _sandbox.move_to(args.get("target", ""))

func _handler_talk_to(args: Dictionary) -> Dictionary:
	if not _sandbox:
		return {"ok": false, "error": "sandbox_not_initialized"}
	if not args.has("name") or str(args.get("name", "")).is_empty():
		return {"ok": false, "error": "missing_required_param:name"}
	return _sandbox.talk_to(args.get("name", ""), args.get("message", ""))

func _handler_think(args: Dictionary) -> Dictionary:
	if not _sandbox:
		return {"ok": false, "error": "sandbox_not_initialized"}
	if not args.has("content") or str(args.get("content", "")).is_empty():
		return {"ok": false, "error": "missing_required_param:content"}
	return _sandbox.think(args.get("content", ""))

func _handler_complete_task(args: Dictionary) -> Dictionary:
	if not _sandbox:
		return {"ok": false, "error": "sandbox_not_initialized"}
	if not args.has("task_id") or str(args.get("task_id", "")).is_empty():
		return {"ok": false, "error": "missing_required_param:task_id"}
	return _sandbox.complete_task(args.get("task_id", ""))

func _handler_adjust_tasks(args: Dictionary) -> Dictionary:
	if not _sandbox:
		return {"ok": false, "error": "sandbox_not_initialized"}
	return _sandbox.adjust_tasks(args.get("actions", []))

func _handler_remember(args: Dictionary) -> Dictionary:
	if not _sandbox:
		return {"ok": false, "error": "sandbox_not_initialized"}
	if not args.has("content") or str(args.get("content", "")).is_empty():
		return {"ok": false, "error": "missing_required_param:content"}
	return _sandbox.remember(args.get("content", ""), int(args.get("importance", 5)))

func _handler_observe(args: Dictionary) -> Dictionary:
	if not _sandbox:
		return {"ok": false, "error": "sandbox_not_initialized"}
	return _sandbox.observe(args.get("target", ""))

func _handler_change_mood(args: Dictionary) -> Dictionary:
	if not _sandbox:
		return {"ok": false, "error": "sandbox_not_initialized"}
	return _sandbox.change_mood(args.get("mood", ""), args.get("reason", ""))

func _handler_wait(args: Dictionary) -> Dictionary:
	if not _sandbox:
		return {"ok": false, "error": "sandbox_not_initialized"}
	return _sandbox.wait(args.get("reason", ""))
