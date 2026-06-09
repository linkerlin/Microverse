class_name AgentSandbox
extends RefCounted

# AgentSandbox — LLM 能看到的全部世界
# Gen 2: ToolRegistry 的 handler 转发到这些方法
# Gen 3: LLM 直接写 GDScript 调用这些方法
# 安全模型:不暴露 OS / FileAccess / Engine 任何符号

var self_char: CharacterBody2D
var nearby: Array = []
var current_room = null
var tasks: Array = []
var memories: Array = []
var time_str: String = ""
var _room_manager: Node = null

func setup(char_node: CharacterBody2D, room_manager: Node) -> void:
	self_char = char_node
	_room_manager = room_manager

# === 工具方法 ===

func move_to(target) -> Dictionary:
	if target is Vector2:
		if self_char and self_char.has_method("move_to"):
			self_char.move_to(target)
			return {"ok": true, "action": "move_to", "target": [target.x, target.y]}
		return {"ok": false, "error": "no_move_method"}
	elif target is String:
		return _move_to_named_target(target)
	return {"ok": false, "error": "invalid_target_type"}

func _move_to_named_target(target_name: String) -> Dictionary:
	if target_name.is_empty():
		return {"ok": false, "error": "empty_target"}
	if "," in target_name:
		var parts = target_name.split(",")
		if parts.size() >= 2:
			var x = parts[0].strip_edges().to_float()
			var y = parts[1].strip_edges().to_float()
			return move_to(Vector2(x, y))
	if _room_manager and _room_manager.rooms.has(target_name):
		var room = _room_manager.rooms[target_name]
		if self_char and self_char.has_method("move_to"):
			self_char.move_to(room.position)
			return {"ok": true, "action": "move_to", "room": target_name}
		return {"ok": false, "error": "no_move_method"}
	var found = _find_target_by_name(target_name)
	if not found.is_empty():
		var pos = found.target.global_position if found.target is Node2D else found.target.position
		if self_char and self_char.has_method("move_to"):
			self_char.move_to(pos)
			return {"ok": true, "action": "move_to", "name": target_name}
	return {"ok": false, "error": "target_not_found:" + target_name}

func talk_to(name: String, message: String = "") -> Dictionary:
	var target = _find_character_by_name(name)
	if not target:
		return {"ok": false, "error": "no_such_character:" + name}
	var dialog_manager = Engine.get_singleton("DialogManager") if Engine.has_singleton("DialogManager") else null
	if not dialog_manager:
		var dm = self_char.get_tree().root.get_node_or_null("DialogManager")
		if dm:
			dialog_manager = dm
	if not dialog_manager:
		return {"ok": false, "error": "dialog_manager_unavailable"}
	var current_room = _get_current_room()
	var target_room = _get_room_at(target.global_position)
	if current_room != target_room and self_char.has_method("move_to"):
		self_char.move_to(target.global_position)
		return {"ok": true, "action": "moving_to_talk", "name": name, "message": "正在前往交谈"}
	var char_manager = self_char.get_tree().root.get_node_or_null("CharacterManager")
	if char_manager:
		char_manager.current_character = self_char
	if dialog_manager.has_method("_try_start_conversation"):
		dialog_manager._try_start_conversation()
	return {"ok": true, "action": "talk_to", "name": name}

func think(content: String) -> Dictionary:
	if content.is_empty():
		return {"ok": false, "error": "empty_content"}
	MemoryManager.add_memory(
		self_char, content,
		MemoryManager.MemoryType.PERSONAL,
		MemoryManager.MemoryImportance.LOW
	)
	return {"ok": true, "stored": true}

func remember(content: String, importance: int = 5) -> Dictionary:
	if content.is_empty():
		return {"ok": false, "error": "empty_content"}
	var imp = importance
	imp = max(1, min(10, imp))
	MemoryManager.add_memory(
		self_char, content,
		MemoryManager.MemoryType.PERSONAL,
		imp
	)
	return {"ok": true, "stored": true, "importance": imp}

func complete_task(task_id: String) -> Dictionary:
	var metadata = self_char.get_meta("character_data", {})
	var task_list = metadata.get("tasks", [])
	for task in task_list:
		var tid = str(task.get("created_at", ""))
		if tid == task_id:
			task["completed"] = true
			task["completed_at"] = Time.get_unix_time_from_system()
			metadata["tasks"] = task_list
			self_char.set_meta("character_data", metadata)
			return {"ok": true, "completed": task.get("description", "")}
		if task.get("description", "") == task_id:
			task["completed"] = true
			task["completed_at"] = Time.get_unix_time_from_system()
			metadata["tasks"] = task_list
			self_char.set_meta("character_data", metadata)
			return {"ok": true, "completed": task.get("description", "")}
	return {"ok": false, "error": "no_such_task:" + task_id}

func adjust_tasks(actions: Array) -> Dictionary:
	if actions.is_empty():
		return {"ok": false, "error": "no_actions"}
	var metadata = self_char.get_meta("character_data", {})
	var task_list = metadata.get("tasks", [])
	var applied = 0
	for action in actions:
		if not action is Dictionary:
			continue
		var op = action.get("op", "")
		match op:
			"reorder":
				var from_idx = int(action.get("from", -1))
				var to_idx = int(action.get("to", -1))
				if from_idx >= 0 and from_idx < task_list.size() and to_idx >= 0 and to_idx < task_list.size():
					var moved = task_list.pop_at(from_idx)
					task_list.insert(to_idx, moved)
					applied += 1
			"add":
				var desc = action.get("description", "")
				var pri = int(action.get("priority", 5))
				if not desc.is_empty():
					task_list.append({
						"description": desc,
						"priority": max(1, min(10, pri)),
						"created_at": Time.get_unix_time_from_system(),
						"completed": false
					})
					applied += 1
			"set_priority":
				var idx = int(action.get("index", -1))
				var pri = int(action.get("priority", 5))
				if idx >= 0 and idx < task_list.size():
					task_list[idx]["priority"] = max(1, min(10, pri))
					applied += 1
			"complete":
				var idx = int(action.get("index", -1))
				if idx >= 0 and idx < task_list.size():
					task_list[idx]["completed"] = true
					task_list[idx]["completed_at"] = Time.get_unix_time_from_system()
					applied += 1
			_:
				pass
	task_list.sort_custom(func(a, b): return a.get("priority", 0) > b.get("priority", 0))
	metadata["tasks"] = task_list
	self_char.set_meta("character_data", metadata)
	if applied > 0:
		MemoryManager.add_memory(self_char,
			"你调整了任务列表,应用了%d个操作。" % applied,
			MemoryManager.MemoryType.TASK,
			MemoryManager.MemoryImportance.NORMAL
		)
	return {"ok": true, "applied": applied}

func observe(target: String) -> Dictionary:
	if target.is_empty():
		return _observe_self()
	var found = _find_character_by_name(target)
	if found:
		return {
			"ok": true,
			"type": "character",
			"name": found.name,
			"mood": found.get_meta("mood", "普通"),
			"health": found.get_meta("health", "良好"),
			"position": [found.global_position.x, found.global_position.y]
		}
	if _room_manager:
		for room_name in _room_manager.rooms:
			if room_name.to_lower() == target.to_lower():
				var room = _room_manager.rooms[room_name]
				return {
					"ok": true,
					"type": "room",
					"name": room.name,
					"description": room.description if room.get("description") else "",
					"position": [room.position.x, room.position.y]
				}
	return {"ok": false, "error": "nothing_to_observe:" + target}

func _observe_self() -> Dictionary:
	return {
		"ok": true,
		"type": "self",
		"name": self_char.name,
		"mood": self_char.get_meta("mood", "普通"),
		"health": self_char.get_meta("health", "良好"),
		"money": self_char.get_meta("money", 0),
		"position": [self_char.global_position.x, self_char.global_position.y]
	}

func change_mood(mood: String, reason: String = "") -> Dictionary:
	if mood.is_empty():
		return {"ok": false, "error": "empty_mood"}
	self_char.set_meta("mood", mood)
	if not reason.is_empty():
		MemoryManager.add_memory(self_char,
			"你的心情变成了%s,因为%s。" % [mood, reason],
			MemoryManager.MemoryType.PERSONAL,
			MemoryManager.MemoryImportance.NORMAL
		)
	return {"ok": true, "mood": mood}

func wait(reason: String = "") -> Dictionary:
	if not reason.is_empty():
		MemoryManager.add_memory(self_char,
			"你选择等待:%s" % reason,
			MemoryManager.MemoryType.PERSONAL,
			MemoryManager.MemoryImportance.LOW
		)
	return {"ok": true, "action": "wait"}

# === 内部辅助 ===

func _find_character_by_name(char_name: String) -> CharacterBody2D:
	if not self_char:
		return null
	var all_chars = self_char.get_tree().get_nodes_in_group("characters")
	if all_chars.is_empty():
		all_chars = self_char.get_tree().get_nodes_in_group("character")
	for c in all_chars:
		if c == self_char:
			continue
		if c.name.to_lower() == char_name.to_lower():
			return c
		if c.name.to_lower().contains(char_name.to_lower()) or char_name.to_lower().contains(c.name.to_lower()):
			return c
	return null

func _find_target_by_name(target_name: String) -> Dictionary:
	if not _room_manager or not self_char:
		return {}
	var current_room = _get_current_room()
	if current_room:
		var room_chars = _get_room_characters(current_room)
		for c in room_chars:
			if c.name.to_lower().contains(target_name.to_lower()) or target_name.to_lower().contains(c.name.to_lower()):
				return {"type": "character", "target": c}
		var room_objects = _get_room_objects(current_room)
		for obj in room_objects:
			if obj.name.to_lower().contains(target_name.to_lower()) or target_name.to_lower().contains(obj.name.to_lower()):
				return {"type": "object", "target": obj}
	for room_name in _room_manager.rooms:
		var room = _room_manager.rooms[room_name]
		if room.name.to_lower().contains(target_name.to_lower()) or target_name.to_lower().contains(room.name.to_lower()):
			return {"type": "room", "target": room}
	return {}

func _get_current_room():
	if not _room_manager or not self_char:
		return null
	return _room_manager.get_current_room(_room_manager.rooms, self_char.global_position)

func _get_room_at(pos: Vector2):
	if not _room_manager:
		return null
	return _room_manager.get_current_room(_room_manager.rooms, pos)

func _get_room_characters(room) -> Array:
	if not room or not _room_manager:
		return []
	var result: Array = []
	var all_chars = self_char.get_tree().get_nodes_in_group("characters")
	if all_chars.is_empty():
		all_chars = self_char.get_tree().get_nodes_in_group("character")
	for c in all_chars:
		if c == self_char:
			continue
		var char_room = _get_room_at(c.global_position)
		if char_room and char_room == room:
			result.append(c)
	return result

func _get_room_objects(room) -> Array:
	if not room or not _room_manager or not self_char:
		return []
	var result: Array = []
	var objects = self_char.get_tree().get_nodes_in_group("interactable")
	for obj in objects:
		var obj_room = _get_room_at(obj.global_position)
		if obj_room and obj_room == room:
			result.append(obj)
	return result
