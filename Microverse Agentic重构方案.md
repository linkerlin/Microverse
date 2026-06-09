# Microverse Agentic 重构方案

> 配套文档:本文是《Microverse架构分析》.md 和《Microverse改进方案》.md 的第三篇。前两篇承认"多选题 prompt 范式"是项目最大的设计债务;本文给出**怎么还债**。
> 范围:仅覆盖两个相关主题——**Agentic 范式重构**(tool use + 自由推理)、**Context Cache 重构**(成本引擎)。其他改进项继续看原方案。
> 立场:不再"反自由但极稳",改为"约束行为边界,释放推理空间"。

---

## 0. 这份文档的来历

写完前两份文档后,被 步子哥 提了两个问题:

1. "当前的设计是否不够 Agentic?似乎低估了 LLM 的能力。"
2. "另外也没有考虑 Context Cache 的作用。"

两个问题都问到了根子上。原方案里我把"多选题 prompt 范式"列为"最值得借鉴的 3 件事",这是**判断错误**——把 LLM 当 1-bit classifier 用,等于把 GPT-4 当 if-else 用。Context Cache 更是完全没碰,**意味着按当前 prompt 结构,跑 1 小时能烧掉 ¥20-30,跑 8 小时能烧掉一整月的开发者试用金**。

本文把"还债方案"落成具体设计。不是 PPT,是**代码侧能直接落地的设计**:每个段落都带 `file:line` 坐标、API 调用样例、token 估算。

---

## 1. 多选题范式的真实成本

先把"省"和"费"算清楚,后面才好权衡。

### 1.1 当前模式的开销账

`AIAgent.make_decision`(`script/ai/AIAgent.gd:488-558`)每次构造的 prompt:

| 段落 | 字符数(估) | Tokens(估) | 频率 |
|------|------------|------------|------|
| 人设 + 性格 | ~600 字 | ~300 | 每次 |
| 公司信息 | ~250 字 | ~120 | 每次 |
| 员工名单 | ~250 字 | ~120 | 每次 |
| 个人状态 | ~150 字 | ~75 | 每次 |
| 情感关系(8 个同事) | ~400 字 | ~200 | 每次 |
| 记忆(50 条) | ~1500 字 | ~750 | 每次 |
| 任务列表(top 3) | ~150 字 | ~75 | 每次 |
| 场景描述 | ~500 字 | ~250 | 每次 |
| 决策选项说明 | ~200 字 | ~100 | 每次 |
| **合计** | **~4000 字** | **~2000 tokens** | — |

`AIAgent._on_conversation_request_completed` 等对话类 prompt 类似规模(对话有聊天历史更长)。

### 1.2 真实输出 vs 浪费

每次决策 LLM 实际"工作"的量:
- 读完 ~2000 tokens 上下文
- 内部推理 ~500-1500 tokens
- **输出:1 token(数字 "1" 或 "2")**

**输入输出比 2000:1。** 就算 Claude 4.5 一秒钟能跑,内部推理是白做的——代码侧完全用不上。

按 8 角色 × 60s 决策周期 + 对话触发 + 移动决策,运行时估算:
- 基础决策:480 次/小时,每次 ~2000 in + 1 out
- 对话触发:平均每个角色每小时 1-2 段对话,每次 ~3000 in + 50 out
- 移动/任务决策:叠加 ~30%,每次 ~1500 in + 1 out
- **总 token 量:约 1.5-2.0M input / 小时,50-100K output / 小时**

按 DeepSeek 现价(¥1/M input,¥2/M output):
- input:¥1.5-2.0/小时
- output:¥0.1-0.2/小时
- **小计:¥1.6-2.2/小时**

玩家跑一下午(4 小时),成本 **¥6-9**。这不算便宜,还不算"长程记忆导致 token 越长越多"的趋势。

### 1.3 多选题范式真正省的是什么

省的是 **LLM 输出非确定性的兜底成本**。但 2024-2025 年的 LLM 已经稳定到**用 JSON schema + tool use 约束输出**,不需要再用"只输出数字 1"这种粗暴办法。

**结论**:多选题范式"省"的部分,在新的工程能力下**已经不该省**。

---

## 2. Agentic 重构:从"分类器"到"行动者"

### 2.1 设计目标

让 LLM 从"在 1-4 数字中挑一个"升级为"规划 1-3 步行动并执行"。要求:

- ✅ LLM 输出包含**完整推理链**,可被 debug 工具捕获
- ✅ LLM 可调用**任何数量、任何类型的工具**,不限于预定选项
- ✅ LLM 可在**一个回合**内连续调用多个工具
- ✅ 失败/幻觉有兜底,系统不卡死
- ✅ 单回合 token 成本 ≤ 当前多选题范式(input 增 10-20%,output 增 50-100%)

### 2.2 工具集设计

`script/ai/ToolRegistry.gd`(新文件):

```gdscript
class_name ToolRegistry
extends RefCounted

# 工具元数据 - 每家 LLM 厂商都能用
class Tool:
    var name: String
    var description: String
    var parameters: Dictionary  # JSON schema 风格
    var handler: Callable       # 实际执行函数

# 已注册工具
var _tools: Dictionary = {}

static func register(tool: Tool) -> void
static func get_definitions() -> Array[Dictionary]  # 转为各家厂商的 tool 格式
static func execute(name: String, args: Dictionary) -> Dictionary
```

首批工具(覆盖当前所有"动作"):

| 工具名 | 用途 | 替代当前的 |
|--------|------|------------|
| `move_to` | 移动到坐标或房间 | 决策选项 1 → `_execute_task_movement` |
| `talk_to` | 与某人对话 | 决策选项 2 → `initiate_conversation` |
| `think` | 内心独白(不显示给人) | `_execute_task_thinking` |
| `complete_task` | 标记任务完成 | 决策选项 4 → `_complete_task` |
| `adjust_tasks` | 调整/重排/添加任务 | 决策选项 1 → `_adjust_tasks` |
| `remember` | 写入记忆(可控重要度) | `_add_memory` |
| `observe` | 观察某人/某物,获取细节 | (新增) |
| `change_mood` | 修改心情 | (新增,需 GodUI 兼容) |

工具参数示例:

```gdscript
# 工具定义
var move_to = Tool.new(
    "move_to",
    "移动到目标位置。可以是坐标 (x, y),或者房间名(自动取中心)。",
    {
        "type": "object",
        "properties": {
            "target": {
                "type": "string",
                "description": "目标。格式: 'x,y' 或 房间名"
            },
            "reason": {
                "type": "string",
                "description": "移动原因(写入决策日志)"
            }
        },
        "required": ["target"]
    },
    Callable(self, "_handle_move_to")
)
```

### 2.3 Prompt 结构(Agentic 版)

替换 `AIAgent.make_decision`(`script/ai/AIAgent.gd:516-543`)的 prompt 拼接,新结构:

```
[SYSTEM - 永久稳定,可全量缓存]
你是 [character.name],SleepySheep 公司的 [position]。

[性格描述]
[speaking_style]
[work_duties]
[work_habits]

公司信息:[公司基本信息 + 员工名单]
当前故事背景:[BackgroundStoryManager.generate_background_prompt()]

[可用工具列表 - JSON schema]
[ToolRegistry.get_definitions()]

[输出格式要求]
- 必须先输出一段 reasoning(50-200 字,描述你为什么这么做)
- 然后输出 1-3 个 tool_call
- 严格使用 JSON,不要 markdown 围栏

# REASONING #
[你的思考]

# ACTIONS #
[{"name": "tool_name", "args": {...}}, ...]
```

**对比旧结构,几个关键变化:**

1. **不再有"选 1/2/3"指令**——LLM 自己决定
2. **推理段强制**——`# REASONING #` 让 LLM 必输出思考,debug 时一眼看到"他为什么这么做"
3. **actions 段可以是空数组**——LLM 可以"什么都不做",在某些场景下(角色在认真开会)这是正确选择
4. **工具定义是 prompt 的一部分**——而不是预埋在代码里,新增工具不用改 prompt

### 2.4 输出解析与执行

替换 `AIAgent._on_decision_request_completed`(`script/ai/AIAgent.gd:561-597`):

```gdscript
func _on_decision_request_completed(result, code, headers, body, char_node):
    var response = JSON.parse_string(body.get_string_from_utf8())
    if not response: return _default_fallback(char_node)
    
    var text = APIConfig.parse_response(current_settings.api_type, response)
    if text.is_empty(): return _default_fallback(char_node)
    
    # 新解析路径
    var parsed = _parse_agentic_response(text)
    var reasoning = parsed.get("reasoning", "")
    var actions = parsed.get("actions", [])
    
    # 写记忆:推理 + 行动
    if not reasoning.is_empty():
        MemoryManager.add_memory(
            char_node, "思考:" + reasoning,
            MemoryManager.MemoryType.PERSONAL,
            MemoryManager.MemoryImportance.NORMAL
        )
    
    # 串行执行 actions
    for action in actions:
        var result = ToolRegistry.execute(action.name, action.args, char_node)
        if not result.success:
            # 单个 tool 失败,记录但不中断
            MemoryManager.add_memory(char_node,
                "尝试 " + action.name + " 失败:" + result.error,
                MemoryManager.MemoryImportance.LOW
            )
    
    # 写入决策日志(给玩家看)
    print("[%s] 思考:%s 行动:%s" % [char_node.name, reasoning, actions])
```

`_parse_agentic_response` 的实现关键:

```gdscript
func _parse_agentic_response(text: String) -> Dictionary:
    # 1. 提取 # REASONING # 段
    var reasoning = ""
    var reasoning_match = _extract_section(text, "REASONING")
    if not reasoning_match.is_empty():
        reasoning = reasoning_match
    
    # 2. 提取 # ACTIONS # 段(必须 JSON)
    var actions = []
    var actions_text = _extract_section(text, "ACTIONS")
    if not actions_text.is_empty():
        actions = JSON.parse_string(actions_text)
        if actions == null: actions = []
    
    return {"reasoning": reasoning, "actions": actions}
```

**容错设计**:
- actions 不是合法 JSON → 当成空数组,角色本回合"什么都没做"
- 单个 tool 失败 → 记录到记忆,继续下一个
- 整个解析失败 → `_default_fallback` 走老路(随机选一个动作)

### 2.5 状态机扩展

`AIAgent.State` 枚举(`script/ai/AIAgent.gd:9-13`)扩展:

```gdscript
enum State {
    IDLE,
    MOVING,
    TALKING,
    LLM_BUSY,        # 新增:等 LLM 响应中
    EXECUTING_ACTIONS  # 新增:正在执行 tool call 链
}
```

替代当前的 `waiting_responses: Dictionary`(`AIAgent.gd:264`)字典。**好处**:状态机是可观测的,debug 时 `print(ai_agent.current_state)` 一眼看穿。

---

## 3. Context Cache 重构:成本引擎

### 3.1 三段式 prompt 切分

把当前 ~2000 token 的 prompt 切成三段,每段独立缓存:

```
[TIER 1: 5 分钟 TTL] ~1200 tokens
  - System prompt(人设 + 性格 + 说话风格 + 工作职责 + 工作习惯)
  - 公司信息 + 员工名单
  - 社会规则(从 BackgroundStoryManager)
  - 工具定义(ToolRegistry.get_definitions())
  
  特点:极少变化。玩家改人设才会变。

[TIER 2: 1 分钟 TTL] ~600 tokens
  - 个人状态(心情/健康/金钱/疾病)
  - top-5 记忆(按 importance 排序)
  - 当前任务列表(top-3)
  - 情感关系(top-3 关系)

  特点:缓慢变化。1 分钟内基本不动。

[TIER 3: 0 TTL / 无缓存] ~300 tokens
  - 场景描述(当前房间 + 附近物品 + 附近角色)
  - 时间
  - 玩家最近一次指令(如果有)

  特点:每次必变。
```

**关键**:三段在 API 层是**独立参数**。Anthropic 的 `system: [{text: ..., cache_control: ephemeral}]`,OpenAI 的自动缓存(deepseek 同理),都按 prefix 命中。三段结构对各家都更友好。

### 3.2 各家 cache 适配

`APIConfig.build_request_data`(`script/ai/APIConfig.gd:187-224`)扩展:

```gdscript
# 新增:tiered prompt 结构
static func build_tiered_request(
    api_type: String,
    model: String,
    tier1: String,   # 5min cache
    tier2: String,   # 1min cache
    tier3: String,   # no cache
    reasoning: String = ""
) -> Dictionary:
    var provider = get_provider(api_type)
    match provider.request_format:
        "openai":
            return {
                "model": model,
                "messages": [
                    {"role": "system", "content": tier1 + "\n\n" + tier2},
                    {"role": "user", "content": tier3}
                ]
            }
        "claude":
            return {
                "model": model,
                "max_tokens": 1024,
                "system": [
                    {"type": "text", "text": tier1, "cache_control": {"type": "ephemeral"}},
                    {"type": "text", "text": tier2, "cache_control": {"type": "ephemeral", "ttl": "1min"}}
                ],
                "messages": [
                    {"role": "user", "content": tier3}
                ]
            }
        "gemini":
            return {
                "contents": [...],
                "cachedContent": tier1_hash,  # 假设有 cache key
                "systemInstruction": {"parts": [{"text": tier1 + "\n\n" + tier2}]}
            }
        _:
            return {}
```

具体每家的 cache 行为:

| 厂商 | 行为 | 节省 | 实施 |
|------|------|------|------|
| **Anthropic** | 显式 `cache_control: ephemeral`,默认 5min TTL,可加 `ttl: "1min"` | input 90% off | 改 `build_tiered_request` 加 system 数组 |
| **OpenAI** | 自动(>1024 token 自动命中),无 TTL 概念 | input 50% off | prefix 稳定就够,无需改 API |
| **DeepSeek** | 自动 cache hit,prefix 稳定 | input 60-90% off | 同 OpenAI,无 API 改 |
| **Gemini** | 显式 `cachedContent`(基于 hash) | input 75% off | 需计算 tier1 hash,API 复杂度高 |
| **KIMI / SiliconFlow** | 多数按 OpenAI 兼容,自动 | 类似 OpenAI | 同 OpenAI |

**关键改造**:`CharacterPromptBuilder`(Phase 2 那个待拆的)按 TIER 1/2/3 分段拼,每段独立字段。`AIAgent` 调用 `APIManager.generate_tiered_dialog(t1, t2, t3, character_name)`。

### 3.3 成本测算(改造后)

设 TIER 1 cache 命中率 95%,TIER 2 cache 命中率 70%,TIER 3 不缓存。

每次请求的有效 input token:
- TIER 1:1200 × 5% = 60(95% 走 cache,只算 5% 的非命中率)
- TIER 2:600 × 30% = 180
- TIER 3:300 × 100% = 300
- **总有效 input:540 tokens/请求**

对比当前的 2000 tokens/请求,**节省 73%**。

每小时 800 次请求:
- 改造前:1.6M tokens × ¥1/M = ¥1.6/小时
- 改造后:432K tokens × ¥1/M(DeepSeek)+ cache 命中部分按 10% 计费 ≈ ¥0.5/小时

**降本 70%。**

再加上 output 涨 50-100%(从 1 token 涨到 50-100 tokens),output 成本从 ¥0.1/小时涨到 ¥5-10/小时。**但是!**

output 也可以走 cache 的"补全缓存",Anthropic 还提供 `prompt-caching-2024-07-31` 的 prefix 缓存,即使每次决策的 reasoning 文本不同,**只要 prefix 一致,后面的输出 token 也会按 cache 价算**。这条对 DeepSeek 同样适用(他们的 output cache 在测试中)。

**总账**:从 ¥1.7-2.2/小时 → ¥0.5-1.0/小时(DeepSeek)或更低(Anthropic cache 更激进)。**再降 50%。**

### 3.4 cache 命中率怎么保

最危险的不是 cache 失效,是 **prompt 改一个字就全失效**。对策:

- TIER 1 内容**严格程序化生成**,不嵌入任何"当前时间""当前房间"这种动态字段
- TIER 2 包含的"top-5 记忆"是按 importance 排序的**稳定**的(任务完成后,top-5 才变)— 这条几乎天然契合 1 分钟 TTL
- TIER 3 完全独立,带"scene_signature"避免重复 prompt(同一房间同一状态合并请求)

代码侧加一个"cache 监控":

```gdscript
# APIManager 内
var _cache_hit_count: int = 0
var _cache_miss_count: int = 0

func _log_cache_usage(response: Dictionary, api_type: String):
    var usage = response.get("usage", {})
    var cache_read = usage.get("cache_read_input_tokens", 0)  # Anthropic
    if cache_read > 0:
        _cache_hit_count += 1
    else:
        _cache_miss_count += 1
    print("[APIManager] Cache hit rate: %d/%d (%.1f%%)" % [
        _cache_hit_count,
        _cache_hit_count + _cache_miss_count,
        100.0 * _cache_hit_count / (_cache_hit_count + _cache_miss_count + 1)
    ])
```

在 GodUI 加个"AI 成本监控"面板,实时显示 cache 命中率,玩家能感觉到"调了 prompt 之后 cache 掉到 30% 了",这是非常强的反馈回路。

---

## 4. 与原《Microverse改进方案》.md 的关系

需要把 改进方案 改两处:

### 4.1 优先级调整

| 原方案 C11(tool use) | 改为 |
|------|------|
| 长期(阶段 5) | **应做(阶段 2 末尾)** |

| 新增 C12(Context Cache 重构) | 描述 |
|------|------|
| 阶段 2 末尾,与 C11 并行 | 拆出 `CharacterPromptBuilder`,分段 prompt,适配各家 cache |

### 4.2 阶段 2 任务增量

原阶段 2 任务:
- C3 拆 AIAgent.gd
- C4 抽 CharacterPromptBuilder
- C6 显式 LLM_BUSY 态

**新增任务**:
- **C11** 写 `ToolRegistry.gd`,迁移现有 8 个决策路径为 tool
- **C11** `AIAgent.make_decision` 改为 tool-call 模式
- **C11** 加 `LLM_BUSY` / `EXECUTING_ACTIONS` 状态
- **C11** 容错:tool 失败、JSON 解析失败都有兜底
- **C12** `CharacterPromptBuilder` 改造为分段(t1/t2/t3)
- **C12** `APIManager` 加 `generate_tiered_dialog` 接口
- **C12** 各家 cache 适配:Anthropic 走 system[],OpenAI 走自动,DeepSeek 走自动,Gemini 走 cachedContent
- **C12** GodUI 加"AI 成本监控"面板,显示 cache 命中率

阶段 2 时间从 3-5 天 → **5-8 天**。

### 4.3 阶段 3 测试体系调整

- **新增 `test/unit/test_tiered_prompt.gd`**:断言 TIER 1 不含"position"、TIER 2 不含"scene"、TIER 3 只含场景信息
- **新增 `test/unit/test_tool_registry.gd`**:注册 3 个 mock tool,断言 `execute` 返回格式正确
- **新增 `test/integration/test_agentic_decision.gd`**:mock LLM 返回 reasoning + actions,断言 AIAgent 状态机正确切换

---

## 5. 验证方法

呼应偏好"通过单元测试验证代码行为"。

| 阶段 | 主要验证手段 | 关键指标 |
|------|------------|----------|
| Tool use 实现 | GUT 单测 + 手动跑场景 | mock LLM 返回 actions,断言 tool 真的被调用;tool 抛异常时,角色不卡死 |
| Context cache 适配 | GUT 单测 + 各厂商回归 | TIER 1 拼接结果去重后,3 次调用应命中 2 次 cache;Anthropic 响应里 `cache_read_input_tokens > 0` |
| 行为对比 | 同 prompt 跑 100 场景,A/B 对比 | 输出"成功率"(tool 真的被正确调用)≥ 95%;成本降 50%+ |
| 玩家体验 | 跑 1 小时 8 角色场景 | 单小时成本 ≤ ¥1(DeepSeek)或 ≤ ¥2(Anthropic);体感延迟无明显变化 |

**总验证成本估算**:3-4 天(测试编写 + 各厂商 LLM 回归)。

---

## 6. 风险与边界

**显式列出"不要做的事"**:

1. **不要把所有动作都做成 tool**。当前 8 个够覆盖 95% 场景,扩到 20+ 反而让 LLM 选错。先 8 个,等用户反馈再加。
2. **不要做"完全无 LLM 的 deterministic 模式"**。这条之前说过,这里再强调:agentic 重构不是为了"减少 LLM 使用",是为了**让 LLM 用得其所**。
3. **不要把 cache 命中率刷到 100%**。99% 命中就够,追求 100% 会让 prompt 失去灵活性。
4. **不要在 cache 改造中加"动态人设拼装"**——人设应该硬编码,改人设意味着 cache 失效。玩家想改人设 → 重启游戏(或显式 cache invalidation 按钮)。
5. **不要把 reasoning 输出到对话气泡**——那是内心独白,不是台词。reasoning 写到记忆,只输出 actions 的副作用。
6. **不要做"自适应 cache"**——别让 LLM 决定哪些内容该缓存,该缓存的由代码侧(按字段)决定。

**风险点**:
- Tool use 各家协议差异:OpenAI/Anthropic/DeepSeek 的 `tool_call` 字段名不同,需要 `APIConfig.parse_response` 适配。**预防**:先 OpenAI 跑通,再扩散。
- 输出变长后,LLM "啰嗦"的概率上升。**预防**:在 prompt 里加硬性约束"reasoning 50-200 字,actions ≤ 3 个"。
- Cache 命中率受 prompt 微调影响,任何 typo 都可能让 cache 掉 0。**预防**:TIER 1 用代码模板生成,禁止手工拼接。

---

## 7. 收尾:这两次修正的本质

原《Microverse架构分析》.md 和《Microverse改进方案》.md 的核心立场是"完成度高于平均水平的独立 LLM 沙箱"。**这个判断没错**。但"沙箱"本身可以有不同形态:

- 当前形态:**LLM 扮 NPC,玩家扮观众**。LLM 是装饰品,所有智能都靠预定义选项。
- 改造后形态:**LLM 扮真人,玩家扮上帝**。LLM 自己想、自己做,玩家介入是特例。

第二种才是"Agentic"该有的样子。

**给 步子哥 一个具体动作建议**:下次开工,**先做 C11(tool use),不做 C1(存档补全)**。原因:存档补全是 P0 但孤立,tool use 是 P0 且**会改变后续所有改造的形态**——先定型,后填缝。**经验法则:架构改造先于数据改造**。

附:是否需要把本文合并到《Microverse改进方案》.md?目前倾向**不合并**——本文是"修正案",独立成文更清楚地标记"这是新立场"。等改造落地,再合并归档。
