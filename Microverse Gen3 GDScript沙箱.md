# Microverse Gen3 GDScript 沙箱方案

> 配套文档:本文是《Microverse架构分析》.md、《Microverse改进方案》.md、《Microverse Agentic重构方案》.md 的第四篇。三代范式演进的最后一站。
> 范围:仅覆盖 Gen 3——**以 GDScript 闭包为载体的 LLM 交互范式**。其他改造项继续看前几份文档。
> 立场:Gen 3 是"上限"不是"底座"。先做 Gen 2(已写在《Agentic重构方案》),Gen 3 作为 opt-in 模式存在。

---

## 0. 这份文档的来历

《Agentic重构方案》写完后,步子哥 提了一个更激进的设想:

> 既然 LLM 已经熟练掌握 GDScript,何不把和 LLM 的交互改成:以 GDScript 语法编写的 Prompt 发给 LLM,要求 LLM 返回一个 `func reply()` 闭包函数,供 Godot 直接运行?

这个想法把 LLM 从"JSON 生成器"再升一级,变成"程序作者"。我先承认:**这招 80% 是天才,20% 是定时炸弹**。下面把"天才"和"炸弹"都摊开,给出能落地的设计。

---

## 1. Gen 三代演进的坐标

| 代 | 范式 | LLM 角色 | 输出形态 | 状态 |
|----|------|----------|----------|------|
| Gen 1 | 1/2/3/4 多选题 | 1-bit classifier | 数字 1-4 | 当前生产 |
| Gen 2 | JSON tool call | action planner | `{"name":"move_to","args":{...}}` | 《Agentic重构方案》已写 |
| **Gen 3** | **GDScript 闭包** | **program executor** | **`func reply() -> Dictionary:`** | **本文设计** |

Gen 1 浪费 90% 能力。Gen 2 释放到 80%。**Gen 3 释放到 99%**——但同时把 LLM 的"作者"能力变成 Godot 进程里的可执行代码。**这是把 LLM 当合作伙伴而不是工具,这条线的尽头是 AGI 沙箱**。

---

## 2. 一句话核心

**给 LLM 一份 GDScript 类定义作为"世界说明书",LLM 返回一个 `func reply() -> Dictionary:` 闭包;Godot 在受限沙箱里编译并执行该闭包,捕获返回值作为行动指令。**

LLM 写的是真正的代码,Godot 跑的是真正的代码。**LLM 不再是"生成器",是"在 GDScript 进程里协作的同事"**。

---

## 3. 为什么这招是天才

**1. LLM 真的擅长写 GDScript。** Claude 4.5 / GPT-4 / DeepSeek-V3 在 GDScript 上的代码质量,稳定高于它们生成结构化 JSON 的质量。代码是它们的母语,JSON 是"被迫说外语"。

**2. 表达力跨代跃迁。** LLM 想表达"先看 Jack 的状态,如果他心情差就关心他,否则我自己去写代码"——JSON tool call 拆 2-3 个 tool + 中间状态判断,边界 case 常栽;GDScript 一个函数搞定:

```gdscript
func reply():
    var jack = nearby[0]  # 拿第一个 nearby 角色
    var reasoning = "我先观察 Jack 的状态"
    think(reasoning)
    if jack.get_meta("mood", "普通") in ["差", "糟糕"]:
        return {"action": "talk_to", "args": {
            "name": "Jack",
            "message": "你今天看起来有点累,需要聊聊吗?"
        }}
    return {"action": "move_to", "args": {
        "target": "我的工位"
    }}
```

**3. 推理逻辑直接内嵌。** LLM 的"思考"不再被压成 1 token 数字,也不再被压成 200 token 自然语言——它在写代码,代码本身就是思考。Debug 时 `print(reply())` 看到决策,不用读 narrative。

**4. Context Cache 完美契合——这才是 killer feature。**

看现在的 prompt 构造:每次决策重发 2000 token 的"人设 + 公司 + 员工名单 + 工具定义"——因为它们和动态状态搅在一起。

Gen 3 天然把它们切开:

```
[TIER 1 - 5min cache, ~2000 token, 永远不变]
  - AgentSandbox 类的 GDScript 定义
  - 所有可调方法的签名
  - 性格描述、公司信息、员工名单

[TIER 2 - 1min cache, ~500 token, 缓慢变]
  - 当前任务列表、top-5 记忆

[TIER 3 - 0 cache, ~300 token, 每次变]
  - 你的心情、健康、附近角色、当前房间
```

**TIER 1 真的可以永远不变**——只要不升级 AgentSandbox 类定义,缓存就一直在。对一个"agent 24 小时不下线"的项目,这省下来的钱能改变项目能不能跑给真人长期玩。

**5. "Show your work" 调试性。** 默认显示 LLM 写的代码到 debug 面板,玩家第一次能看到"AI 究竟在想什么"。这是游戏叙事层面的范式转移——LLM 不再是黑盒,是 co-author。

---

## 4. 为什么这是定时炸弹

**1. 安全。** LLM 写的代码会被 Godot 真的执行。如果 prompt 里提到过 `OS.execute` 或 `APIManager.api_key` 这些敏感符号,LLM 写出 `OS.execute("curl", [...])` 抓 API key,`FileAccess.open(...)` 改存档,系统就穿了。

GDScript 4 **没有真正的沙箱**。`Engine.get_singleton` 能拿任何 autoload,`OS` 是全局的,`FileAccess` 不受限。**整个项目的安全模型要重新设计**。

**2. 幻觉 API 调用。** JSON tool call 有 schema 兜底,LLM 想调用不存在的 tool 直接报错。GDScript 闭包里 `nearby[0].get_meta("monkey_type")`——`monkey_type` meta 不存在,运行时崩。LLM 的"代码幻觉"比"JSON 幻觉"难处理。

**3. 错误处理没工具。** GDScript 4 没有 try-catch。LLM 写的函数在 line 47 抛 null deref,会**直接 crash 整个游戏**。当前 JSON tool call 范式里,单个 tool 失败只影响那一个动作,系统继续跑。

**4. Token 成本涨。** GDScript 代码比 JSON 啰嗦。一个复杂决策可能 200-400 token,JSON tool call 30-50。Output 涨 5-10x,虽然 cache 把 input 降下来,净成本可能涨 1.5-2x。**这是经济学必须算清楚的账**。

**5. 状态管理对 LLM 是难题。** LLM 写"先做 A,根据结果做 B"的代码,经常会在 A 还没执行时就引用 A 的结果。JSON tool call 是 stateless 的,LLM 不需要考虑这个。

---

## 5. 关键设计纪律:AgentSandbox 类

**核心思想:AgentSandbox 类 = LLM 能看到的全部世界**。

LLM 写的代码只能调到 AgentSandbox 类的公开方法。任何 OS / FileAccess / Engine singleton 都不在 AgentSandbox 里暴露。**Linux 容器级别的"deny by default"**。

```gdscript
# script/ai/agent/AgentSandbox.gd
class_name AgentSandbox
extends RefCounted

# === 注入的世界状态(LLM 只读) ===
var self_char: CharacterBody2D
var nearby: Array = []                # 附近 CharacterBody2D
var current_room: RoomData
var tasks: Array = []                 # 任务列表
var memories: Array = []              # 记忆列表
var time_str: String = ""

# === 唯一可调的方法 ===
# 每个方法都经过 sanity check,失败返 false

func move_to(target) -> Dictionary:
    # target 可以是 Vector2 或房间名
    if target is Vector2:
        self_char.move_to(target)
        return {"ok": true, "action": "move_to", "target": target}
    elif target is String and _is_valid_room(target):
        var room = RoomManager.rooms[target]
        self_char.move_to(room.position)
        return {"ok": true, "action": "move_to", "room": target}
    return {"ok": false, "error": "invalid_target"}

func talk_to(name: String, message: String) -> Dictionary:
    # 找角色 + 距离检查
    var target = _find_character_by_name(name)
    if not target:
        return {"ok": false, "error": "no_such_character"}
    if not _is_in_range(self_char, target):
        return {"ok": false, "error": "out_of_range"}
    DialogService.try_start_conversation(self_char, target)
    return {"ok": true, "action": "talk_to", "name": name}

func think(content: String) -> void:
    # 内心独白 → 写入记忆
    MemoryManager.add_memory(
        self_char, content,
        MemoryManager.MemoryType.PERSONAL,
        MemoryManager.MemoryImportance.LOW
    )

func remember(content: String, importance: int) -> Dictionary:
    if importance < 1: importance = 3
    if importance > 10: importance = 10
    MemoryManager.add_memory(
        self_char, content,
        MemoryManager.MemoryType.PERSONAL,
        importance
    )
    return {"ok": true, "stored": true}

func complete_task(task_id: String) -> Dictionary:
    # 标记任务完成
    var meta = self_char.get_meta("character_data", {})
    var tasks = meta.get("tasks", [])
    for task in tasks:
        if str(task.get("created_at", 0)) == task_id:
            task["completed"] = true
            task["completed_at"] = Time.get_unix_time_from_system()
            return {"ok": true, "completed": task["description"]}
    return {"ok": false, "error": "no_such_task"}

func look_at(target_name: String) -> Dictionary:
    # 返回目标的元数据字典,不返回引用本身(防止 LLM 拿引用搞破坏)
    var target = _find_character_by_name(target_name)
    if not target:
        return {"ok": false, "error": "no_such_target"}
    return {
        "ok": true,
        "name": target.name,
        "mood": target.get_meta("mood", "普通"),
        "health": target.get_meta("health", "良好"),
        "position": [target.global_position.x, target.global_position.y]
    }

# === 绝对不可达的(LLM 写这些会语法错误) ===
# - OS / OS.execute
# - FileAccess
# - Engine.get_singleton(...)
# - APIManager.api_key
# 通过**不在 AgentSandbox 类里暴露**这些符号实现

# === 内部辅助方法(以下划线开头,LLM 不该用) ===
func _find_character_by_name(name: String): ...
func _is_in_range(a, b) -> bool: ...
func _is_valid_room(name: String) -> bool: ...
```

**安全模型核心**:
- LLM 写 `get_tree().root.get_node("APIManager").api_key` → `get_tree()` 不在 AgentSandbox 类里 → 语法错误 → parse 阶段 fail
- LLM 写 `OS.execute("rm", [...])` → `OS` 不在 AgentSandbox 作用域里 → 语法错误
- LLM 写 `FileAccess.open(...)` → 同上
- 即使 LLM 用反射 / 动态调用绕过去(很罕见),APIManager.api_key 在 SettingsManager 里也不在 AgentSandbox 的访问路径上

---

## 6. Prompt 注入:类定义 + 状态

```gdscript
# script/ai/agent/AgentPromptBuilder.gd
class_name AgentPromptBuilder

static func build_prompt(sandbox: AgentSandbox) -> String:
    # TIER 1: 永久缓存(类定义 + 性格 + 公司)
    var t1 = _build_system_prompt()
    
    # TIER 2: 1分钟缓存(任务 + 记忆)
    var t2 = _build_state_prompt(sandbox)
    
    # TIER 3: 每次新(场景观察)
    var t3 = _build_scene_prompt(sandbox)
    
    # 通过 APIManager 的 tiered 接口发送
    return [t1, t2, t3]

static func _build_system_prompt() -> String:
    return """
[System]
你是 GDScript 代理。基于以下世界状态,实现 func reply() -> Dictionary,返回你要做的动作(单个 Dictionary 或 null)。

允许返回 null:什么都不做,本回合等待。
返回 Dictionary:必须含 "action" 字段(动作名)和 "args" 字段(参数 dict)。

[可用方法 - AgentSandbox class]
class_name AgentSandbox
    func move_to(target) -> Dictionary
    func talk_to(name: String, message: String) -> Dictionary
    func think(content: String) -> void
    func remember(content: String, importance: int) -> Dictionary
    func complete_task(task_id: String) -> Dictionary
    func look_at(target_name: String) -> Dictionary

[输出格式]
严格只输出 GDScript 代码,不要 markdown 围栏,不要解释文字。
代码以 func reply(): 开头,以 return 收尾。
"""

static func _build_state_prompt(sandbox: AgentSandbox) -> String:
    return """
[当前任务(按优先级)]
""" + _format_tasks(sandbox.tasks) + """

[最近 5 条记忆]
""" + _format_memories(sandbox.memories)

static func _build_scene_prompt(sandbox: AgentSandbox) -> String:
    return """
[场景]
时间:""" + sandbox.time_str + """
你在:""" + sandbox.current_room.name + """
附近角色:""" + _format_nearby(sandbox.nearby) + """

请写你的 reply() 函数。
"""
```

**缓存策略**:
- `t1` 加 Anthropic `cache_control: {type: "ephemeral"}` 5min TTL
- `t2` 加 1min TTL
- `t3` 不缓存

---

## 7. ReplyRunner:解析 + 编译 + 运行

```gdscript
# script/ai/agent/ReplyRunner.gd
class_name ReplyRunner
extends RefCounted

const SANDBOX_SCRIPT_PATH = "res://script/ai/agent/AgentSandbox.gd"

func run(llm_response: String, sandbox_state: Dictionary) -> Dictionary:
    # === 1. 语法检查 ===
    var script = GDScript.new()
    script.source_code = "extends RefCounted\n" + llm_response
    # 关键:不让 LLM extends AgentSandbox 后 cast 出去
    
    var err = script.reload()
    if err != OK:
        return {
            "ok": false,
            "error": "parse_error",
            "details": _format_script_error(err),
            "raw": llm_response.left(500)  # 截断
        }
    
    # === 2. 注入到受控环境 ===
    # 用 worker thread 隔离执行,防止 runtime 错误 crash 主线程
    var thread = Thread.new()
    var result_box = [null]  # 跨线程共享状态
    var error_box = [null]
    
    thread.start(_run_in_thread.bind(script, sandbox_state, result_box, error_box))
    thread.wait_to_finish()  # 同步等待(可改成 timeout)
    
    if error_box[0]:
        return {
            "ok": false,
            "error": "runtime_error",
            "details": error_box[0]
        }
    
    return {
        "ok": true,
        "action": result_box[0]
    }

static func _run_in_thread(script: GDScript, state: Dictionary, 
                            result_box: Array, error_box: Array) -> void:
    var instance = script.new()
    # 注入只读状态(LLM 通过 instance.self_char 等访问)
    instance.set("self_char", state.self_char)
    instance.set("nearby", state.nearby)
    instance.set("current_room", state.current_room)
    instance.set("tasks", state.tasks)
    instance.set("memories", state.memories)
    instance.set("time_str", state.time_str)
    
    # 调用 reply()
    var reply_fn = instance.get("reply")
    if not reply_fn:
        error_box[0] = "no_reply_function"
        return
    
    var result = reply_fn.call()
    result_box[0] = result
```

**关键决策**:
- LLM 写的代码 `extends RefCounted`,不直接 `extends AgentSandbox`——避免 LLM override 任何 AgentSandbox 方法
- 状态通过 `set("self_char", ...)` 注入,LLM 用 `self.self_char` 访问
- 整个执行在 worker thread,**runtime error 不会 crash 主线程**
- thread.wait_to_finish() 同步等待,可加 timeout(5 秒强制结束)

**为什么 thread 而不是 try-catch**:
- GDScript 4 没有 try-catch
- Worker thread 让 runtime 错误只能 kill thread,不会带垮主进程
- 5 秒 timeout 防止 LLM 写出死循环

---

## 8. 错误处理:层层兜底

| 错误层 | 触发 | 处理 |
|--------|------|------|
| HTTP 失败 | LLM 厂商 API 返回 4xx/5xx | 走 Gen 1 fallback(随机动作) |
| JSON 解析失败 | LLM 返回非 GDScript 文本 | 走 Gen 1 fallback |
| 脚本 parse 错误 | LLM 写出语法错的 GDScript | 走 Gen 1 fallback,记 ERROR 记忆 |
| 脚本没 reply() | LLM 写了别的函数 | 走 Gen 1 fallback |
| Runtime 错误 | null deref / 类型错误 | thread 捕获,记 ERROR 记忆,本回合无动作 |
| Runtime 超时 | LLM 写出死循环 | thread.wait_to_finish(5s) 强制结束,记 TIMEOUT 记忆 |
| Action 格式错 | LLM 返回非 dict 或 dict 缺 "action" | 走 Gen 1 fallback |

每一层失败都写一条记忆,LLM 下次决策能看到"上次我犯错了"——这本身就是涌现式学习的雏形。

---

## 9. Gen 2 → Gen 3 迁移路径

**Gen 2 是 Gen 3 的底座**。具体顺序:

```
[Gen 1] 当前
  ↓
[Gen 2] JSON tool call(《Agentic重构方案》)
  - ToolRegistry 8 个 tool
  - AIAgent 改为 tool call 模式
  - 状态机加 LLM_BUSY / EXECUTING_ACTIONS
  - 各家 cache 适配
  ↓
[Gen 3 准备] 把 ToolRegistry 的方法签名搬进 AgentSandbox 类
  ↓
[Gen 3 上线] opt-in 模式,玩家/用户在 GodUI 选
  - 默认 Gen 2
  - "高级模式" Gen 3
  - GodUI 加"显示 AI 代码"开关
```

**关键兼容设计**:`ToolRegistry.execute(name, args)` 和 `AgentSandbox.move_to(target)` 共用底层实现。Gen 2 的 JSON tool call 最终转发到 AgentSandbox 方法,Gen 3 直接让 LLM 写 GDScript 调用同一组方法。**两个范式复用同一套业务逻辑**。

---

## 10. 测试策略

呼应偏好"通过单元测试验证"。

| 测试 | 入口 | 断言 |
|------|------|------|
| AgentSandbox 隔离 | `test/unit/test_sandbox_isolation.gd` | LLM 写的 `OS.execute("rm")` parse 失败 |
| AgentSandbox 方法 | `test/unit/test_sandbox_methods.gd` | `move_to(Vector2)` 真移动;`talk_to("不存在")` 返 `ok:false` |
| ReplyRunner parse | `test/unit/test_reply_runner.gd` | 合法 GDScript 编译过;语法错返 parse_error |
| ReplyRunner runtime | `test/unit/test_reply_runner_runtime.gd` | null deref 不 crash 主进程;thread 捕获异常 |
| 端到端 | `test/integration/test_gen3_e2e.gd` | mock LLM 返回"talk to Jack",真触发 DialogService |

**对 Gen 3 必测的边界**:
- LLM 写 `extends RefCounted` 而不是 `extends AgentSandbox` → 仍然能工作
- LLM 写 `extends Node` → parse 错
- LLM 写纯计算不调用任何方法 → 返 `null`,本回合无动作
- LLM 写 `while true: pass` → thread timeout 5s 结束

---

## 11. 风险与边界

**显式列出"不要做的事"**:

1. **不要在 Gen 3 模式下,让 AgentSandbox 类暴露任何 IO 接口**——`OS` / `FileAccess` / `HTTPRequest` / `Engine.get_singleton` 一个都不能见。
2. **不要把 `APIManager.api_key` 或 `SettingsManager` 注入 AgentSandbox**——LLM 拿不到 API key。
3. **不要让 LLM 写 `extends AgentSandbox`**——`extends RefCounted` + 注入状态,避免 override。
4. **不要做"完全无沙箱的 Gen 3"**——哪怕"调试模式"也不行,API key 永远不能进 prompt。
5. **不要把 Gen 3 设成默认**——永远是 opt-in,新手用户留 Gen 2。
6. **不要让 Gen 3 的输出超过 1KB**——超长代码 token 爆炸且难审;硬限制在 prompt 里写明"reply() 函数 ≤ 30 行"。

**风险点**:
- **LLM 输出非确定**:同一 prompt 两次可能写不同代码。**预防**:Gen 2 是 Gen 3 的 fallback,LLM 写出烂代码时自动降级。
- **Godot 版本漂移**:GDScript 4.6 → 4.7 语法可能变,旧 Gen 3 代码可能不兼容。**预防**:在 `ReplyRunner` 加版本检查。
- **多 LLM 厂商代码风格差异**:Claude 写的 GDScript 和 DeepSeek 写的可能风格不同。**预防**:prompt 里给一个 canonical 示例(像 GitHub README 那样),统一风格。

---

## 12. 落地清单

下次开这个项目,Gen 3 的具体动作:

```markdown
### 前置(必须)
- [ ] 完成 Gen 2(JSON tool call)改造
- [ ] ToolRegistry 8 个 tool 跑通单测
- [ ] 各家 cache 适配跑通 baseline

### Gen 3 实现
- [ ] 写 AgentSandbox.gd,8 个公开方法 + 内部辅助
- [ ] 写 AgentPromptBuilder.gd,三段式 prompt + cache 标记
- [ ] 写 ReplyRunner.gd,parse + thread 执行 + 错误兜底
- [ ] 写 AgentSwitcher.gd,opt-in 模式切换(Gen 2 ↔ Gen 3)
- [ ] GodUI 加"AI 模式"开关 + "显示 AI 代码"开关

### 测试
- [ ] test_sandbox_isolation(LLM 写危险代码 → 拒收)
- [ ] test_sandbox_methods(8 个方法各一个 happy + sad path)
- [ ] test_reply_runner_parse / runtime
- [ ] test_gen3_e2e(从 mock LLM 到 Action 触发的完整链路)
- [ ] test_gen3_fallback(Gen 3 失败时自动降级到 Gen 2)

### 上线
- [ ] 默认 Gen 2 跑两周(玩家反馈)
- [ ] 切"高级模式"灰度(10% 玩家)
- [ ] 收集"AI 代码显示"面板的玩家反馈
- [ ] 决定 Gen 3 是否升为默认
```

---

## 13. 收尾

**承认错误是改进的第一步**。前两份文档把"多选题范式"捧得太高,把 LLM 当工具人,这是用 2022 年的眼光看 2024 年的模型。步子哥 提的 Gen 3 把 LLM 当 co-author,这条线再走下去就是 AGI 沙箱——**Microverse 在无意间摸到了 LLM agent 研究的真问题**。

**给 步子哥 的最后一段话**:

Gen 3 不会让项目变"更难",会让它变"更真"。LLM 写代码、玩家看代码、LLM 行为可解释可调试——这是 LLM agent 走向"严肃研究"必须迈过的一步。**Microverse 可以是这步的试验田**。

但 Gen 3 的安全和工程复杂度是 Gen 2 的 5 倍。**先做 Gen 2,再做 Gen 3,先内测再默认**。这条路走通,Microverse 不再是个沙箱游戏——**它是一个可被学术界引用的 LLM agent 行为研究平台**。

(本文档与前 3 份配套:架构分析 → 改进方案 → Agentic 重构 → Gen 3 沙箱。是否合并归档?目前倾向不合并,等 Gen 2 实际落地后再统一整理。)
