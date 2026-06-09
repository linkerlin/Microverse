# Microverse Agentic 方案 v2

> 第四份文档的前三份是:《架构分析》《改进方案》《Gen3 GDScript 沙箱》。这份 v2 把《Agentic 重构方案》(Gen 2)和《Gen3》的结论合到一起,修掉初版的五个硬伤,补上三块缺角。
>
> 初版哪里有问题?往下看。

---

## 0. 旧版犯了什么错

写初版的时候犯了五个错,现在逐个摊开:

**错一:把"tool call"当成终点。** 初版把 Gen 2 JSON tool call 写成"Agentic 重构的终态",其实它只是过渡态。Gen 3(闭包执行)才是这条线的上限——把这一点藏进另一份文档,让读者以为 Gen 2 就是全部。

**错二:9 家厂商适配只给了伪代码。** `build_tiered_request` 里 Gemini 那格写了 `cachedContent: tier1_hash` 加了句"假设有 cache key"——这不是设计,是占位符。9 家厂商里有 7 家走 OpenAI 兼容格式,剩下 Claude 和 Gemini 的 cache 机制完全不同,必须分开写死。

**错三:Context Cache 和 tool call 是两条平行线。** 初版先讲完 tool call 再讲 cache,读起来像两篇独立文章拼在一起。实际上 cache 不是"可选优化"——它是 tool call 能跑起来的经济前提。output 从 1 token 涨到 50-100 token 之后,不压 input 成本根本玩不下去。这俩应该捏成一个整体。

**错四:ToolRegistry 的"8 个 tool 够了"太武断。** 8 个 tool 覆盖的是 Gen 1 的 4 个选项(1→调整任务,2→继续任务)加几个细粒度拆分。但当前代码里角色还能"对话""观察""写记忆""改心情",这些在 prompt 里用自然语言描述、靠 LLM 自己选择数字来隐式触发。Gen 2 应该显式定义这些能力,同时给 Gen 3 留好接口。

**错五:缺 Gen 2→Gen 3 的复用路径。** 初版说"Gen 2 先做,Gen 3 以后再说",但没写清楚两代共享哪些代码、怎么从 Gen 2 平滑迁移到 Gen 3。结果 Gen 3 文档里突然冒出 `AgentSandbox` 类,和 Gen 2 的 `ToolRegistry` 毫无衔接。

下面是修正后的方案。不长,但每个判断都带了代码坐标和账本。

---

## 1. 三代坐标,一次说清

| 代 | 范式 | LLM 输出 | 状态机新态 | Context Cache 命中率 |
|----|------|----------|------------|---------------------|
| Gen 1(当前) | 多选题 1/2 | 1 token | 无(靠字典) | ~0%(每次全量重发) |
| **Gen 2** | **JSON tool call** | **50-100 tokens** | **LLM_BUSY + EXECUTING** | **~75-85%** |
| Gen 3(opt-in) | GDScript 闭包 | 200-400 tokens | +SANDBOX_RUNNING | ~90%+ |

Gen 2 是这篇文章的主体。Gen 3 的复用接口写在第 8 节,完整设计看《Gen3 GDScript 沙箱》。

---

## 2. 成本账:为什么非改不可

### 2.1 当前开销

`AIAgent.make_decision`(`script/ai/AIAgent.gd:488-558`)每次拼的 prompt:

| 段落 | 字符 | Token 估 | 频率 |
|------|------|----------|------|
| 人设+性格+说话风格+职责+习惯 | ~600 | ~300 | 每次 |
| 公司信息+员工名单 | ~500 | ~240 | 每次 |
| 个人状态(心情/健康/金钱) | ~150 | ~75 | 每次 |
| 情感关系(8 个同事) | ~400 | ~200 | 每次 |
| 记忆(上限 50 条) | ~1500 | ~750 | 每次 |
| 任务(top 3) | ~150 | ~75 | 每次 |
| 场景描述 | ~500 | ~250 | 每次 |
| 决策选项说明 | ~200 | ~100 | 每次 |
| **合计** | **~4000** | **~2000** | — |

`AIAgent._on_conversation_request_completed` 的对话类 prompt 规模接近,但多了聊天历史,实际更长。

关键数字:LLM 读完 2000 token 上下文,内部推理 500-1500 token,最终输出 **1 token**——一个数字"1"或"2"。

输入输出比 2000:1。

### 2.2 运行时估算

8 角色 × 60 秒决策周期 + 对话 + 移动:

- 基础决策:480 次/小时,每次 ~2000 in + 1 out
- 对话触发:每角色每小时 1-2 段,每次 ~3000 in + 50 out
- 叠加移动/任务:~30% 额外,每次 ~1500 in + 1 out
- **总 token:约 1.5-2.0M input/小时 + 50-100K output/小时**

DeepSeek 现价(¥1/M input,¥2/M output):¥1.6-2.2/小时。

玩家跑一下午 4 小时:¥6-9。一整天:¥15-20。

这价格不致命,但有两个趋势会让它恶化:
- 记忆系统有 50 条上限,跑到中后期记忆条目会变长,prompt 膨胀到 ~3000 token
- 对话历史是累计的,两个角色长聊 5 轮,input 直接翻倍

### 2.3 为什么不直接砍 prompt

砍掉 50 条记忆降到 10 条?可以。但 `MemoryManager`(`script/ai/memory/MemoryManager.gd:1-175`)的设计是 "IMPORTANCE 排序 + 超出上限淘汰最不重要"——砍到 10 条会丢掉 LLM 对"上周被 Jack 骂了"这类长程记忆的引用,角色行为会变笨。

砍情感关系?不行,`ConversationManager`(`script/ai/ConversationManager.gd:188-253`)的对话递归回环里,情感值直接影响 LLM 是否愿意继续聊。砍了,对话质量塌方。

**砍不了。**

---

## 3. Context Cache:不是优化,是前提

先写 cache,再写 tool call。

不是因为这个顺序更好读——是因为 tool call 把 output 从 1 token 拉到 50-100 token 之后,input 成本不压下去,总成本反而会涨。cache 不是锦上添花,是 tool call 能跑起来的经济前提。

### 3.1 三段式切分

把 ~2000 token 的 prompt 切成三个独立缓存段:

```
[TIER 1: 5 分钟 TTL] ~1200 tokens
  - System prompt(人设 + 性格 + 说话风格 + 职责 + 习惯)
  - 公司信息 + 员工名单
  - 社会规则(BackgroundStoryManager)
  - 工具定义(ToolRegistry.get_definitions()) ← Gen 2 新增

  稳定性:极高。只在玩家改人设时才变。

[TIER 2: 1 分钟 TTL] ~600 tokens
  - 个人状态(心情/健康/金钱/疾病)
  - top-5 记忆(按 importance 排序)
  - 当前任务列表(top-3)
  - 情感关系(top-3 最强关系)

  稳定性:中等。1 分钟内基本不动。
  top-5 记忆在任务完成后才会变化,天然契合 1 分钟 TTL。

[TIER 3: 0 TTL / 不缓存] ~300 tokens
  - 场景描述(当前房间 + 附近物品 + 附近角色)
  - 时间
  - 玩家最近一次指令(如果有)

  稳定性:每次都变。
```

三段在 API 层是独立的。Anthropic 的 `system: [{text, cache_control}]` 是数组,OpenAI 系按前缀自动匹配。拆成三段,对各家都更友好。

### 3.2 九家厂商的 cache 实现

当前 `APIConfig`(`script/ai/APIConfig.gd:44-157`)注册了 9 家厂商。7 家走 OpenAI 兼容格式(`request_format: "openai"`),Claude 和 Gemini 各自独立。

**OpenAI 系(7 家):OpenAI, DeepSeek, 豆包, KIMI, SiliconFlow, OpenAICompatible, Ollama**

这 7 家共享同一个 JSON 结构。cache 行为:

| 厂商 | cache 行为 | 改造量 |
|------|-----------|--------|
| OpenAI | >1024 token 自动 prefix cache,50% off | **零**。prefix 稳定就够 |
| DeepSeek | 自动 prefix cache,60-90% off | **零**。同上 |
| 豆包 | 兼容 OpenAI,自动 prefix | **零** |
| KIMI | 兼容 OpenAI | **零** |
| SiliconFlow | 兼容 OpenAI | **零** |
| Ollama | 本地无 cache,但也无成本 | **零** |
| OpenAICompatible | 取决于后端 | **零** |

也就是说,7 家 OpenAI 系的 cache 改造,工作量在 prompt 拼接层,不在 API 层。

```gdscript
# script/ai/agent/CharacterPromptBuilder.gd (新文件)
class_name CharacterPromptBuilder
extends RefCounted

static func build_tiered(character: CharacterBody2D) -> Dictionary:
    var t1 = _build_tier1(character)   # 1200 token, 极少变
    var t2 = _build_tier2(character)   # 600 token, 缓变
    var t3 = _build_tier3(character)   # 300 token, 每次变
    return {"tier1": t1, "tier2": t2, "tier3": t3}

static func _build_tier1(character) -> String:
    # 严格程序化生成,不含任何动态字段
    var personality = CharacterPersonality.get_personality(character.name)
    var p = "你是%s,%s的%s。" % [
        character.name,
        CompanyInfo.get_company_name(),
        personality["position"]
    ]
    p += "\n性格:" + personality["personality"]
    p += "\n说话风格:" + personality["speaking_style"]
    p += "\n工作职责:" + personality["work_duties"]
    p += "\n工作习惯:" + personality["work_habits"]
    p += "\n\n" + get_company_basic_info()
    p += get_company_employees_info()
    p += BackgroundStoryManager.generate_background_prompt()
    p += "\n\n[可用工具]\n" + ToolRegistry.get_tool_descriptions()
    return p

static func _build_tier2(character) -> String:
    var s = get_character_status_info(character)   # 心情/健康/金钱
    s += get_top_memories(character, 5)             # importance 排序
    s += get_top_tasks(character, 3)                # 任务
    s += get_top_relations(character, 3)            # 情感关系
    return s

static func _build_tier3(character) -> String:
    return generate_scene_description(character) + "\n时间:" + TimeManager.get_time_str()
```

**Claude(Anthropic):显式 cache_control**

Claude 是唯一需要改 API 参数的厂商。它的 `system` 字段接受数组,每个元素可以带 `cache_control`:

```gdscript
# APIConfig.build_tiered_request 的 Claude 分支
"claude":
    return {
        "model": model,
        "max_tokens": 1024,
        "system": [
            {
                "type": "text",
                "text": tier1,
                "cache_control": {"type": "ephemeral"}
            },
            {
                "type": "text",
                "text": tier2,
                "cache_control": {"type": "ephemeral"}
            }
        ],
        "messages": [
            {"role": "user", "content": tier3}
        ]
    }
```

Claude 的 cache 价格:input 命中部分 90% off(即原价的 10%)。TIER 1 命中率 95% 意味着每 20 次请求只有 1 次需要全量计费。

**Gemini:cachedContent API**

Gemini 的 cache 机制和前两家完全不同。它需要先调用 `cachedContents.create` API 创建缓存,拿到一个 `cachedContent` ID,后续请求引用这个 ID:

```gdscript
# Gemini 的两步流程
# Step 1: 创建 cache(首次或 TIER 1 变更时)
static func _create_gemini_cache(api_key: String, model: String, tier1: String) -> String:
    var cache_body = {
        "model": "models/" + model,
        "contents": [{"role": "user", "parts": [{"text": tier1}]}],
        "ttl": "300s"   # 5 分钟
    }
    # POST https://generativelanguage.googleapis.com/v1beta/cachedContents
    # 返回 cachedContent.name 作为 cache_id
    return cache_id

# Step 2: 正常请求时引用 cache
"gemini":
    return {
        "model": "models/" + model,
        "cachedContent": _gemini_cache_id,  # 引用缓存
        "contents": [
            {"role": "user", "parts": [{"text": tier2 + "\n\n" + tier3}]}
        ]
    }
```

Gemini 的 cache 命中部分 75% off。需要在 `APIManager` 里维护一个 `_gemini_cache_id: String`,TIER 1 变更时重新创建。

### 3.3 成本测算(改造后)

TIER 1 命中率 95%,TIER 2 命中率 70%,TIER 3 不缓存。

每次请求的有效 input token:
- TIER 1: 1200 × 5% = 60
- TIER 2: 600 × 30% = 180
- TIER 3: 300 × 100% = 300
- **有效 input: 540 token/请求**

对比当前的 2000 token,**降 73%**。

每小时 800 次请求(DeepSeek):
- 改造前:1.6M token × ¥1/M = ¥1.6
- 改造后:432K × ¥1/M + cache 命中部分按折扣 ≈ ¥0.5
- **降本 ~70%**

但 Gen 2 的 output 涨了。1 token 变 50-100 token。DeepSeek output ¥2/M:
- output: 800 × 75 token × ¥2/M = ¥0.12/小时

净成本:¥0.5 + ¥0.12 ≈ **¥0.6/小时**。

对比改造前的 ¥1.7-2.2/小时,**降 70%**。

用 Claude 算一笔更狠的:cache 命中 90% off,input 成本压到约 ¥0.3/小时(Claude 单价高但折扣更大)。output 也更贵,总计约 ¥1.0-1.5/小时——仍然比当前低 40%。

### 3.4 cache 命中率的保障措施

最危险的事:改一个字,prefix 全部对不上,命中率直接归零。

对策:
1. **TIER 1 纯程序化生成**——`CharacterPromptBuilder._build_tier1` 用模板拼接,不嵌入时间、房间名等动态字段。改人设 → 整个 TIER 1 变 → cache 全失效,但这种情况极少(玩家手动改人设)。
2. **TIER 2 的"top-5 记忆"天然稳定**——记忆按 importance 排序,top-5 在 1 分钟内几乎不变。任务完成后 importance 重排,才会触发 TIER 2 变化。
3. **加 cache 监控**——`APIManager` 里统计 `cache_read_input_tokens`(Anthropic 响应里的字段),定期打印命中率。

```gdscript
# APIManager 新增
var _cache_stats: Dictionary = {"hits": 0, "misses": 0}

func _log_cache_usage(response_body: Dictionary, api_type: String) -> void:
    var usage = response_body.get("usage", {})
    # Anthropic
    if usage.get("cache_read_input_tokens", 0) > 0:
        _cache_stats.hits += 1
    elif usage.get("cache_creation_input_tokens", 0) > 0:
        _cache_stats.misses += 1
    # OpenAI 系(通过 total_tokens 与 input_tokens 差值推算)
    # ... 按厂商分别处理
```

在 `GodUI`(`script/ui/GodUI.gd`)加个"AI 成本"面板——实时显示 cache 命中率、本小时 token 消耗、预估费用。玩家改了 prompt 之后看到命中率掉到 30%,马上知道该检查。这个反馈回路比文档管用。

---

## 4. Tool Call:从分类器到行动者

### 4.1 设计目标

让 LLM 从"在 1 和 2 里挑一个"升级为"自己想、自己做"。几个硬指标:

- LLM 输出包含推理链(reasoning),可 debug
- LLM 可调用 1-3 个工具,不限于预定选项
- 工具可组合(先 observe 再 talk_to)
- 失败有兜底,系统不卡死
- 单回合 token 成本 ≤ 当前 × 1.2(input 增 10-20%,output 增 50-100%)

### 4.2 工具集

不是 8 个,是 10 个。覆盖 Gen 1 的全部行为,加上 Gen 2 新增的 observe/change_mood,再给 Gen 3 留复用接口。

| 工具名 | 用途 | 对应当前代码 | 参数 |
|--------|------|-------------|------|
| `move_to` | 移动到坐标或房间 | `_execute_task_movement` | `target: String, reason?: String` |
| `talk_to` | 与某人对话 | `initiate_conversation` | `name: String, message?: String` |
| `think` | 内心独白(不显示) | `_execute_task_thinking` | `content: String` |
| `complete_task` | 标记任务完成 | `_complete_task` | `task_id: String` |
| `adjust_tasks` | 重排/新增任务 | `_adjust_tasks` | `actions: Array` |
| `remember` | 写入记忆 | `_add_memory` | `content: String, importance: int` |
| `observe` | 观察某人获取细节 | (新增) | `target: String` |
| `change_mood` | 修改心情 | (新增) | `mood: String, reason: String` |
| `wait` | 本回合什么都不做 | (新增) | `reason?: String` |
| `interact_object` | 与场景物品互动 | (新增) | `object: String, action: String` |

后两个是 Gen 3 的复用接口。`wait` 让 LLM 可以显式选择"什么都不做",而不是靠输出空数组;`interact_object` 为场景物品互动留扩展口。

### 4.3 ToolRegistry 实现

```gdscript
# script/ai/agent/ToolRegistry.gd (新文件)
class_name ToolRegistry
extends RefCounted

class ToolDef:
    var name: String
    var description: String
    var parameters: Dictionary   # JSON schema
    var handler: Callable

var _tools: Dictionary = {}     # name -> ToolDef
var _sandbox: AgentSandbox       # Gen 3 复用时注入

func _init():
    # 每个工具的 handler 最终调用 AgentSandbox 的同名方法
    # Gen 2 通过 JSON dispatch,Gen 3 直接调 GDScript
    _register_all()

func _register_all() -> void:
    _reg("move_to", "移动到目标位置。target 可以是 'x,y' 坐标或房间名。",
        {"type": "object", "properties": {
            "target": {"type": "string", "description": "'x,y' 或房间名"},
            "reason": {"type": "string", "description": "移动原因(可选)"}
        }, "required": ["target"]},
        _handle_move_to)

    _reg("talk_to", "与某人开始对话。对方必须在附近。",
        {"type": "object", "properties": {
            "name": {"type": "string", "description": "对方名字"},
            "message": {"type": "string", "description": "开场白(可选)"}
        }, "required": ["name"]},
        _handle_talk_to)

    _reg("think", "内心独白。只有你自己知道,不会显示给其他角色。",
        {"type": "object", "properties": {
            "content": {"type": "string", "description": "思考内容"}
        }, "required": ["content"]},
        _handle_think)

    _reg("complete_task", "标记一个任务为已完成。",
        {"type": "object", "properties": {
            "task_id": {"type": "string", "description": "任务 ID"}
        }, "required": ["task_id"]},
        _handle_complete_task)

    _reg("adjust_tasks", "调整任务优先级或新增任务。",
        {"type": "object", "properties": {
            "actions": {"type": "array", "description": "调整动作列表"}
        }, "required": ["actions"]},
        _handle_adjust_tasks)

    _reg("remember", "把一条信息写入长期记忆。",
        {"type": "object", "properties": {
            "content": {"type": "string", "description": "记忆内容"},
            "importance": {"type": "integer", "description": "1-10,默认 5"}
        }, "required": ["content"]},
        _handle_remember)

    _reg("observe", "仔细观察某人或某物,获取详细信息。",
        {"type": "object", "properties": {
            "target": {"type": "string", "description": "目标名字"}
        }, "required": ["target"]},
        _handle_observe)

    _reg("change_mood", "主动调整自己的心情。",
        {"type": "object", "properties": {
            "mood": {"type": "string", "description": "新心情"},
            "reason": {"type": "string", "description": "原因"}
        }, "required": ["mood", "reason"]},
        _handle_change_mood)

    _reg("wait", "本回合什么都不做,等待。",
        {"type": "object", "properties": {
            "reason": {"type": "string", "description": "等待原因(可选)"}
        }, "required": []},
        _handle_wait)

func _reg(name: String, desc: String, params: Dictionary, handler: Callable) -> void:
    var tool = ToolDef.new()
    tool.name = name
    tool.description = desc
    tool.parameters = params
    tool.handler = handler
    _tools[name] = tool

func execute(tool_name: String, args: Dictionary, character: CharacterBody2D) -> Dictionary:
    if not _tools.has(tool_name):
        return {"ok": false, "error": "unknown_tool:%s" % tool_name}
    return _tools[tool_name].handler.call(args, character)

func get_tool_descriptions() -> String:
    # 生成给 LLM 看的工具列表文本(进 TIER 1)
    var lines: Array = []
    for name in _tools:
        var t = _tools[name]
        lines.append("- %s: %s 参数:%s" % [name, t.description, JSON.stringify(t.parameters)])
    return "\n".join(lines)

func get_openai_tools() -> Array:
    # 转为 OpenAI tool_call 格式
    var result: Array = []
    for name in _tools:
        var t = _tools[name]
        result.append({
            "type": "function",
            "function": {
                "name": t.name,
                "description": t.description,
                "parameters": t.parameters
            }
        })
    return result

# === 各 handler ===
# 每个 handler 最终调用的是 AgentSandbox 的同名方法
# 这里是 Gen 2 的 JSON→sandbox 转发层

func _handle_move_to(args: Dictionary, char: CharacterBody2D) -> Dictionary:
    if not _sandbox:
        # Gen 2 standalone:直接执行
        return _execute_move_direct(args, char)
    return _sandbox.move_to(args.get("target", ""))

func _handle_talk_to(args: Dictionary, char: CharacterBody2D) -> Dictionary:
    if not _sandbox:
        return _execute_talk_direct(args, char)
    return _sandbox.talk_to(args.get("name", ""), args.get("message", ""))

# ... 其余 handler 同理

# Gen 2 standalone 的直接执行(无 AgentSandbox)
func _execute_move_direct(args: Dictionary, char: CharacterBody2D) -> Dictionary:
    var target = args.get("target", "")
    if target.is_empty():
        return {"ok": false, "error": "empty_target"}
    # 复用 AIAgent 现有逻辑
    if "," in target:
        var parts = target.split(",")
        var pos = Vector2(float(parts[0]), float(parts[1]))
        char.get_node("CharacterController").move_to(pos)
        return {"ok": true}
    # 尝试按房间名
    if RoomManager.rooms.has(target):
        char.get_node("CharacterController").move_to(RoomManager.rooms[target].position)
        return {"ok": true}
    return {"ok": false, "error": "invalid_target:%s" % target}
```

### 4.4 Prompt 结构(Gen 2)

替换 `AIAgent.gd:516-543` 的字符串拼接:

```
[TIER 1]
你是 [name],[company] 的 [position]。
性格:[personality]
说话风格:[speaking_style]
工作职责:[work_duties]
工作习惯:[work_habits]

[公司信息 + 员工名单]
[BackgroundStoryManager 的故事背景]

[可用工具]
ToolRegistry.get_tool_descriptions()

[输出格式]
先输出 #REASONING# 段(50-200 字,描述你为什么这么做)
再输出 #ACTIONS# 段(JSON 数组,1-3 个工具调用)
严格 JSON,不要 markdown 围栏。
也可以只输出 #REASONING# 不输出 #ACTIONS#——什么都不做是合法选择。

[TIER 2]
[个人状态]
[记忆 top-5]
[任务 top-3]
[关系 top-3]

[TIER 3]
[场景描述]
[时间]

请基于以上信息做决策。
```

对比旧 prompt,几个关键变化:
1. 没有"请只回复数字 1 或 2"——LLM 自己决定
2. `#REASONING#` 强制输出思考——debug 时一眼看到"他为什么这么做"
3. actions 可以是空数组——角色可以"什么都不做"
4. 工具定义在 TIER 1 里——新增工具不改 prompt 结构

### 4.5 输出解析

替换 `AIAgent._on_decision_request_completed`(`script/ai/AIAgent.gd:561`):

```gdscript
func _on_decision_request_completed(result, code, headers, body, char_node):
    var response = JSON.parse_string(body.get_string_from_utf8())
    if not response:
        return _default_fallback(char_node)

    var text = APIConfig.parse_response(current_settings.api_type, response)
    if text.is_empty():
        return _default_fallback(char_node)

    var parsed = _parse_agentic_response(text)
    var reasoning = parsed.get("reasoning", "")
    var actions = parsed.get("actions", [])

    # 推理写记忆
    if not reasoning.is_empty():
        MemoryManager.add_memory(
            char_node, "思考:" + reasoning,
            MemoryManager.MemoryType.PERSONAL,
            MemoryManager.MemoryImportance.LOW
        )

    # 串行执行
    for action in actions:
        var tool_name = action.get("name", "")
        var tool_args = action.get("args", {})
        var exec_result = tool_registry.execute(tool_name, tool_args, char_node)
        if not exec_result.get("ok", false):
            MemoryManager.add_memory(char_node,
                "尝试 %s 失败:%s" % [tool_name, exec_result.get("error", "")],
                MemoryManager.MemoryImportance.LOW
            )

    _set_state(char_node, State.IDLE)
```

解析函数:

```gdscript
func _parse_agentic_response(text: String) -> Dictionary:
    var reasoning = _extract_section(text, "REASONING")
    var actions = []
    var actions_text = _extract_section(text, "ACTIONS")
    if not actions_text.is_empty():
        var parsed = JSON.parse_string(actions_text)
        if parsed != null and parsed is Array:
            actions = parsed
    return {"reasoning": reasoning, "actions": actions}

func _extract_section(text: String, marker: String) -> String:
    # 匹配 #MARKER# ... (到下一个 # 或文本末尾)
    var pattern = "#%s#\\s*([\\s\\S]*?)(?=#\\w+#|$)" % marker
    var regex = RegEx.create_from_string(pattern)
    var match = regex.search(text)
    if match:
        return match.get_string(1).strip_edges()
    return ""

func _default_fallback(char_node) -> void:
    # 兜底:随机选一个动作(Gen 1 的行为)
    var options = ["move_to", "think", "wait"]
    var choice = options[randi() % options.size()]
    match choice:
        "move_to":
            _execute_random_movement(char_node)
        "think":
            pass   # 什么都不做
        "wait":
            pass
```

### 4.6 容错设计

| 失败情况 | 处理 |
|----------|------|
| LLM 返回非文本(空/格式错) | `_default_fallback` 走 Gen 1 行为 |
| JSON 解析失败 | actions 为空,角色本回合不行动 |
| 单个 tool 不存在 | 记录到记忆,继续下一个 |
| 单个 tool 执行异常 | 记录到记忆,继续下一个 |
| 全部 tool 失败 | 角色本回合不行动,下回合重新决策 |

关键:任何单点失败都不会卡死系统。`_default_fallback` 兜底,角色总有行为。

---

## 5. 状态机扩展

`AIAgent.State`(`script/ai/AIAgent.gd:9-13`)当前只有 `IDLE`。扩展:

```gdscript
enum State {
    IDLE,
    MOVING,
    TALKING,
    LLM_BUSY,           # 等 LLM 响应
    EXECUTING_ACTIONS,   # 执行 tool call 链
}
```

替换当前的 `waiting_responses: Dictionary`(`AIAgent.gd:264`)。

状态机是显式的:`print(ai_agent.current_state)` 一眼看穿。`GodUI` 的"AI 调试"面板可以显示每个角色的当前状态。

状态转换:
```
IDLE → LLM_BUSY(发出请求)
LLM_BUSY → EXECUTING_ACTIONS(收到响应,开始执行)
EXECUTING_ACTIONS → IDLE(执行完毕)
EXECUTING_ACTIONS → TALKING(talk_to 触发对话)
TALKING → IDLE(对话结束)
IDLE → MOVING(move_to 触发移动)
MOVING → IDLE(到达目标)
```

---

## 6. API 层改造

### 6.1 APIConfig 新增

`APIConfig`(`script/ai/APIConfig.gd`)当前只有 `build_request_data`。新增:

```gdscript
static func build_tiered_request(
    api_type: String,
    model: String,
    tier1: String,
    tier2: String,
    tier3: String,
    api_key: String = ""
) -> Dictionary:
    var provider = get_provider(api_type)
    match provider.request_format:
        "openai":
            return _build_openai_tiered(model, tier1, tier2, tier3)
        "claude":
            return _build_claude_tiered(model, tier1, tier2, tier3)
        "gemini":
            return _build_gemini_tiered(model, tier1, tier2, tier3, api_key)
        "ollama":
            return _build_ollama_tiered(model, tier1, tier2, tier3)
        _:
            return {}

static func _build_openai_tiered(model, t1, t2, t3) -> Dictionary:
    return {
        "model": model,
        "messages": [
            {"role": "system", "content": t1 + "\n\n" + t2},
            {"role": "user", "content": t3}
        ]
    }

static func _build_claude_tiered(model, t1, t2, t3) -> Dictionary:
    return {
        "model": model,
        "max_tokens": 1024,
        "system": [
            {"type": "text", "text": t1, "cache_control": {"type": "ephemeral"}},
            {"type": "text", "text": t2, "cache_control": {"type": "ephemeral"}}
        ],
        "messages": [
            {"role": "user", "content": t3}
        ]
    }

static func _build_gemini_tiered(model, t1, t2, t3, api_key) -> Dictionary:
    # 引用已创建的 cachedContent
    return {
        "model": "models/" + model,
        "cachedContent": _gemini_cache_id,
        "contents": [
            {"role": "user", "parts": [{"text": t2 + "\n\n" + t3}]}
        ]
    }

static func _build_ollama_tiered(model, t1, t2, t3) -> Dictionary:
    return {
        "model": model,
        "prompt": t1 + "\n\n" + t2 + "\n\n" + t3,
        "stream": false
    }
```

### 6.2 APIManager 新增接口

`APIManager`(`script/ai/APIManager.gd`)当前只有 `generate_dialog`。新增:

```gdscript
func generate_tiered_dialog(
    tier1: String, tier2: String, tier3: String,
    character_name: String
) -> HTTPRequest:
    var settings = SettingsManager.get_ai_settings(character_name)
    var body = APIConfig.build_tiered_request(
        settings.api_type, settings.model,
        tier1, tier2, tier3, settings.api_key
    )
    var http = HTTPRequest.new()
    get_tree().root.add_child(http)
    var headers = APIConfig.get_headers(settings.api_type, settings.api_key)
    var url = APIConfig.get_url(settings.api_type, settings.model)
    http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
    return http
```

---

## 7. AIAgent 拆分路线

`AIAgent.gd` 当前 2004 行,决策循环在 488-558,prompt 拼接散落 4 处(321-328, 516-543, 还有 DialogManager 和 ConversationManager 各一处)。

拆分计划:

| 新文件 | 职责 | 从 AIAgent 拆出的行 |
|--------|------|---------------------|
| `agent/CharacterPromptBuilder.gd` | 三段式 prompt 拼接 | 321-328, 516-543 + 散落各处的拼接 |
| `agent/ToolRegistry.gd` | 工具注册 + 执行 | 559-597(决策执行) |
| `agent/AgentSandbox.gd` | Gen 3 沙箱(预留) | 全新,Gen 2 只建骨架 |
| `AIAgent.gd`(保留) | 状态机 + 调度 | 488-558(简化) |

拆完后 `AIAgent.gd` 缩到 ~500 行,核心循环变成:

```gdscript
func make_decision():
    if current_state == State.LLM_BUSY:
        return
    if dialog_manager.is_character_in_conversation(character):
        await make_conversation_decision()
        return

    await _check_and_initialize_tasks()

    var tiers = CharacterPromptBuilder.build_tiered(character)
    current_state = State.LLM_BUSY
    var http = await api_manager.generate_tiered_dialog(
        tiers.tier1, tiers.tier2, tiers.tier3, character.name
    )
    http.request_completed.connect(
        func(r, c, h, b): _on_decision_request_completed(r, c, h, b, character)
    )
```

---

## 8. Gen 2 → Gen 3 复用路径

Gen 2 和 Gen 3 共享核心执行逻辑。不是两条独立的线。

**共享层:AgentSandbox 类的方法签名**

`ToolRegistry` 的每个 handler 最终调用的就是 `AgentSandbox` 的同名方法。Gen 2 通过 JSON dispatch 到 handler,handler 转发到 sandbox;Gen 3 直接让 LLM 写 GDScript 调用 sandbox。

```
Gen 2 路径:
  LLM → JSON tool_call → ToolRegistry.execute()
  → handler → AgentSandbox.move_to()

Gen 3 路径:
  LLM → GDScript 代码 → ReplyRunner 执行
  → 直接调用 AgentSandbox.move_to()
```

两条路径在 `AgentSandbox.move_to()` 汇合。一套业务逻辑,两个入口。

Gen 2 实施时就建 `AgentSandbox` 骨架——方法签名和参数校验都在,内部实现暂时走旧路径(直接调 `CharacterController.move_to`)。等 Gen 3 上线,sandbox 已经经过 Gen 2 的实战验证,不用从零写安全模型。

具体迁移步骤:

```
Phase 1: Gen 2 落地
  - ToolRegistry 10 个 tool,handler 走旧逻辑
  - AIAgent 改为 tool call 模式
  - 三段式 cache 上线

Phase 2: AgentSandbox 骨架
  - 把 ToolRegistry 的 handler 搬进 AgentSandbox 方法
  - ToolRegistry 的 handler 变成简单的 sandbox 转发
  - 跑一轮回归测试,行为不变

Phase 3: Gen 3 opt-in
  - ReplyRunner + worker thread
  - AgentPromptBuilder(GDScript 类定义版)
  - GodUI 加"高级模式"开关
```

---

## 9. 验证方法

| 阶段 | 手段 | 关键指标 |
|------|------|----------|
| Tool use | GUT 单测 + mock LLM | mock 返回 actions,断言 tool 被正确调用;tool 抛异常时角色不卡死 |
| Context cache | GUT 单测 + 各厂商回归 | TIER 1 三次调用命中两次 cache;Anthropic `cache_read_input_tokens > 0` |
| 行为对比 | 同 prompt 100 场景 A/B | tool 调用成功率 ≥ 95%;成本降 50%+ |
| 玩家体验 | 8 角色跑 1 小时 | 单小时 ≤ ¥1(DeepSeek)或 ≤ ¥2(Anthropic);延迟无感 |

新增测试文件:

| 测试 | 断言 |
|------|------|
| `test/unit/test_tiered_prompt.gd` | TIER 1 不含"position"等动态字段;TIER 2 不含场景信息;TIER 3 只含场景 |
| `test/unit/test_tool_registry.gd` | 注册 3 个 mock tool,execute 返回格式正确;未知 tool 返回 error |
| `test/integration/test_agentic_decision.gd` | mock LLM 返回 reasoning + actions,AIAgent 状态机正确切换 |
| `test/integration/test_cache_hit.gd` | 同一个 TIER 1 连续 3 次请求,第 2、3 次 cache 命中 |

---

## 10. 风险与"不要做"清单

**不要做的事:**

1. 不要把工具扩到 20+。10 个够了,太多让 LLM 选错。等用户反馈再加。
2. 不要做"deterministic 模式"替代 LLM。Agentic 重构是让 LLM 用得其所,不是减少 LLM。
3. 不要追求 100% cache 命中率。95% 就够,再高牺牲灵活性。
4. 不要在 TIER 1 里放动态字段。一个 typo 就让 cache 归零。
5. 不要把 reasoning 输出到对话气泡。那是内心独白,只写记忆。
6. 不要让 LLM 自己决定缓存策略。缓存由代码侧按字段决定。

**风险点:**

| 风险 | 严重度 | 预防 |
|------|--------|------|
| 9 家厂商 tool_call 字段名不同 | 中 | 先 OpenAI 系跑通(7 家),再 Claude,最后 Gemini |
| output 变长后 LLM 更啰嗦 | 低 | prompt 硬性约束 "reasoning 50-200 字,actions ≤ 3" |
| cache prefix 被 prompt 微调打碎 | 高 | TIER 1 模板化生成,禁止手工拼接 |
| 旧存档不兼容 | 低 | `GameSaveManager` 加 `data.get("version", "0.9")` 判定 |
| Gemini cachedContent API 复杂 | 中 | 先跳过 Gemini cache,走全量发送;后续单独适配 |

---

## 11. 工期与优先级

改造放在《改进方案》的 Phase 2,和原有的 C3(拆 AIAgent)、C4(抽 PromptBuilder)合并。

| 任务 | 工作量 | 依赖 |
|------|--------|------|
| C3:拆 AIAgent.gd | 1 天 | — |
| C4:CharacterPromptBuilder(三段式) | 1 天 | C3 |
| C11:ToolRegistry + 10 个 tool | 2 天 | C3 |
| C11:make_decision 改 tool call | 1 天 | C4 + C11 |
| C11:状态机 LLM_BUSY/EXECUTING | 0.5 天 | C11 |
| C12:APIConfig.build_tiered_request | 1 天 | C4 |
| C12:APIManager.generate_tiered_dialog | 0.5 天 | C12 |
| C12:Gemini cache 适配 | 1 天 | C12(可后置) |
| C12:GodUI 成本监控面板 | 1 天 | C12 |
| 测试 | 2 天 | 全部 |

**总计:~10 天**

比初版估算的 5-8 天多了两天。原因:9 家厂商适配不再是伪代码了,Gemini 要单独处理 cache API,测试覆盖也更全。

**开工顺序:先 C11(tool use)不做 C1(存档补全)**。存档补全是 P0 但孤立;tool use 是 P0 且会改变后续所有改造的形态。先定型,后填缝。

---

## 12. 步子哥,几句话

这份 v2 纠了初版五个错。最大的那个:把 Gen 2 当终点。tool call 不是"更聪明的多选题"。它是从"LLM 当工具"到"LLM 当同事"的半程票。Gen 3 是终点,Gen 2 是路上必须经过的收费站。

Context Cache 初版写得太薄。实际一拆:9 家里 7 家是 OpenAI 兼容——cache 改造的工作量不在 API 层,在 prompt 拼接层。`CharacterPromptBuilder` 把三段拼对、顺序固定,7 家自动生效。真正要写代码的只有 Claude 和 Gemini。

工期从 5-8 天调到 10 天。不是 scope 膨胀——是初版低估了"把伪代码变成能跑的代码"需要的时间。Gemini 的 `cachedContents` API 初版写了一行注释就过去了,实际要处理 cache 创建、刷新、过期、错误恢复,至少一天。

AgentSandbox 骨架 Gen 2 就建。ToolRegistry 的 handler 直接调 sandbox 方法,等于 Gen 3 上线前 sandbox 就过了一轮实战。这个复用路径初版完全没提。

最后:先做 tool call,后做存档。没变。
