extends GutTest

# 测试 ToolRegistry 的核心功能

var _registry: ToolRegistry

func before_each():
	_registry = ToolRegistry.new(null)

func test_has_10_tools():
	assert_eq(_registry.get_tool_names().size(), 10, "应有 10 个工具")

func test_known_tools():
	var names = _registry.get_tool_names()
	for expected in ["move_to", "talk_to", "think", "complete_task", "adjust_tasks", "remember", "observe", "change_mood", "wait"]:
		assert_has(names, expected, "缺少工具: " + expected)

func test_execute_unknown_tool():
	var result = _registry.execute("nonexistent_tool", {})
	assert_false(result.get("ok", true), "未知工具应返回 ok=false")
	assert_has(result, "error", "应包含 error 字段")

func test_execute_think_no_sandbox():
	var result = _registry.execute("think", {"content": "test"})
	assert_false(result.get("ok", true), "无 sandbox 时应失败")

func test_execute_wait_no_sandbox():
	var result = _registry.execute("wait", {"reason": "idle"})
	assert_false(result.get("ok", true), "无 sandbox 时应失败")

func test_get_tool_descriptions_not_empty():
	var desc = _registry.get_tool_descriptions()
	assert_gt(desc.length(), 0, "工具描述不应为空")
	assert_true(desc.contains("move_to"), "描述应包含 move_to")

func test_has_tool():
	assert_true(_registry.has_tool("move_to"), "应有 move_to")
	assert_false(_registry.has_tool("fly_to"), "不应有 fly_to")
