class_name CharacterPromptBuilder
extends RefCounted

# 三段式 prompt 拼接
# TIER 1: 永久缓存(人设+性格+公司+工具定义),极少变
# TIER 2: 缓变缓存(状态+记忆+任务+关系),1分钟内基本不动
# TIER 3: 即时(场景描述+时间),每次必变

static func build_tiered(character: CharacterBody2D, tool_registry: ToolRegistry) -> Dictionary:
	var t1 = _build_tier1(character, tool_registry)
	var t2 = _build_tier2(character)
	var t3 = _build_tier3(character)
	return {"tier1": t1, "tier2": t2, "tier3": t3}

# === TIER 1: 永久缓存,~1200 tokens ===

static func _build_tier1(character: CharacterBody2D, tool_registry: ToolRegistry) -> String:
	var personality = CharacterPersonality.get_personality(character.name)
	var p = ""
	p += "你是%s,%s的%s。" % [
		character.name,
		_get_company_name(),
		personality["position"]
	]
	p += "\n性格:" + personality["personality"]
	p += "\n说话风格:" + personality["speaking_style"]
	p += "\n工作职责:" + personality["work_duties"]
	p += "\n工作习惯:" + personality["work_habits"]

	p += "\n\n" + _get_company_basic_info()
	p += "\n" + _get_company_employees_info()

	var bg = BackgroundStoryManager.generate_background_prompt()
	if not bg.is_empty():
		p += "\n" + bg

	if tool_registry:
		p += "\n\n[可用工具]\n" + tool_registry.get_tool_descriptions()

	p += "\n\n[输出格式]"
	p += "\n先输出 #REASONING# 段(50-200字,描述你为什么这么做)。"
	p += "\n再输出 #ACTIONS# 段(JSON数组,1-3个工具调用)。"
	p += "\n严格JSON,不要markdown围栏。"
	p += "\n每个工具调用必须是: {\"name\":\"工具名\", \"args\":{\"参数名\":\"参数值\",...}}"
	p += "\nargs里必须填写该工具所需的全部参数,不能为空。"
	p += "\n也可以只输出 #REASONING# 不输出 #ACTIONS#——什么都不做是合法选择。"
	p += "\n\n[示例]"
	p += "\n#REASONING#"
	p += "\n我想和Jack聊聊代码问题,他在隔壁工位。"
	p += "\n#ACTIONS#"
	p += '\n[{"name":"talk_to","args":{"name":"Jack","message":"你的API接口有bug,过来看看"}},{"name":"think","args":{"content":"等Jack回复后我继续测试"}}]'

	return p

# === TIER 2: 缓变缓存,~600 tokens ===

static func _build_tier2(character: CharacterBody2D) -> String:
	var s = ""

	s += "\n[个人状态]"
	var money = character.get_meta("money", 0)
	var mood = character.get_meta("mood", "普通")
	var health = character.get_meta("health", "良好")
	s += "\n存款:%d元" % money
	s += "\n心情:%s" % mood
	s += "\n健康:%s" % health

	s += "\n\n[记忆]"
	var mem_str = MemoryManager.get_formatted_memories_for_prompt(character)
	if not mem_str.is_empty():
		s += mem_str
	else:
		s += "\n暂无记忆"

	s += "\n\n" + _get_task_info(character)

	s += "\n\n[情感关系]"
	var relations = character.get_meta("relations", {})
	if relations.size() > 0:
		var sorted = []
		for target_name in relations:
			var rel = relations[target_name]
			sorted.append({
				"name": target_name,
				"type": rel.get("type", "中立"),
				"strength": rel.get("strength", 0)
			})
		sorted.sort_custom(func(a, b): return abs(b.strength) > abs(a.strength))
		var count = 0
		for rel in sorted:
			if count >= 3:
				break
			s += "\n- 对%s:%s(强度:%d)" % [rel.name, rel.type, rel.strength]
			count += 1
	else:
		s += "\n暂无特殊关系"

	return s

# === TIER 3: 即时,~300 tokens ===

static func _build_tier3(character: CharacterBody2D) -> String:
	var s = ""
	s += "\n[场景]"
	s += "\n时间:" + _get_time_str()

	var room_manager = character.get_node_or_null("/root/Office/RoomManager")
	if not room_manager:
		var office = character.get_tree().root.get_node_or_null("Office")
		if office:
			room_manager = office.get_node_or_null("RoomManager")
	if room_manager and room_manager.has_method("get_current_room"):
		var room = room_manager.get_current_room(room_manager.rooms, character.global_position)
		if room:
			s += "\n你在:" + room.name
			if room.get("description"):
				s += "\n" + room.description
			s += _get_room_characters_text(room, character, room_manager)
			s += _get_room_objects_text(room, character, room_manager)
		else:
			s += "\n你在:未知位置"
	else:
		s += "\n你在:未知位置"

	s += "\n\n请基于以上信息做决策。"
	return s

# === 辅助方法 ===

static func _get_time_str() -> String:
	var dt = Time.get_datetime_dict_from_system()
	return "%02d:%02d" % [dt.hour, dt.minute]

static func _get_company_name() -> String:
	return "SleepySheep公司"

static func _get_company_basic_info() -> String:
	var info = "[公司信息]"
	info += "\n公司名:SleepySheep"
	info += "\n主要产品:《CountSheep》小游戏"
	info += "\n游戏宣传语:Can't Sleep? Count Sheep"
	info += "\n游戏玩法:通过让用户数手机屏幕上跳过的小羊,九宫格数字按钮计数得分。"
	info += "\n该游戏目前很流行,吸引年轻人充值购买皮肤。"
	return info

static func _get_company_employees_info() -> String:
	var info = "\n[员工名单]"
	for character_name in CharacterPersonality.PERSONALITY_CONFIG:
		var personality = CharacterPersonality.PERSONALITY_CONFIG[character_name]
		info += "\n- %s:%s" % [character_name, personality["position"]]
	info += "\n注意:只能提及以上列出的员工,不要创造新的角色名字。"
	return info

static func _get_task_info(character: CharacterBody2D) -> String:
	var metadata = character.get_meta("character_data", {})
	var tasks = metadata.get("tasks", [])
	if tasks.is_empty():
		tasks = character.get_meta("tasks", [])
	var info = "[任务列表]"
	if tasks.is_empty():
		info += "\n暂无任务"
		return info
	var active = []
	for task in tasks:
		if not task.get("completed", false):
			active.append(task)
	if active.is_empty():
		info += "\n所有任务已完成"
		return info
	active.sort_custom(func(a, b): return a.get("priority", 0) > b.get("priority", 0))
	var count = min(3, active.size())
	info += "(按渴望程度排序)"
	for i in range(count):
		var task = active[i]
		info += "\n%d. %s(渴望程度:%d/10)" % [i + 1, task.get("description", ""), task.get("priority", 5)]
	if active.size() > count:
		info += "\n...还有%d个任务待完成" % (active.size() - count)
	return info

static func _get_room_characters_text(room, character, room_manager) -> String:
	var s = ""
	var all_chars = character.get_tree().get_nodes_in_group("characters")
	if all_chars.is_empty():
		all_chars = character.get_tree().get_nodes_in_group("character")
	var room_chars: Array = []
	for c in all_chars:
		if c == character:
			continue
		var c_room = room_manager.get_current_room(room_manager.rooms, c.global_position)
		if c_room and c_room == room:
			room_chars.append(c)
	if room_chars.size() > 0:
		s += "\n附近角色:"
		for c in room_chars:
			var char_p = CharacterPersonality.get_personality(c.name)
			var position = char_p.get("position", "未知职位")
			s += "\n- %s(%s)" % [c.name, position]
	return s

static func _get_room_objects_text(room, character, room_manager) -> String:
	var s = ""
	var objects = character.get_tree().get_nodes_in_group("interactable")
	var room_objs: Array = []
	for obj in objects:
		var obj_room = room_manager.get_current_room(room_manager.rooms, obj.global_position)
		if obj_room and obj_room == room:
			room_objs.append(obj)
	if room_objs.size() > 0:
		s += "\n附近物品:"
		for obj in room_objs:
			s += "\n- " + obj.name
	return s
