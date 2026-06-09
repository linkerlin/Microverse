# Microverse 改进方案

> 配套文档:本文是《Microverse架构分析》.md 的姊妹篇。前者做"是什么、为什么",本文做"该不该做、怎么做、做到什么程度算完"。
> 范围:基于架构分析中已识别的所有问题点,做优先级排序 + 分阶段研究路径 + 可验证标准。
> 立场:有取有舍。明确指出哪些"看着该做但 ROI 太低",哪些"看着不起眼但实际是 P0"。

---

## 0. 先给一个总评(避免后续失焦)

Microverse 是个**完成度高于平均水平的独立 LLM 沙箱项目**。架构分析里提到的"5 类 4 重要度记忆""9 厂商统一路由""多对并存对话""数据驱动房间发现"——这些**单独拎出来都不算复杂,合起来却拼出一个真正能玩的沙箱**。**强项不在算法,在工程组装**。

但"诚实"地说,它当前**卡在 Demo 阶段的两类典型陷阱**:
1. **P0 级隐性 bug 没修**(存档丢记忆、`.uid` 孤儿、prompt 重复债)
2. **没有"未来扩展"的地基**(单文件 2004 行、prompt 拼接四散、零单测)

下面 11 项改进候选按"必做→应做→值得做→长期"四档排列,每项给出**入口文件、依赖、验证方法、风险**。最后给一个 5 阶段研究路径。

---

## 1. 改进候选总览(11 项)

| # | 改进项 | 档位 | 影响面 | 改动量 | 入口 |
|---|--------|------|--------|--------|------|
| C1 | 存档补齐记忆/关系/情绪/健康 | 必做 | 长程叙事 | 1 文件 + 1 测试 | `script/GameSaveManager.gd:121-170` |
| C2 | 清理 5 个 `.uid` 孤儿 | 必做 | 编译稳定性 | 5 文件级 | `script/**.gd.uid` |
| C3 | 拆分 AIAgent.gd 2004 行 | 应做 | 可维护性 | 重构 1 文件,产出 4-5 个 | `script/ai/AIAgent.gd` |
| C4 | 抽 CharacterPromptBuilder 集中 prompt 拼接 | 应做 | 维护性 + 后续可测 | 1 新文件 + 4 处替换 | `script/ai/AIAgent.gd:70-307` 等 |
| C5 | 记忆上限策略改"重要度+关键类型优先保护" | 应做 | 长程可玩性 | 1 函数 | `script/ai/memory/MemoryManager.gd:130-158` |
| C6 | 状态机增加 `LLM_BUSY` 显式态 | 应做 | 并发 bug 防御 | 多点 | `script/ai/AIAgent.gd:9-13` 等 |
| C7 | 单元测试体系(GUT) | 应做 | 回归保护 | 全仓 | 新增 `test/` |
| C8 | School / Jail 两张地图 .tscn | 值得做 | 内容丰富度 | 2 新场景 + 关联 | `scene/maps/` |
| C9 | README 同步到 Godot 4.6 + Steam 元数据 | 值得做 | 用户体验 | 2 文件 | `README.md`、`README_EN.md` |
| C10 | 用户可上传自定义人设 | 值得做 | 长尾玩法 | 1 新文件 + UI | `script/CharacterPersonality.gd` |
| C11 | LLM tool use / function calling | 长期 | AI 能力上限 | 跨多文件 | `script/ai/APIConfig.gd` 等 |

下面 5 阶段研究路径以这张表为骨干排序。

---

## 2. 5 阶段研究路径

### 阶段 0:工程基线(0.5 天)

**目标:** 消灭所有"开箱编译失败""用户上手卡住"的浅层问题。

**任务:**
- **C2 清理 `.uid` 孤儿**。`find . -name "*.gd.uid" | while read uid; do gd=$(echo "$uid" | sed 's/\.uid$//'); if [ ! -f "$gd" ]; then echo "ORPHAN: $uid"; fi; done`。对每个孤儿:`git log --all --oneline -- "**/X.gd"` 查源头,三选一:补回 .gd、删 .uid、删引用(`.gd.uid` 是 Godot 4.4+ 的"路径稳定性"机制,删 .uid = 强迫 Godot 重新生成)。
- **C9 同步 README**。`project.godot:19` 写的是 `4.6`,README 全篇写"4.3+",改成"Godot 4.6+",顺手把"Steam 即将上线"那段补上商店链接(`README.md:188-196` 已有)。
- **C9 顺手把贡献指南里"待办"过期的合并**。`CONTRIBUTING.md:62-87` 的"代码规范"已经过时(用 Tab、snake_case 没问题,但 GDScript 4.x 已默认类型推导,不该写 `@param` / `@return` 注释——这是旧式 Godot 3 风格)。

**验证:**
- 在干净环境克隆仓库,`git clone` + Godot 4.6 打开,Console 不报"Script not found"。
- `grep -rn "X.gd" script/ scene/` 确认无悬挂引用。
- README 顶部版本号与 `project.godot:19` 一致。

**风险:** 极低。这是清理,不是改动。

**不做的事:** 不要顺手"重构 .uid 系统"或"统一缩进"。那是 Phase 2 的事。

---

### 阶段 1:数据完整性(2-3 天)

**目标:** 修 P0 bug,让"读档"和"会话"等价。

**任务:**
- **C1 扩展存档 schema**。当前 `GameSaveManager.collect_character_data`(`GameSaveManager.gd:121-170`)只覆盖位置、姿态、任务、人设。要把 `character_data.memories / relations / money / mood / health` 也纳入。
  - 但要先决定:这些字段放 `character.set_meta()` 还是新建一个 `CharacterData: Resource` 资源类?Godot 4 的 `Resource` 是序列化友好方案,但要求每个角色都迁移到 Resource 引用。**短期方案**:直接 JSON 化 `character_data` 整个 dict(它已经是 JSON-friendly),存为 `save["characters"][i]["character_data"]`。**长期方案**:在 Phase 3 重构时迁到 Resource。
  - **关键修复**:`apply_character_data` 里的任务恢复(`GameSaveManager.gd:248-253`)有 bug——它尝试写 `ai_agent.current_tasks` 或 `ai_agent.tasks`,但 AIAgent 实际存的是 `character.get_meta("character_data", {}).tasks`,**这段代码现在根本没生效**。验证:`print` 一下读档后的 `character.get_meta("character_data")["tasks"]` 看是不是空。
- **C5 记忆清理策略改写**。`MemoryManager._cleanup_old_memories`(`MemoryManager.gd:130-158`)现是"按重要度+时间排序,砍尾"。改成"重要度阈值 + 关键类型保护":
  ```
  protected_quota:
    - MemoryType.CRITICAL: 不删
    - MemoryType.EMOTION: 至少保留 10 条
    - MemoryType.INTERACTION: 至少保留 15 条
    - 剩余配额由其他类型按重要度填充
  ```
  上限从 50 提到 100(给保护策略留空间)。
- 顺手修 `dialog_bubble` 跟随 bug(`script/ui/DialogBubble.gd:60-67`):气泡应绑定 `target_node.global_position`,但因为它 `add_child` 在 root 而不是说话者,玩家移动说话者时气泡"留在原地"。改为 `add_child` 到当前 Camera2D 的 CanvasLayer(场景里现成的 `CanvasLayer`),跟随自动正确。

**验证:**
- 单元测试(GUT 框架,见 C7)覆盖 `MemoryManager` 全部公开方法,边界条件"100 条触发清理时,EMOTION 必保 10 条"必须 assert。
- 手动验证:启游戏,加 5 条记忆,存档,清状态,读档,看 5 条记忆是否都回来。
- 跑 `script/CharacterController.gd:534` 全行,确认 0 警告。

**风险:**
- `character_data` 序列化可能撞上不可序列化的对象(比如 Dictionary 里塞 Callable)。**预防**:`collect_character_data` 出口加 `_sanitize_for_json(data)` 兜底,把所有 `Callable` / `Object` 引用转字符串。
- 旧存档不兼容。**预防**:`apply_game_data` 入口加 `data.get("version", "0.9")` 判定,旧存档触发"首次读档迁移"弹窗。

**不做的事:** 不要在这一阶段顺手重写 GameSaveManager 的整个数据流(从 JSON 迁 SQLite / 二进制)。那是 Phase 4 的事,过早优化。

---

### 阶段 2:拆分与抽象(3-5 天)

**目标:** 把 2004 行的 `AIAgent.gd` 拆开,把 prompt 拼接集中化。

**任务:**
- **C3 拆 AIAgent**。建议拆成 4 个文件(都 `class_name` 化):
  ```
  script/ai/
    AIAgent.gd              # 主循环,降到 ~400 行
    AIDecisionMaker.gd      # make_decision / _on_decision_completed, ~500 行
    AIConversationFlow.gd   # make_conversation_decision / _generate_farewell, ~400 行
    AITaskPlanner.gd        # _generate_initial_tasks / _adjust_tasks / _complete_task, ~500 行
    AIDefaultActions.gd     # 所有 _xxx_default 兜底函数, ~200 行
  ```
  拆分原则:**一个文件管一个决策阶段**(`make_decision` → 顶层循环;`_adjust_tasks` → 任务层;`_execute_task_movement` → 移动层)。跨文件调用通过 `owner: AIAgent` 反向引用主类。
- **C4 抽 CharacterPromptBuilder**。新建 `script/ai/prompt/CharacterPromptBuilder.gd`,集中:
  ```gdscript
  class_name CharacterPromptBuilder
  static func build_decision_prompt(character, scene, status, tasks) -> String
  static func build_conversation_prompt(speaker, listener, ...) -> String
  static func build_task_generation_prompt(character) -> String
  static func build_movement_prompt(character, current_task) -> String
  ```
  4 个文件里的 prompt 拼接逻辑(`AIAgent.gd:516-543`、`ConversationManager.gd:127-185` 等)全部改为单行调用:
  ```gdscript
  var prompt = CharacterPromptBuilder.build_decision_prompt(
      character, scene_description, status_info, task_info
  )
  ```
  **好处**:
  1. 改一处 prompt,全仓生效
  2. 可以对每个 builder 函数做单测,断言"输出含 `[人设]` 且不含 `position.x` 这种坐标泄漏"
  3. 为 Phase 3 的 token 优化(见 C11)留接口
- 顺手做 **C6 显式 LLM_BUSY 态**。在 `AIAgent.State` 枚举里加:
  ```gdscript
  enum State { IDLE, MOVING, TALKING, LLM_BUSY }
  ```
  把 `waiting_responses[character.name]`(`AIAgent.gd:264`)字典删掉,改用 `current_state == LLM_BUSY`。每个出站 HTTP 前置检查,回调结束必切回原状态。**好处**:`current_state` 是单个可观测属性,debug 时一眼看出谁在等 LLM。

**验证:**
- GUT 单测:`AIDecisionMaker.make_decision` 模拟 API 成功/失败/超时,断言状态机切换正确。
- 跑 Office 场景 30 分钟,8 个角色日志里不该出现"`[AIAgent] X 正在等待上一次 API 响应,跳过本次决策`"这条警告——除非真的排队。

**风险:**
- 重构过程中行为漂移。**预防**:Phase 2 期间不动 prompt 措辞,只动结构,保留所有"回复 1 或 2"的输出约束。
- 主类拆完,`AIAgent` 不再能自己 `make_decision`,得让外部触发。**预防**:保留 `AIAgent.make_decision` 作为 facade,内部转发到 `AIDecisionMaker`。

**不做的事:** 不要在这一阶段改 prompt 内容、换 LLM 厂商、改决策超时(60s)。结构性改动够了。

---

### 阶段 3:测试体系与 LLM 行为基线(2-3 天)

**目标:** 让所有重构后的代码有回归保护;让 LLM 输出可被"断言"。

**任务:**
- **C7 引入 GUT**(Godot Unit Test,社区最成熟框架,`addons/gut/`)。新建 `test/`:
  ```
  test/
    unit/
      test_api_config.gd
      test_memory_manager.gd
      test_room_manager.gd
      test_settings_manager.gd
      test_character_prompt_builder.gd
    integration/
      test_ai_decision_loop.gd     # 模拟 LLM 返回,断言状态机
      test_save_load_roundtrip.gd  # 完整存读循环
    fixtures/
      mock_responses/              # 离线 LLM 响应样例
  ```
- **关键设计决策**:如何 mock LLM?两个选项:
  1. **A:协议层 mock**——在 `APIManager` 加 `set_response_override(prompt_pattern, response_text)`,测试时设置。生产代码不变。
  2. **B:HTTP 层 mock**——给 `APIManager` 加 `mock_url` 字段,测试时指向本地 `http://localhost:PORT/mock`,起个 Python/Go 假服务器。
  **推荐 A**——更轻,不依赖网络。
- 写**断言 prompt 结构的测试**:
  ```gdscript
  func test_decision_prompt_contains_personality():
      var prompt = CharacterPromptBuilder.build_decision_prompt(
          mock_alice_character(), scene, status, tasks
      )
      assert_string_contains(prompt, "Alice")
      assert_string_contains(prompt, "前端工程师")
      assert_string_contains(prompt, "只回复数字 1 或 2")
      assert_string_not_contains(prompt, "position.x")  # 不泄漏内部坐标
  ```
- **建立"行为快照"基线**:对每个真实 LLM 厂商(OpenAI/DeepSeek/Claude/Gemini),跑 100 个标准场景,记录"平均决策延迟 / 平均 token 数 / 异常率",写到 `docs/llm-baseline.md`。后续若改 prompt,跑同样 100 个场景,做 A/B 对比。

**验证:**
- `gut -gconfig=.gutconfig.json` 全绿。
- CI 跑测试(若不想接 CI,本地 pre-commit hook 跑 `gut`)。
- `docs/llm-baseline.md` 第一版就绪。

**风险:**
- 写测试拖慢节奏。**预防**:**不为已经稳定的代码写测试**(像 CameraController 这种纯物理的,单元测试收益低;**优先测有决策逻辑的**:APIConfig、MemoryManager、PromptBuilder、状态机)。

**不做的事:** 不强求 100% 覆盖率。Godot 项目追求 100% 覆盖率是反模式——视觉/物理部分测不出价值。**目标覆盖率:核心逻辑 80%+,视觉/输入 0%**。

---

### 阶段 4:内容扩展(3-5 天,可在 1-2 阶段并行)

**目标:** 让项目支持多张地图 + 自定义人设,从"Office Demo"变成"World Builder"。

**任务:**
- **C8 School / Jail 两张地图**。先用 LimeZu 风格素材(`asset/objects/` 已有 200+ 张 32×32 通用素材)拼两张 .tscn。每张地图至少 3 个 RoomArea(教室/图书馆/操场,牢房/食堂/工作坊)。**关键**:`Office.tscn` 的 RoomArea 命名要参考(`MeetingRoom`、`OpenArea`)。新地图复用同一套 `CharacterController` / `Chair` / `Desk` 节点。
- **C10 用户上传自定义人设**。`CharacterPersonality.gd:6-63` 当前是 `const PERSONALITY_CONFIG` 硬编码。改成:
  ```gdscript
  static var _user_configs: Dictionary = {}  # 运行时追加
  static func register_character(name: String, config: Dictionary)
  static func get_personality(name: String) -> Dictionary  # 优先查 _user_configs
  ```
  UI 上加个"添加角色"弹窗:填名字/职位/性格/说话风格/工作职责/工作习惯,落到 `user://custom_characters.json`。
  **好处**:让用户能"创造自己的 NPC",这是 LLM 沙箱的杀手锏特性。

**验证:**
- 切到 School 地图,8 个原角色瞬间变成"学生",能继续聊天(测试 prompt 是否能迁移)。
- 用户上传一个"江湖郎中"人设,跑 30 分钟,看他是否能稳定扮演。

**风险:**
- 美术资产不够。**预防**:`asset/objects/` 现有 200+ 张够用;若不够,先用 placeholder 灰块,等社区贡献。
- Jail 地图的"暴力/冲突"内容可能触 LLM 厂商 policy。**预防**:在 `BackgroundStoryManager` 加 `violence_level: int` 字段,Jail 默认开警告,所有 LLM 请求前 prepend "内容为虚构,仅供娱乐"。

**不做的事:** 不在这一阶段重写地图编辑器(Godot 自带的 TileMap 工具够用)。**不做自动测试生成地图**(那是另一类项目了)。

---

### 阶段 5:LLM 能力跃迁(5-10 天,长期)

**目标:** 把 LLM 从"按 prompt 选数字"升级到"能调工具"。

**任务:**
- **C11 tool use / function calling**。当前 LLM 只能输出 1/2/3/4,所有"动作"都是代码侧 match 的。tool use 让 LLM 直接输出 `{"name": "move_to", "args": {"x": 100, "y": 200}}`。
  - 优势:角色可发起"非预定"动作(比如"打开抽屉找文件"——这个动作在 4 选项 prompt 里根本没列)。
  - 路径:`APIConfig.parse_response` 增 `function_call` 分支(`APIConfig.gd:255-296`),新加 `ToolRegistry.gd` 注册所有可用工具,`AIAgent` 收到 function_call 后 dispatch 到对应方法。
  - **风险**:tool use 是 OpenAI 2023-06 后的能力,DeepSeek/Claude/Gemini 都已经支持,但 API 形态各异。**预防**:先用 OpenAI/DeepSeek 这两家"协议相近"的厂商跑通,再扩散。
- **多模态**:让 LLM 看场景截图(2D 像素图就行,base64 编码 < 100KB),减少 prompt 长度。**好处**:不再需要 `generate_scene_description` 那 60 行拼接。
- **本地 LLM 支持**:Ollama 配置已就位(`APIConfig.gd:50-59`),但 Ollama 模型普遍偏小,`qwen2.5:1.5b` 这种跑不动"性格化对话"。**下一步**:推荐 `qwen2.5:7b` 或 `llama3.1:8b`,在 README 里给配置指南。

**验证:**
- 设计 5 个"tool use 必触发"的测试场景(比如"角色想查 Slack",必须生成 function_call 而非文本)。
- 多模态:截图 Office 场景,问 LLM"会议室里有几个人",答案应=截图实际人数。

**风险:**
- tool use 改 API 形态,**所有现有 prompt 都要重写**。**预防**:用 feature flag 切,旧路径保留,新路径并存,先内测再默认。
- 厂商差异。**预防**:`APIConfig` 已经有 9 厂商适配经验,新增 `function_call` 字段时复用这套适配。

**不做的事:** 不在这一阶段做"多 agent 协作框架"(AutoGen / CrewAI 风格),Microverse 的"角色独立 AI + 玩家上帝视角"已经是独特卖点,不要套别人的抽象。

---

## 3. 验证方法总览(对应"通过单元测试验证"偏好)

| 阶段 | 主要验证手段 | 关键指标 |
|------|------------|----------|
| 0 | 静态检查(grep / Godot 打开) | 编译 0 错,0 警告 |
| 1 | GUT 单测 + 手动存读档 | 100 条记忆保护策略正确, 存读档 roundtrip 100% |
| 2 | GUT 单测 + 行为对比 | 拆分前后 `make_decision` 输出 log 完全一致 |
| 3 | GUT 全绿 + LLM baseline 跑通 | 核心逻辑覆盖率 ≥ 80%, 9 厂商 baseline 文档就绪 |
| 4 | 手动 + 玩家测试 | School/Jail 各跑 1 小时无崩溃, 自定义人设能稳定扮演 |
| 5 | GUT + A/B 对比 | tool use 触发率 ≥ 80%, 多模态 token 节省 ≥ 30% |

**总验证成本估算:**
- 阶段 0: 1 小时手动
- 阶段 1-3: 3-4 天 GUT 编写 + 1 天 baseline 跑
- 阶段 4-5: 1-2 天手动测试

**项目总 ROI:**
- 必做 + 应做 ≈ 8-10 天工作量
- 收益:从"能跑但有 P0 bug 的 demo" → "可被 100+ 用户稳定玩的 0.1 版"
- 长期(5):从"独立 demo" → "可扩展的世界构建器",天花板打开。

---

## 4. 不要做的事(显式列出,避免被任务带跑偏)

下面这些**听着该做、做了不划算**——明确不纳入研究路径:

1. **不要重写 Godot NodeTree 为 ECS**。项目规模不到 100 节点,ECS 是为上千实体设计的,引入会让代码量翻倍。
2. **不要迁移到 ECS / 状态机库**(如 godot-state-machine)。3 个状态够用,加 `LLM_BUSY` 后 4 个,自己写 enum 完全够。
3. **不要换 Godot 版本到 4.7/5.0**。等社区版本成熟再升,现在升是赌博。
4. **不要把 LLM 调用改成 batch 推理**。批量提示增加复杂度,降低响应实时性,LLM 沙箱的价值是"每个角色独立响应"。
5. **不要做"完全无 LLM 的 deterministic 模式"**。这等于砍掉项目灵魂。如果担心 API 成本,做"轻量决策模式"——只在玩家主动对话时调 LLM,角色间自动对话走预定义模板。
6. **不要做完整的 i18n**。中英双语 OK,但日韩越泰不急。**用 GodUI 已有的多语言字段结构**就够了,不要拉引入 gettext。
7. **不要做云存档**。先单设备 local save 跑稳,云存档引入账号系统,跨 3 个阶段。
8. **不要把 RoomManager 升级为 TileMap 系统**。Area2D 已经够,且 2D 像素 RPG 的 Z 序问题 Area2D 处理得更好。

---

## 5. 给项目维护者(步子哥/你)的 3 段话

**第一段:做减法。** 你 6 个月内做出一个完整能跑的项目,功劳在"什么都做一点但都不求完美"。下一步最大的风险是**想加太多东西**。Phase 0-2 是减法——把已有的修好,不要加新特性。Phase 3 之前,别碰 LLM 厂商新接入、别碰多模态、别碰云存档。**先把地基打实**。

**第二段:写测试,不是为了"找 bug",是为了"放心改"。** 现在你怕改 .gd 文件,因为没回归保护,改完不知道哪里坏。**GUT 一旦上,改 AIAgent 这种核心文件时心里才有底**。这不是工程洁癖,是你接下来 6 个月能持续迭代的护城河。

**第三段:别把所有问题都自己扛。** `.uid` 孤儿、School/Jail 地图、新人设模板——这些都是 GitHub Issue 友好型任务,适合"good first issue" 标签。开源项目的健康度看 issue 响应速度,不看 commit 数量。**Phase 4 开始,试着把 C8/C10 拆成社区任务**,你会发现有人比你更想做。

---

## 6. 落地清单(给下一次会话的 hook)

下次再开这个项目,按这个清单做:

```markdown
- [ ] 阶段 0 - C2: 清理 .uid 孤儿(grep + git log 找源头)
- [ ] 阶段 0 - C9: README 版本同步到 Godot 4.6
- [ ] 阶段 0 - C9: CONTRIBUTING.md 清理过时规范
- [ ] 阶段 1 - C1: GameSaveManager 扩展 schema(含 character_data)
- [ ] 阶段 1 - C1: apply_character_data 修任务恢复 bug
- [ ] 阶段 1 - C5: MemoryManager 改"重要度+关键类型"保护策略
- [ ] 阶段 1 - 顺手: DialogBubble 跟随 bug
- [ ] 阶段 2 - C3: AIAgent.gd 拆 4 文件
- [ ] 阶段 2 - C4: 抽 CharacterPromptBuilder
- [ ] 阶段 2 - C6: 显式 LLM_BUSY 态
- [ ] 阶段 3 - C7: 引入 GUT + 写 5-6 个核心单测
- [ ] 阶段 3 - C7: 9 厂商 LLM baseline 文档
- [ ] 阶段 4 - C8: School.tscn + Jail.tscn
- [ ] 阶段 4 - C10: 自定义人设 UI + 持久化
- [ ] 阶段 5 - C11: tool use / function calling
- [ ] 阶段 5 - 长期: 多模态 / 本地 LLM 优化
```

每完成一项,打勾 + 写一行 commit message;每完成一个阶段,跑 `gut` 确认绿了再进下一阶段。
