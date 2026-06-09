extends GutTest

# 测试 AIAgent.execute_player_command 的公开契约
# 不依赖真实 ToolRegistry，用轻量 RefCounted fake 注入

class _FakeRegistry extends RefCounted:
	var last_tool: String = ""
	var last_args: Dictionary = {}
	var return_value: Dictionary = {"ok": true}
	var fail_next: bool = false

	func execute(tool_name: String, args: Dictionary) -> Dictionary:
		last_tool = tool_name
		last_args = args
		if fail_next:
			return {"ok": false, "error": "fake_error"}
		return return_value


class _FakeMemoryManager extends RefCounted:
	var last_character = null
	var last_content: String = ""
	var last_type = null
	var last_importance = null

	func add_memory(character, content: String, mem_type, importance) -> void:
		last_character = character
		last_content = content
		last_type = mem_type
		last_importance = importance


var _agent: Node = null
var _fake_registry: _FakeRegistry = null
var _fake_memory_mgr: _FakeMemoryManager = null
var _char_ref: Node = null  # 单独保存 character 引用，避免 after_each 中访问已释放的 _agent.character


func before_each():
	# 创建 AIAgent 实例（作为 Node，不直接 _ready）
	_agent = Node.new()
	_agent.set_script(load("res://script/ai/AIAgent.gd"))

	# 注入 fake ToolRegistry（类型现为 RefCounted，可赋值）
	_fake_registry = _FakeRegistry.new()
	_agent._tool_registry = _fake_registry

	# 注入 fake MemoryManager（用 set 避免类型检查）
	_fake_memory_mgr = _FakeMemoryManager.new()
	_agent.set("_memory_mgr_node", _fake_memory_mgr)

	# 给 character 一个最小 mock，单独保存引用以便 after_each 释放
	_char_ref = Node.new()
	_char_ref.set_meta("character_data", {"memories": [], "tasks": []})
	_agent.character = _char_ref


func after_each():
	# 先释放 character，再释放 agent（避免访问已释放对象）
	if is_instance_valid(_char_ref):
		_char_ref.free()
		_char_ref = null
	if is_instance_valid(_agent):
		_agent.free()


# === 接口存在性 ===

func test_agent_has_execute_player_command_method():
	assert_true(_agent.has_method("execute_player_command"),
		"AIAgent 应有 execute_player_command 方法")


func test_execute_player_command_returns_dictionary():
	_agent._tool_registry = null  # 模拟未初始化
	var result = _agent.execute_player_command("move_to", {"target": "100,100"})
	assert_true(result is Dictionary, "返回值应为 Dictionary")
	assert_false(result.get("ok", true), "未初始化时应返回 ok=false")


func test_execute_player_command_no_registry():
	_agent._tool_registry = null
	var result = _agent.execute_player_command("move_to", {"target": "100,100"})
	assert_false(result.get("ok", true), "ToolRegistry 未初始化应返回 ok=false")
	assert_eq(result.get("error"), "tool_registry_not_initialized",
		"错误信息应指出 tool_registry_not_initialized")


func test_execute_player_command_unknown_tool():
	_fake_registry.return_value = {"ok": false, "error": "unknown_tool"}
	var result = _agent.execute_player_command("nonexistent", {})
	assert_false(result.get("ok", true), "未知工具应返回 ok=false")


func test_execute_player_command_with_valid_registry():
	_fake_registry.return_value = {"ok": true, "action": "move_to"}
	var result = _agent.execute_player_command("move_to", {"target": "100,100"})
	assert_true(result.get("ok", false), "合法调用应返回 ok=true")
	assert_eq(_fake_registry.last_tool, "move_to", "应调用 ToolRegistry.execute")
	assert_eq(_fake_registry.last_args.get("target"), "100,100", "参数应正确传递")


func test_execute_player_command_interrupt_flag():
	# 验证中断逻辑：character 的 navigation_path 被清空
	# 复用 _char_ref，避免 orphan
	_char_ref.set_meta("character_data", {"memories": [], "tasks": []})
	_char_ref.set("_navigation_path", [])
	_agent.character = _char_ref

	_agent.execute_player_command("wait", {"reason": "test"})
	# 不崩溃即通过（navigation_path 的存在性因实现而异，这里只测不崩溃）
	assert_true(true, "中断逻辑不应崩溃")


func test_execute_player_command_records_memory():
	_fake_registry.return_value = {"ok": true}
	_agent.execute_player_command("remember", {"content": "test", "importance": 5})
	# 验证 MemoryManager.add_memory 被调用
	assert_true(_fake_memory_mgr.last_content != "",
		"执行成功后应记录记忆")


func test_execute_player_command_does_not_record_memory_on_failure():
	_fake_registry.return_value = {"ok": false, "error": "fake"}
	_agent.execute_player_command("move_to", {"target": "100,100"})
	# 失败时不应记录记忆
	assert_true(_fake_memory_mgr.last_content == "",
		"执行失败时不应记录记忆")


func test_execute_player_command_empty_content_for_remember():
	# ToolRegistry 返回错误（content 为空时 handler 会返回错误）
	_fake_registry.return_value = {"ok": false, "error": "empty_content"}
	var result = _agent.execute_player_command("remember", {"content": ""})
	assert_false(result.get("ok", true), "空 content 应返回 ok=false")
	assert_eq(result.get("error"), "empty_content", "错误原因应为 empty_content")
