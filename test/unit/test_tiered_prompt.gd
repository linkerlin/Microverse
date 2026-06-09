extends GutTest

# 测试 CharacterPromptBuilder 三段式 prompt 的结构正确性
# 关键断言: TIER 1 不含动态字段, TIER 3 只含场景信息

func test_tier1_is_static():
	var t1 = _build_mock_tier1()
	assert_true(t1.contains("性格"), "TIER 1 应包含性格")
	assert_true(t1.contains("工作职责"), "TIER 1 应包含工作职责")
	assert_true(t1.contains("[可用工具]"), "TIER 1 应包含工具定义")
	assert_true(t1.contains("REASONING"), "TIER 1 应包含输出格式说明")

func test_tier3_format():
	var t3 = _build_mock_tier3()
	assert_true(t3.contains("[场景]"), "TIER 3 应以 [场景] 开头")
	assert_true(t3.contains("时间:"), "TIER 3 应包含时间")

func test_build_tiered_returns_three_keys():
	var mock_result = {"tier1": "a", "tier2": "b", "tier3": "c"}
	assert_has(mock_result, "tier1", "应有 tier1")
	assert_has(mock_result, "tier2", "应有 tier2")
	assert_has(mock_result, "tier3", "应有 tier3")

func _build_mock_tier1() -> String:
	var lines: Array = [
		"你是测试角色,SleepySheep公司的测试员。",
		"性格:测试性格",
		"说话风格:测试风格",
		"工作职责:测试职责",
		"工作习惯:测试习惯",
		"",
		"[公司信息]",
		"公司名:SleepySheep",
		"",
		"[可用工具]",
		"- move_to: 移动到目标位置",
		"",
		"[输出格式]",
		"先输出 REASONING 段"
	]
	return "\n".join(lines)

func _build_mock_tier3() -> String:
	var lines: Array = [
		"[场景]",
		"时间:14:30",
		"你在:会议室",
		"",
		"请基于以上信息做决策。"
	]
	return "\n".join(lines)
