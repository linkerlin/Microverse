class_name RadialMenu
extends Control

# 圆形菜单 —— 右键点击角色弹出，选择指令后角色立即执行
# 参照 AGENTS.md §5 方案实施

signal action_selected(character_node, action_name, params)

# 菜单项定义（与 ToolRegistry 的 9 个工具对应，合并为 6 个玩家指令）
const MENU_ITEMS = [
	{"name": "移动", "icon": "🏃", "action": "move_to", "needs_target": true, "tooltip": "移动到指定位置"},
	{"name": "对话", "icon": "💬", "action": "talk_to", "needs_target": true, "tooltip": "与指定角色对话"},
	{"name": "任务", "icon": "📋", "action": "adjust_tasks", "needs_target": false, "tooltip": "管理任务列表"},
	{"name": "记忆", "icon": "🧠", "action": "remember", "needs_target": false, "tooltip": "写入一条记忆"},
	{"name": "心情", "icon": "😊", "action": "change_mood", "needs_target": false, "tooltip": "改变心情状态"},
	{"name": "等待", "icon": "⏳", "action": "wait", "needs_target": false, "tooltip": "原地等待一回合"},
]

# 二级选择模式
enum SelectMode { NONE, MOVE, TALK, MOOD, REMEMBER }
var _select_mode: SelectMode = SelectMode.NONE
var _pending_action: Dictionary = {}

var _character: CharacterBody2D = null
var _buttons: Array = []
var _tween: Tween = null

# 布局参数
const RADIUS: float = 60.0
const BUTTON_SIZE: Vector2 = Vector2(48, 48)

# 二级 UI 节点（延迟创建）
var _overlay: Control = null
var _target_panel: Panel = null
var _target_list: ItemList = null
var _mood_panel: Panel = null
var _remember_panel: Panel = null


func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP
	# 设置最小尺寸，确保 size 有正确值（半径*2 + 按钮尺寸）
	custom_minimum_size = Vector2(RADIUS * 2 + BUTTON_SIZE.x, RADIUS * 2 + BUTTON_SIZE.y)
	hide()
	_build_menu_buttons()


func show_for_character(character: CharacterBody2D, screen_pos: Vector2) -> void:
	_character = character
	_select_mode = SelectMode.NONE
	_pending_action = {}
	_hide_secondary_panels()

	# 定位菜单中心到点击位置
	position = screen_pos - size * 0.5
	show()
	_animate_in()


func hide_menu() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector2.ZERO, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_tween.tween_property(self, "modulate:a", 0.0, 0.08)
	_tween.tween_callback(func(): hide(); _character = null)


func _build_menu_buttons() -> void:
	# 清空旧按钮
	for b in _buttons:
		if is_instance_valid(b):
			b.queue_free()
	_buttons.clear()

	# 极坐标布局
	var n: int = MENU_ITEMS.size()
	for i in range(n):
		var item: Dictionary = MENU_ITEMS[i]
		var angle: float = TAU * float(i) / float(n) - PI * 0.5  # 从正上方开始
		var btn_pos: Vector2 = Vector2(cos(angle), sin(angle)) * RADIUS

		var btn := Button.new()
		btn.theme_type_variation = "RadialButton"
		btn.custom_minimum_size = BUTTON_SIZE
		btn.tooltip_text = item.get("tooltip", item.name)
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.pressed.connect(_on_button_pressed.bind(item))

		# 按钮文字：图标 + 名称（Button 文字默认居中，无需设置 alignment）
		btn.text = "%s\n%s" % [item.icon, item.name]

		add_child(btn)
		btn.position = btn_pos - BUTTON_SIZE * 0.5 + size * 0.5
		_buttons.append(btn)


func _animate_in() -> void:
	scale = Vector2.ZERO
	modulate.a = 0.0
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "modulate:a", 1.0, 0.15)


func _on_button_pressed(item: Dictionary) -> void:
	if item.needs_target:
		_enter_secondary_mode(item)
	else:
		_execute_direct_action(item)


func _enter_secondary_mode(item: Dictionary) -> void:
	_pending_action = item
	match item.action:
		"move_to":
			_select_mode = SelectMode.MOVE
			_show_move_target_overlay()
		"talk_to":
			_select_mode = SelectMode.TALK
			_show_talk_target_panel()
		_:
			_select_mode = SelectMode.NONE


func _execute_direct_action(item: Dictionary) -> void:
	match item.action:
		"change_mood":
			_show_mood_panel()
			return
		"remember":
			_show_remember_panel()
			return
		"wait":
			_dispatch_action(item.action, {"reason": "玩家指令"})
		"adjust_tasks":
			_show_task_panel()
			return
	_hide_secondary_panels()


func _dispatch_action(action_name: String, params: Dictionary) -> void:
	if not is_instance_valid(_character):
		push_warning("[RadialMenu] 角色节点无效")
		hide_menu()
		return

	# 通过 AIAgent.execute_player_command 执行
	var ai_agent: Node = _character.get_node_or_null("AIAgent")
	if ai_agent and ai_agent.has_method("execute_player_command"):
		var result: Dictionary = ai_agent.execute_player_command(action_name, params)
		if result.get("ok", false):
			print("[RadialMenu] 指令执行成功: %s → %s" % [action_name, params])
		else:
			push_warning("[RadialMenu] 指令执行失败: %s, 错误: %s" % [action_name, result.get("error", "未知")])
	else:
		push_warning("[RadialMenu] 角色缺少 AIAgent 或 execute_player_command 方法")

	action_selected.emit(_character, action_name, params)
	hide_menu()


# === 移动选点覆盖层 ===

func _show_move_target_overlay() -> void:
	_hide_secondary_panels()
	if not _overlay:
		_overlay = Control.new()
		_overlay.name = "MoveOverlay"
		_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
		_overlay.gui_input.connect(_on_overlay_input)
		var label := Label.new()
		label.text = "点击地图某处，角色将移动过去（右键取消）"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		label.offset_top = 10
		_overlay.add_child(label)
		get_tree().root.add_child(_overlay)
	else:
		_overlay.show()


func _on_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var world_pos: Vector2 = _screen_to_world(event.position)
			_dispatch_action("move_to", {"target": "%f,%f" % [world_pos.x, world_pos.y], "reason": "玩家指令"})
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_hide_secondary_panels()
			hide_menu()


# === 对话目标选择面板 ===

func _show_talk_target_panel() -> void:
	_hide_secondary_panels()
	if not _target_panel:
		_target_panel = Panel.new()
		_target_panel.name = "TalkTargetPanel"
		_target_panel.custom_minimum_size = Vector2(150, 200)
		_target_panel.position = get_viewport_rect().size * 0.5 - Vector2(75, 100)
		_target_list = ItemList.new()
		_target_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_target_list.item_selected.connect(_on_talk_target_selected)
		_target_panel.add_child(_target_list)
		var cancel_btn := Button.new()
		cancel_btn.text = "取消"
		cancel_btn.pressed.connect(_hide_secondary_panels)
		_target_panel.add_child(cancel_btn)
		get_tree().root.add_child(_target_panel)
	else:
		_target_panel.show()

	# 填充同房间角色
	_populate_talk_targets()


func _populate_talk_targets() -> void:
	_target_list.clear()
	if not is_instance_valid(_character):
		return
	var char_manager = get_node_or_null("/root/CharacterManager")
	if not char_manager:
		return
	# 简单实现：列出所有可控角色，过滤自己
	var all_chars: Array = get_tree().get_nodes_in_group("controllable_characters")
	for c in all_chars:
		if c != _character:
			_target_list.add_item(c.name)


func _on_talk_target_selected(idx: int) -> void:
	var char_name: String = _target_list.get_item_text(idx)
	_dispatch_action("talk_to", {"name": char_name, "message": ""})
	_hide_secondary_panels()


# === 心情选择面板 ===

func _show_mood_panel() -> void:
	_hide_secondary_panels()
	if not _mood_panel:
		_mood_panel = Panel.new()
		_mood_panel.name = "MoodPanel"
		_mood_panel.custom_minimum_size = Vector2(200, 250)
		_mood_panel.position = get_viewport_rect().size * 0.5 - Vector2(100, 125)
		var vbox := VBoxContainer.new()
		_mood_panel.add_child(vbox)
		var moods := ["普通", "开心", "悲伤", "愤怒", "焦虑", "兴奋"]
		for m in moods:
			var btn := Button.new()
			btn.text = m
			btn.pressed.connect(_on_mood_selected.bind(m))
			vbox.add_child(btn)
		var cancel_btn := Button.new()
		cancel_btn.text = "取消"
		cancel_btn.pressed.connect(_hide_secondary_panels)
		vbox.add_child(cancel_btn)
		get_tree().root.add_child(_mood_panel)
	else:
		_mood_panel.show()


func _on_mood_selected(mood: String) -> void:
	_dispatch_action("change_mood", {"mood": mood, "reason": "玩家指令"})
	_hide_secondary_panels()


# === 记忆输入面板 ===

func _show_remember_panel() -> void:
	_hide_secondary_panels()
	if not _remember_panel:
		_remember_panel = Panel.new()
		_remember_panel.name = "RememberPanel"
		_remember_panel.custom_minimum_size = Vector2(300, 120)
		_remember_panel.position = get_viewport_rect().size * 0.5 - Vector2(150, 60)
		var vbox := VBoxContainer.new()
		_remember_panel.add_child(vbox)
		var line_edit := LineEdit.new()
		line_edit.name = "MemoryInput"
		line_edit.placeholder_text = "输入要记住的内容..."
		line_edit.text_submitted.connect(_on_remember_submitted)
		vbox.add_child(line_edit)
		var hbox := HBoxContainer.new()
		var confirm_btn := Button.new()
		confirm_btn.text = "确认"
		confirm_btn.pressed.connect(func(): _on_remember_submitted(line_edit.text))
		var cancel_btn := Button.new()
		cancel_btn.text = "取消"
		cancel_btn.pressed.connect(_hide_secondary_panels)
		hbox.add_child(confirm_btn)
		hbox.add_child(cancel_btn)
		vbox.add_child(hbox)
		get_tree().root.add_child(_remember_panel)
	else:
		_remember_panel.show()
		var line_edit: LineEdit = _remember_panel.get_node("MemoryInput")
		if line_edit:
			line_edit.text = ""
			line_edit.grab_focus()


func _on_remember_submitted(text: String) -> void:
	if text.is_empty():
		return
	_dispatch_action("remember", {"content": text, "importance": 5})
	_hide_secondary_panels()


# === 任务面板（简化版）===

func _show_task_panel() -> void:
	# 暂时直接添加一个示例任务，后续可扩展为完整任务管理
	_dispatch_action("adjust_tasks", {"actions": [{"op": "add", "description": "玩家指派的任务", "priority": 5}]})


# === 工具方法 ===

func _hide_secondary_panels() -> void:
	_select_mode = SelectMode.NONE
	if is_instance_valid(_overlay):
		_overlay.hide()
	if is_instance_valid(_target_panel):
		_target_panel.hide()
	if is_instance_valid(_mood_panel):
		_mood_panel.hide()
	if is_instance_valid(_remember_panel):
		_remember_panel.hide()


func _screen_to_world(screen_pos: Vector2) -> Vector2:
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera:
		return camera.get_global_mouse_position()
	return screen_pos


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	# 点击菜单外区域关闭
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _select_mode == SelectMode.NONE:
			# 检查是否点击在按钮上
			var clicked_button := false
			for b in _buttons:
				if b is Button and b.is_pressed():
					clicked_button = true
					break
			if not clicked_button:
				hide_menu()
	get_viewport().set_input_as_handled()
