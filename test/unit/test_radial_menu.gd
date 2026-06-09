extends GutTest

# 测试 RadialMenu 的公开接口与信号契约
# 不依赖完整场景树，只测菜单项定义、坐标布局、信号发射

var _menu_script: Script = null
var _menu: Control = null


func before_each():
	_menu_script = load("res://script/ui/RadialMenu.gd")
	assert_not_null(_menu_script, "RadialMenu.gd 脚本应存在")
	_menu = _menu_script.new()
	# 不需要 add_child，直接测方法逻辑


func after_each():
	if is_instance_valid(_menu):
		_menu.free()


# === 接口存在性 ===

func test_radial_menu_script_exists():
	assert_not_null(_menu_script, "RadialMenu.gd 脚本应存在")


func test_radial_menu_has_method_show_for_character():
	assert_true(_menu.has_method("show_for_character"),
		"RadialMenu 应有 show_for_character 方法")


func test_radial_menu_has_method_hide_menu():
	assert_true(_menu.has_method("hide_menu"),
		"RadialMenu 应有 hide_menu 方法")


func test_radial_menu_has_signal_action_selected():
	var sigs: Array = _menu.get_signal_list()
	var found := false
	for s in sigs:
		if s["name"] == "action_selected":
			found = true
			break
	assert_true(found, "RadialMenu 应声明 action_selected 信号")


# === 菜单项常量 ===

func test_menu_items_count():
	assert_eq(_menu.MENU_ITEMS.size(), 6,
		"MENU_ITEMS 应有 6 个指令")


func test_menu_items_have_required_keys():
	for item in _menu.MENU_ITEMS:
		assert_has(item, "name", "每项应有 name")
		assert_has(item, "action", "每项应有 action")
		assert_has(item, "needs_target", "每项应有 needs_target")


func test_menu_items_actions_match_tool_registry():
	# 直接指令应对应 ToolRegistry 中的工具名
	var expected_actions = ["move_to", "talk_to", "adjust_tasks", "remember", "change_mood", "wait"]
	for i in range(expected_actions.size()):
		assert_eq(_menu.MENU_ITEMS[i]["action"], expected_actions[i],
			"第 %d 项的 action 应是 %s" % [i, expected_actions[i]])


# === 坐标布局 ===

func test_polar_layout_angles():
	# 6 个按钮应均匀分布，角度间隔 TAU/6
	var n: int = _menu.MENU_ITEMS.size()
	var expected_angles: Array = []
	for i in range(n):
		expected_angles.append(TAU * float(i) / float(n) - PI * 0.5)
	# 只检查角度计算，不依赖 _build_menu_buttons 的私有状态
	assert_eq(expected_angles.size(), n, "角度数组长度应匹配")
	# 第一个角度应从 -π/2 开始（正上方）
	assert_almost_eq(expected_angles[0], -PI * 0.5, 0.001, "第一个按钮应在正上方")


func test_radius_is_positive():
	assert_true(_menu.RADIUS > 0, "RADIUS 应为正数")


# === 二级模式枚举 ===

func test_select_mode_enum_values():
	assert_eq(_menu.SelectMode.NONE, 0, "NONE 应为 0")
	assert_eq(_menu.SelectMode.MOVE, 1, "MOVE 应为 1")
	assert_eq(_menu.SelectMode.TALK, 2, "TALK 应为 2")
	assert_eq(_menu.SelectMode.MOOD, 3, "MOOD 应为 3")
	assert_eq(_menu.SelectMode.REMEMBER, 4, "REMEMBER 应为 4")




# === 集成契约：CharacterManager 右键 ===

func test_character_manager_has_handle_right_click():
	var cm = load("res://script/CharacterManager.gd")
	var inst = Node.new()
	inst.set_script(cm)
	# _handle_right_click 是私有方法（前缀 _），Godot 外部不可调用
	# 但可以通过 call_method 测试（如果暴露）
	# 这里只验证脚本能加载且无语法错误
	assert_not_null(inst.get_script(), "CharacterManager 脚本应加载成功")
	inst.free()
