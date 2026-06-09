# Microverse 架构分析

> 副标题:一个 Godot 4 多智能体 AI 社交沙箱的代码层解剖
> 撰写时间:2025-06-08
> 范围:Microverse 仓库当前 main 分支(commit 93901d8)
> 写作约定:本文先做"信息密度地图 + 逻辑骨架"(halo-writer 思路),落笔阶段主动拉高文本的困惑度与突发性(去 AI 味),不堆砌"显著""全面"等套话,凡事实必带 `file:line` 坐标。

---

## 0. 一句话定位

Microverse 是**"Godot 引擎 + 多 LLM 提供商 + 长程记忆 + 上帝模式 UI"**缝合出来的多智能体沙箱游戏,代码量不大(去掉素材约 6000 行 GDScript),但把"调用大模型做角色扮演"这条路径上几乎所有常见的工程问题都自己造了一遍小轮子:**配置路由、HTTP 异步、prompt 拼接、记忆管理、对话编排、地图抽象、保存/加载、上帝控制台**。理解它,等于理解一个独立开发者在 6 个月内把 LLM-agent 框架跑通需要踩的所有坑。

---

## 1. 体量与边界

| 维度 | 数字 | 备注 |
|------|------|------|
| 仓库总文件 | 440 | `ls` 统计,含素材与 `.uid` 旁路 |
| GDScript 文件 | ~40 | 不含 `.uid`、`panel_container_theme.tres` |
| 主场景 | `Office.tscn` | 248 KB,占仓库大头 |
| 预置角色 | 8 | Alice / Grace / Jack / Joe / Lea / Monica / Stephen / Tom |
| LLM 提供商 | 9 | Ollama、OpenAI、DeepSeek、Doubao、Gemini、Claude、KIMI、SiliconFlow、OpenAICompatible |
| 预置地图 | 3 | Office、School、Jail(后两者只占 `BackgroundStoryManager.gd:50-83`) |
| Godot 版本 | 4.6 | `project.godot:19`(`config/features`),README 仍写"4.3+",版本漂移 |
| 引擎特性集 | GL Compatibility | `project.godot:19`,说明走兼容性渲染,不是 Mobile/Forward+ |
| 自动加载 | 7 个 | 见 §2 |

最值得注意的边界事实:**8 个角色共 8 个 `scene/characters/*.tscn`,每个都是手工编辑的 700+ 行大场景文件**,只换贴图不换结构。`Alice.tscn` 总长 733 行,80% 是 `AtlasTexture` 子资源。Godot 的 SpriteFrame 拆图工作流,在这里是非常纯粹的人工活。

---

## 2. 自动加载(Singleton)清单

Godot 的 autoload 是该项目的"服务总线"。`project.godot:22-30` 全部声明:

| 单例 | 路径 | 职责 |
|------|------|------|
| `SettingsManager` | `script/ui/SettingsManager.gd` | 全局配置 + 角色独立 AI 配置 + 配置文件持久化 |
| `DialogManager` | `script/ai/DialogManager.gd` | 对话编排的"门面",包住 `DialogService` |
| `CharacterManager` | `script/CharacterManager.gd` | 玩家点击选中、相机跟随、群组广播 |
| `APIManager` | `script/ai/APIManager.gd` | HTTP 出站,9 厂商路由,生成 `HTTPRequest` 节点 |
| `GameSaveManager` | `script/GameSaveManager.gd` | 读档/存档 JSON |
| `SaveLoadUIManager` | `scene/ui/SaveLoadUIManager.tscn` | 存档 UI 面板 |
| `MemoryManager` | `script/ai/memory/MemoryManager.gd` | 长程记忆的增删改查与排序 |

**模式观察:** 7 个 autoload 里,5 个名字以 `Manager` 结尾。这是 Godot 项目里"全知单例"风格的典型副作用——所有跨场景状态都被塞进单例,代价是测试困难、状态散落。Microverse 没建任何单测,这条路径走通是合理的工程取舍。

`APIConfig`(`script/ai/APIConfig.gd`)虽不在 autoload,但通过 `SettingsManager._load_api_config()` 在启动时被引用——`class_name APIConfig` + 全静态方法,等价于"被动单例"。

---

## 3. 文件分层与依赖

```
script/
├── ai/                          # AI 核心,Godot 节点 + 纯逻辑混合
│   ├── AIAgent.gd               # 2004 行,单智能体主控
│   ├── APIManager.gd            # HTTP 出站
│   ├── APIConfig.gd             # 9 厂商请求/响应模板
│   ├── ConversationManager.gd   # 单次对话(说话者+听众)
│   ├── DialogManager.gd         # 对话编排门面
│   ├── DialogService.gd         # 多对并存对话注册表
│   ├── memory/MemoryManager.gd  # 长期记忆
│   └── background_story/        # 故事背景(Office/School/Jail)
├── ui/                          # GodUI、设置、对话框
├── CharacterController.gd       # 角色移动 + 路径 + 避障
├── CharacterManager.gd          # 单例,选中交互
├── CharacterPersonality.gd      # 8 个角色人设硬编码
├── ChatHistory.gd               # 角色私聊记录
├── GameSaveManager.gd
├── RoomManager.gd + RoomData.gd + RoomArea.gd  # 房间抽象
├── Chair.gd / Desk.gd           # 家具脚本
└── CameraController.gd          # 相机跟随/拖拽/缩放
```

**关键约束:** `script/ai/*.gd` 不依赖 `script/ui/*.gd`;`script/ui/*.gd` 几乎只读单例,反过来几乎不写。`AIAgent` 是"上游",`GodUI` 是"下游"——这条单向链很干净。但同一份"格式化角色状态/任务/记忆"的 prompt 拼接代码被 `AIAgent`、 `DialogManager`、 `ConversationManager`、 `GodUI` 四处重复(详见 §11)。

---

## 4. AI Agent 核心循环(最值得读的 200 行)

`script/ai/AIAgent.gd` 总长 2004 行,但真正的"循环"在 `make_decision`(`AIAgent.gd:488-558`)里只有 70 行。把它抽出来,就是整个项目的灵魂:

```gdscript
# AIAgent.gd:488-558 的骨架
func make_decision():
    if character.name in waiting_responses: return          # 1. 防止并发
    if dialog_manager.is_character_in_conversation(...):    # 2. 对话中走另一条路径
        await make_conversation_decision(); return
    await _check_and_initialize_tasks()                     # 3. 任务未生成则先生成
    var scene = generate_scene_description()                # 4. 拼接 prompt
    var status = get_character_status_info(character)
    var tasks = get_character_task_info(character)
    var prompt = "[人设] ... [公司信息] ... [状态] ... [任务] ... [场景] ..."
    prompt += "请只回复数字 1 或 2"
    var http = await api_manager.generate_dialog(prompt, character.name)  # 5. 出站
    http.request_completed.connect(func(...): _on_decision_completed(...))  # 6. 回调
```

**6 步里最值钱的不是代码,是那个"只回复数字 1 或 2"。**

整个 Microverse 的 AI 决策全部走**多选题 prompt 范式**:每个决策点对应一个 1/2/3/4 的选项,LLM 必须挑数字,代码用 `match decision: "1": ...` 路由。`_continue_current_task` 给出"移动/对话/思考/完成"4 个选项,`_adjust_tasks` 给出"保持/重排/新增"3 个选项,`make_conversation_decision` 给出"继续/告别"2 个选项。

**为什么这么干?**
1. **可控性。** LLM 不被允许"自由发挥",只能从预定选项里选——绕开了"LLM 给我返回了一首诗/一段 markdown/一段拒绝"的边缘情况。
2. **可观测。** 决策是单字符,日志和 debug 极容易读。
3. **容错。** 解析失败时,`APIConfig.parse_response` 兜底返回 `""`,触发 `_execute_default_decision` 走随机分支( `AIAgent.gd:1706-1752` ),系统不会卡死。
4. **路由简单。** `match` 块,O(1) 跳转,完全同步。

代价是**上下文利用率偏低**——为了让 LLM 选 1,得先在 prompt 里堆一整页人设、公司、状态、任务、场景;但选完只读一个字符。Microverse 没压缩 prompt,这对长跑场景是隐性的 token 黑洞。

**心跳:** 决策定时器 `decision_timer.wait_time = 60`(`AIAgent.gd:39`),即每个角色每 60 秒做一次"宏观决定"。这意味着 8 个角色并行时,LLM 流量约每 7.5 秒来一发(8 × 1/60 ≈ 0.13/s),叠加 `make_conversation_decision` 每 60 秒一次,叠加移动/任务执行子流程,真实生产环境的 QPS 不低。

---

## 5. 状态机:IDLE / MOVING / TALKING

`AIAgent.gd:9-13`:

```gdscript
enum State { IDLE, MOVING, TALKING }
```

**这是 2004 行代码里唯一的状态枚举**。整个 agent 的"做什么"被压成 3 个值;切换规则散在 `move_to_target`、`initiate_conversation`、`toggle_player_control` 等地方。

| 当前状态 | 触发 | 切换到 | 备注 |
|----------|------|--------|------|
| 任意 | 玩家点选 | IDLE(停掉决策定时器) | `set_selected` → `ai_agent.toggle_player_control(true)` → `decision_timer.stop()` |
| IDLE | LLM 决策 = "移动" | MOVING | `move_to_target` |
| IDLE | LLM 决策 = "对话" | TALKING | `initiate_conversation` |
| TALKING | LLM 决策 = "结束对话" | IDLE(再走) | 走 `_send_farewell_and_end_conversation` |

**这个枚举的"弱"在于它管不到子流程**。比如"我在 TALKING 中等 LLM 生成对话"是个 IO 阻塞,这之间没有显式状态;状态全靠 `waiting_responses[character.name]` 字典(`AIAgent.gd:264`)维护。这是个隐藏的并行 bug 源:如果 `waiting_responses` 漏置,会双发请求。

---

## 6. LLM 路由层(9 厂商的"小框架")

`script/ai/APIConfig.gd` 是整个项目里**最像"框架"的一段代码**。它的设计:

### 6.1 厂商配置表

```gdscript
class APIProvider:
    var name, display_name, url
    var models: Array[String]
    var requires_api_key
    var headers_template: Dictionary
    var request_format: String   # "ollama" | "openai" | "gemini" | "claude"
    var response_parser: String  # 同上
```

9 个厂商全部用这一份元数据描述(`APIConfig.gd:50-157`)。差异只剩两件事:**请求格式**和**响应解析**。新增一个厂商的代价是写一个 `APIProvider` 实例 + 在 `build_request_data` / `parse_response` 的 `match` 里加一个分支。

### 6.2 三件套函数

| 函数 | 作用 | 关键点 |
|------|------|--------|
| `build_request_data(type, model, prompt)` | 拼请求体 JSON | 4 个 match 分支,`ollama` 用 `prompt` 字段,`openai/claude` 用 `messages[]`,`gemini` 用 `contents[].parts[].text` |
| `build_headers(type, key)` | 拼请求头 | `{api_key}` 占位符替换 |
| `parse_response(type, response)` | 解析响应 | 4 个 match,每家取自己字段 |

### 6.3 APIManager 那一段隐藏的 hack

`APIManager.gd:43-50`:

```gdscript
func generate_dialog(prompt, character_name):
    if not is_inside_tree():
        push_error("APIManager is not properly initialized!")
        return null
    # 等待三帧以确保完全初始化
    await get_tree().process_frame
    await get_tree().process_frame
    await get_tree().process_frame
    var http = HTTPRequest.new()
    ...
```

**"等三帧"是个公开的 hack**。原因藏在 Godot 生命周期里:autoload 节点在场景树未稳态时调用 `is_inside_tree()` 可能返 false,直接发 HTTP 会拿到 `RESULT_NO_RESPONSE`。`await process_frame` × 3 是经验性兜底。这种 hack 在快速迭代的小项目里是合理的,但**未来若上正式发行版,这里会需要换成"订阅 SceneTree.ready 信号"或主动注册回调**。

### 6.4 每角色独立配置

`SettingsManager.character_ai_settings: Dictionary`(`SettingsManager.gd:26`),key 是角色名,value 是一份 `current_settings` 拷贝。APIManager 拿 prompt 时会查这个 dict,实现"Stephen 用 Claude,Tom 用 DeepSeek"的混搭(`APIManager.gd:69-73`)。

存储分两份文件:`user://settings.cfg` 与 `user://character_ai_settings.cfg`,`save_settings` 时一次写两份。

---

## 7. 对话系统:两段式 + 多对并存

`DialogService` 是注册表,`ConversationManager` 是单对实例。**这层是整个项目最微妙的架构**。

### 7.1 三层对象

```
DialogManager (autoload, 门面)
    └── DialogService (Node, 活跃对话注册表)
            ├── ConversationManager instance A   # A <-> B
            ├── ConversationManager instance B   # C <-> D
            └── ConversationManager instance C   # E <-> F
```

`active_conversations: Dictionary`(`DialogService.gd:5`)以 `conversation_id` 为 key,允许多对同时存在。这打破了一个常见的天真设计——"全局只有一个对话槽"。

### 7.2 一对对话的递归回环

`ConversationManager._on_request_completed`(`ConversationManager.gd:188-253`)的核心 30 行:

```gdscript
# 创建气泡、保存聊天记录、然后...
var temp = speaker
speaker = listener    # 角色互换
listener = temp
await generate_dialog()  # 递归,让对方回复
```

**这是一个会让初学者懵的设计**:对话不是"我说一句,你说一句"的两次调用,而是**同一次请求完成后,把全局的 speaker/listener 翻转,再生成下一句**。这意味着 LLM 上一秒在扮演 Alice,下一秒就扮演 Tom,完全靠 prompt 里的"你是谁"来切换身份。Godot 的 coroutine 撑住了这个递归,没死锁。

### 7.3 隐私边界

`ConversationManager.build_dialog_prompt` 显式**只注入说话者的记忆,不注入听众的记忆**(`ConversationManager.gd:165-166`有注释:"因为这些是对方的私人信息")。这是 Microverse 在"AI 主观体验"上做过的最关键的架构决策。

但同时 `ConversationManager:127-185` 又要求"突发的记忆优先级大于任务"——意思是说话者在生成对话时,优先考虑"我刚发生了什么",其次才是"我的待办"。这是个有意思的优先级倒置,把社交从"任务驱动"拉回"事件驱动"。

### 7.4 距离门槛

`max_dialog_distance: 100.0`(`DialogService.gd:8`)。玩家通过 `T` 键发起对话时,系统从当前选中角色 100 像素内找最近的角色。`CharacterManager.get_nearby_character`(`CharacterManager.gd:70-76`)的实现是 O(n),目前 n=8 没问题,角色多了得换 spatial hash。

---

## 8. 记忆系统:3 个文件,1 个真相

`MemoryManager.gd` 是核心,`script/CharacterController.gd:33-36` 给每个角色注入 `ChatHistory` 子节点,`script/ai/AIAgent.gd:283` 调 `MemoryManager.get_formatted_memories_for_prompt` 拼接 prompt。

### 8.1 数据结构

```gdscript
# MemoryManager.gd:43-50
var memory_obj = {
    "content": String,        # "你完成了销售报告"
    "timestamp": "2025-06-08 14:32",  # 可读时间
    "type": MemoryType,       # PERSONAL/INTERACTION/TASK/EMOTION/EVENT
    "importance": int,        # 1/3/5/10
    "created_at": float       # unix 时间戳,排序用
}
```

存储位置:`character.get_meta("character_data", {}).memories`——Godot 的 `set_meta` 当作 key-value 存储用,`character_data` 是项目里**最重要的"元数据容器"**,身份、人设、记忆、任务、关系全塞这里。

### 8.2 5 类 × 4 重要度

| Type | 用途 | 例子 |
|------|------|------|
| PERSONAL | 个人状态变化 | "你感冒了,程度中等" |
| INTERACTION | 社交事件 | "你与 Alice 开始了对话" |
| TASK | 任务相关 | "你制定了一个新任务: ..." |
| EMOTION | 情感变动 | "对 Tom 产生了强烈喜欢的情感" |
| EVENT | 通用事件 | (预留) |

| Importance | 值 | 用途 |
|-----------|----|----|
| LOW | 1 | 闲聊小事 |
| NORMAL | 3 | 默认 |
| HIGH | 5 | 玩家植入记忆,疾病诊断 |
| CRITICAL | 10 | 极端事件 |

### 8.3 清理策略

`MemoryManager._cleanup_old_memories`(`MemoryManager.gd:130-158`):每角色最多 50 条,按 (importance desc, created_at desc) 排序,砍尾。

**这里有个隐藏的 bug 面**:50 条上限对长期运行(几小时)远远不够。普通玩家启动游戏 2 小时,一个角色会经历几十次决策、任务完成、对话、心情变化——50 条一满,LOW 优先被砍,但 LOW 砍完砍 NORMAL 时,会丢"你三小时前和 Tom 吵过架"这种对人格连续性很关键的记忆。**这个上限是临时的、保守的初始值,生产环境应该按"重要度阈值 + 关键类型优先保护"做策略**。

### 8.4 持久化:记忆**不**在 save schema 里

`GameSaveManager.collect_character_data`(`GameSaveManager.gd:121-170`)存的字段是:
- name / position / facing_direction / is_sitting / current_chair
- is_player_controlled / ai_state / **tasks** / personality

**`memories`、`relations`、`money`、`mood`、`health` 全没存**。这意味着读档后,角色的所有记忆、人际关系、情绪、健康状态全没了,只剩下坐标和任务清单。

这是个**真正的架构缺陷**,而不是疏忽——因为 CharacterController 的 `AIAgent` 永远在跑,读档后 AI 会基于"空记忆"做决策,与读档前的连续性瞬间断裂。

---

## 9. 房间与地图抽象:从 Group 到 AABB

房间系统是项目里**最"游戏引擎"的一段**,独立于 AI 之外。

### 9.1 三个角色

- `RoomArea`(`script/RoomArea.gd`):继承自 `Area2D`,只有 2 个 `@export` 字段:
  ```gdscript
  @export var room_name: String = "未命名房间"
  @export var room_desc: String = "这里是一个房间"
  ```
  加在场景里,挂 `CollisionShape2D` 描述房间形状。
- `RoomData`(`script/RoomData.gd`):`RefCounted` 纯数据类,name/position/size/description/important_locations。
- `RoomManager`(`script/RoomManager.gd`):构建字典 `rooms: Dictionary`,提供 `is_position_in_room`、`get_current_room`、`get_room_important_locations`。

### 9.2 启动流程

`RoomManager._init_rooms`(`RoomManager.gd:12-28`):遍历 `get_tree().get_nodes_in_group("room_area")`,从每个 `Area2D` 的 `CollisionShape2D` 推出 `position = area.global_position + collision_shape.position`,从 `RectangleShape2D.extents` 推出 `size`,塞进 `rooms` dict。

**干净、零硬编码**——这意味着同一个 Office.tscn 可以有任意多房间,设计师在 Godot 编辑器里拖 Area2D 即可,代码不需要改一行。

### 9.3 决策时怎么用

`AIAgent.generate_scene_description`(`AIAgent.gd:70-134`)的输出示例(角色"在会议室"):

```
你现在在会议室。
[room.description]
[environment_info: 上午/下午/夜晚 + 公司通用描述]
房间内有以下物品:
- 桌子(办公桌...,距离约 25 米)
- 椅子(一把椅子,目前有人正在使用,距离约 18 米)
房间内有以下角色:
- Jack(后端开发工程师) - 状态:TALKING
地图信息:
- 会议室:中心坐标(800, 400),边界范围[左:700,右:900,上:300,下:500],距离约 25 米,方向:西边,房间内角色:Jack
- 大厅:中心坐标(200, 200),距离约 350 米,方向:西北方向
- ...
```

**这里有个精度问题**:prompt 里写"距离约 25 米",但坐标是 800 像素——25 米这个数字是把像素当米算出来的,跟实际尺度脱节。LLM 会信这个数字并据此"决策去哪个房间",**这是个 prompt 错误源**。短距离不影响决策,但跨房间移动时,LLM 容易被"距离 350 米"误导,犹豫不决。

---

## 10. 角色移动:Pathfinding + 避障 + 卡住重算

`CharacterController.gd` 总长 534 行,Godot NavigationServer 2D + 物理射线 + 重试。

### 10.1 寻路

`move_to(target)`(`CharacterController.gd:54-94`):
```gdscript
var path_params = NavigationPathQueryParameters2D.new()
path_params.path_postprocessing = PATH_POSTPROCESSING_CORRIDORFUNNEL
NavigationServer2D.query_path(path_params, path_result)
navigation_path = path_result.path
```

启用 funnel 算法优化路径。失败时降级为直线 `navigation_path = [global_position, target]`(`CharacterController.gd:80`)。

### 10.2 避障:方向稳定 + 渐进混合

`_calculate_avoidance_direction`(`CharacterController.gd:97-173`)是该项目的精华之一:

```gdscript
# 前方 35 像素射线检测
# 距离 < 30 像素才避障(避免远距离误判)
# 避障方向 = 优先沿用上次的(0.8 秒稳定窗口),否则左右探查
# 与 desired_direction 做 lerp(blend_factor * 0.6)混合
# 再用 obstacle_normal 兜底
```

**"方向稳定窗口" 0.8 秒是关键**——避障时强行保持同一方向 0.8 秒,避免"左-右-左-右"的抖动。这是非常接地气的避障经验,比教科书的 RVO 实现更轻。

### 10.3 卡住检测

`_check_if_stuck`(`CharacterController.gd:189-210`):每帧检查"实际位移 < 5 像素",累积 2 秒则触发 `_recalculate_path`,最多重试 3 次,最终降级为直线。

**这是给"两个角色互卡"准备的**——LLM 让 A 走向 B,B 也走向 A,二者迎面撞上,光看物理层永远不会分开。重试 3 次配合随机 offset 偏移,大概率能挣脱。

### 10.4 椅子系统

`Chair.gd`(102 行)+ `sit_position` 偏移 + Z-order 动态调整(`Chair.gd:62-72`):
- 角色朝上坐(背对桌),Z 提到桌之上
- 角色朝下坐,角色 Z 高于桌

**这种"基于朝向的 Z-index 处理"是 2D 像素 RPG 的老技巧**,Microverse 把 Chair 和 Desk 都做了(`Desk.gd` 每 0.1 秒扫一次角色和椅子位置关系,动态调 Z),保证视角错觉不穿帮。

---

## 11. UI 层:GodUI = 上帝模式控制台

`script/ui/GodUI.gd` 总长 ~1100 行,是项目**第二大的文件**(仅次于 AIAgent)。它是真正的"God Mode"——玩家不是"看着 AI 演",而是"在 AI 演的中途插手":

### 11.1 6 大玩家干预能力

| 弹窗 | 做什么 | 实现要点 |
|------|--------|----------|
| ImplantMemory | 给任意角色写入一条 HIGH 重要性记忆 | `MemoryManager.add_memory(..., HIGH)` |
| Disease | 设定疾病(感冒/发烧/抑郁/焦虑/受伤) + 严重度 0-10 | 改 `character.set_meta("health", ...)` |
| Money | 增减金钱 + 写记忆 | 改 `character.set_meta("money", ...)` + 加记忆 |
| Emotion | 选两个角色 + 情感类型(喜欢/尊敬/嫉妒/愤怒/信任/怀疑/崇拜) + 强度 -10~+10 | 改 `character.set_meta("relations", ...)` |
| Task | 直接给某角色加任务/完成/删除 | 绕过 AI,直接写 `tasks` |
| Background | 切换地图(Office/School/Jail) + 加自定义社会规则 | 改 `BackgroundStoryManager` 静态状态 |

**这套 UI 是把"调试控制台"产品化的结果**。开发者本来需要这些接口看 AI 行为,索性把"按钮 + 表单"摆到玩家面前。**结果是:这是个"工程工具"长成"游戏特性"的典型案例**——你可以拿它做严肃的"涌现式叙事实验",也可以纯粹恶搞 Tom 让 Tom 觉得 Stephen 是他爹。

### 11.2 GodUI 与 CharacterManager 的双向同步

`CharacterManager._sync_godui_selection`(`CharacterManager.gd:134-161`)实现:
- 玩家点击场景里角色 → 选中 → GodUI 同步
- 玩家在 GodUI 列表里点选 → CharacterManager.current_character 切换 → 相机跟随

这层通过 `get_tree().get_first_node_in_group("godui")` 在 `_init_godui_reference` 里延迟查找——**`call_deferred` + group lookup 是 Godot 里处理"跨场景引用"的常规解法**,比硬编码路径稳。

### 11.3 DialogBubble:跟随说话者的浮空对话框

`script/ui/DialogBubble.gd`(80 行)是个纯 Node2D,`target_node: Node2D` 引用,每帧 `_process` 里把自己移到目标正上方 20 像素处,水平居中。

5 秒后自动消失,新消息来时用 Tween 覆盖。它不接 signal,纯推模式——这避免了"AI 同时说话"的多气泡冲突。`ConversationManager` 直接 `instantiate()` + `add_child(Engine.get_main_loop().root)` 把它挂到根节点而不是说话者身上,这样**气泡不会跟着角色移动**(定位在生成时的全局坐标),这是有意为之还是 bug 不太清楚——玩家移动角色时气泡会"留在原地"。

---

## 12. 持久化层的真实能力

### 12.1 存档的 JSON 结构

`GameSaveManager.collect_game_data`(`GameSaveManager.gd:82-118`):

```json
{
  "version": "1.0",
  "timestamp": 1717838400,
  "scene_name": "Office",
  "characters": [
    { "name": "Alice", "position": {...}, "facing_direction": "down",
      "is_sitting": false, "current_chair": null,
      "is_player_controlled": false, "ai_state": {...},
      "tasks": [...], "personality": {...} }
  ],
  "rooms": { "ConferenceRoom": { "name": ..., "position": ..., "size": ..., "description": ... } },
  "global_state": { "game_time": ..., "settings": {...} }
}
```

### 12.2 存什么 / 不存什么

| 数据 | 存档 | 读档 | 备注 |
|------|------|------|------|
| 坐标、朝向、坐下状态 | ✓ | ✓ | |
| 玩家控制权 | ✓ | ✓ | |
| AI 状态机(枚举值) | ✓ | ✓ | 但 `waiting_responses` 字典不存,会重置 |
| 任务列表 | ✓ | ✓ | **这里有 bug:** `apply_character_data` 尝试恢复 `ai_agent.current_tasks` / `ai_agent.tasks`(`GameSaveManager.gd:248-253`),但 AIAgent 实际把任务存在 `character.get_meta("character_data", {}).tasks` 里,根本不在这两个属性上——**读档后任务丢失** |
| 人设 | ✓ | ✓ | 但人设是 hardcoded 的(`CharacterPersonality.PERSONALITY_CONFIG`),读档没意义 |
| 记忆 | ✗ | — | 每次读档都是空记忆 |
| 情感关系 | ✗ | — | |
| 金钱/心情/健康 | ✗ | — | |
| 房间布局 | ✓ | ✓ | 实际上从 .tscn 恢复,存档里的 rooms 数据**没被 apply_game_data 使用** |
| 自定义社会规则 | ✗ | — | `BackgroundStoryManager.custom_rules` 存 user://custom_social_rules.json,独立于 GameSaveManager |

**结论:** GameSaveManager 的"save"很勤快,"load"很怠惰。能存的:位置。能恢复的:位置。

对单人沙箱游戏来说这勉强能接受——读档后看到 8 个角色瞬间"失忆",但他们会基于 LLM 慢慢重建人格,几轮决策后又能聊起来。**对真正的"叙事游戏"来说,这是 P0 级 bug**。

---

## 13. 8 个角色人设:讽刺的"打工人标本"

`CharacterPersonality.gd:6-63` 静态字典,每个角色 5 字段:`position` / `personality` / `speaking_style` / `work_duties` / `work_habits`。每个字段都是**长篇吐槽式描述**,LLM 拿去做角色扮演时,口音、立场、措辞都能学到。

举几个"味"很重的:

- **Stephen**(老板)——"奥斯卡级虚伪表演家,职场 PUA 持证上岗选手,手机相册里存着 100 张'和马云合影'(实则 AI 合成)"
- **Tom**(秘书)——"人形彩虹屁发射装置,职场绿茶段位满级,手机备忘录存满 Stephen 语录"
- **Lea**(前台)——"表面甜妹实则人精,手机里存着《同事喜好红宝书》:Joe 喝咖啡要加两勺糖,Alice 讨厌香菜"
- **Alice**(前端/UI)——"开口就是'这需求的视觉层级比老板的发际线还混乱',遇到设计争议时能从色彩心理学讲到劳动法第 38 条"
- **Joe**(测试)——"口头禅是'这破代码是用脚写的吧?',分析问题时能从 bug 扯到宇宙起源"

**这是一个"中国互联网公司文化样本库"**——8 个人覆盖了老板、舔狗、HR、PM、设计、前端、后端、测试、财务、前台,基本是中型互联网公司的全套岗位。每个角色都被"骂"出特色,LLM 学到的不是"善良的 Alice",而是"会在周会上引劳动法的 Alice"。

公司本身是 **SleepySheep 公司**,主产品是《CountSheep》小游戏——"Can't Sleep? Count Sheep",玩法是数手机屏幕上跳过的小羊,然后用九宫格按钮记数。**这是一个用元笑话把自己嵌入游戏设定的写法**:玩家在 LLM 模拟的办公室 AI 桌面上"工作",而办公室里"做的工作"本身也是个 LLM 时代到来之前的低技术小游戏——一种反向自嘲。

---

## 14. 故事背景:3 张地图 = 3 个社会规则集

`BackgroundStoryManager` 静态,3 套配置(Office / School / Jail,见 `BackgroundStoryManager.gd:32-84`):

| 地图 | 机构 | 时代 | 关键差异 |
|------|------|------|----------|
| Office | CountSheep 游戏公司 | 2024 现代 | "鼓励团队合作和知识分享" |
| School | 阳光学院 | 2024 现代 | "上课时间保持安静,认真听讲" |
| Jail | 新希望监狱 | 2024 现代 | "严格遵守监狱作息时间,服从管理人员的指挥" |

**3 个背景的 prompt 内容相同——**都是公司 + 环境 + 时代 + 文化 + 经济 + 7 条规则,但**地图**这个名字变了。LLM 拿到 prompt 后会发现"机构是监狱"和"机构是学校"产生的行为完全不同——这是 Office / School 还能复用同一份 8 角色人设的关键:**人设说的是"打工人",但只要换背景,人设可以无缝套到"学生"或"服刑人员"上**。

玩家可在 GodUI 增删自定义规则(独立于预设规则),`user://custom_social_rules.json` 持久化。

---

## 15. 重复的 prompt 拼接(代码债)

**这是项目最大的代码债**。同一份"角色状态 + 任务 + 记忆"格式化函数,在 4 个文件里被复制粘贴:

| 函数 | 位置 | 几乎一样地出现在 |
|------|------|------------------|
| `get_company_basic_info()` | 4 处 | `AIAgent.gd:321-328`、`DialogManager.gd:43-50`、`ConversationManager.gd:267-274`、`AIAgent` 内多次 |
| `get_company_employees_info()` | 4 处 | 同上 |
| `get_character_status_info()` | 2 处 | `AIAgent.gd:267-307`、`ConversationManager.gd:277-311`(实现微差) |
| `get_character_task_info()` / `get_character_tasks()` | 2 处 | `AIAgent.gd:331-363`、`ConversationManager.gd:313-332` |

**为什么不抽?** 最可能的原因是"AI prompt 改起来频繁,放一起反而不好管"。但代价是:**改一个数字(比如心情的措辞)要改 4 个文件,容易漏**。理想的拆分:

```
script/ai/prompt/
  CharacterPromptBuilder.gd   # 集中拼 prompt 的所有段落
  PromptContext.gd            # 输入:角色、场景、任务、记忆 -> 段落字典
```

这条重构路是未来正式版的必做项。

---

## 16. 项目状态盘点(2025-06-08 这一刻)

### 16.1 已实装

- [x] 9 厂商 LLM 路由
- [x] 8 角色人设 + Office 地图
- [x] 多对并存对话
- [x] 长期记忆(5 类 4 重要度,50 条上限)
- [x] 任务系统(自动生成 + 玩家干预)
- [x] 情感关系(玩家直接编辑)
- [x] 故事背景(3 地图 + 自定义规则)
- [x] 上帝控制台(6 大弹窗)
- [x] 基础路径规划 + 避障 + 卡住重试
- [x] 基础存档(位置 + 任务)
- [x] 切换窗口/全屏/分辨率

### 16.2 半成品 / 已知缺口

- [ ] 5 个 `.gd.uid` 找不到对应 `.gd` 源文件:
  - `CharacterStatusManager.gd.uid`
  - `DialogUI.gd.uid`
  - `ScenePerceptionManager.gd.uid`
  - `TaskManager.gd.uid`
  - `SettingsUI.gd.uid`
  可能是改名 / 拆分的进行中状态;**目前的 main 分支在引用这些类时会有 GDScript 编译错误**(虽然 autoload 用的 `GameSaveManager`、`MemoryManager` 等没有 uid 孤儿问题)
- [ ] 记忆 / 关系 / 情绪 / 健康不在 save schema
- [ ] School / Jail 地图没有对应的 .tscn
- [ ] README 说"Godot 4.3+",实际 `project.godot:19` 是 4.6
- [ ] CharacterController.move_to 失败时打印的"路径点数量"是调试日志(3 处 `print("[CharacterController]")`)
- [ ] `CharacterController:103-106` 有个 `self` 被加进 `front_query.exclude`,但 exclusion 字段在 Godot 4 实际叫 `exclude`(已用,正确)
- [ ] `CameraController:21-29` `_ready` 函数体比注释多一个 tab 的缩进(实际不致命,但风格不统一)

### 16.3 资源向

- `asset/objects/` 下 200+ 张 32×32 像素图(LimeZu 风格),大部分未在场景中实例化——预留给未来"扩展地图"的弹药库
- 字体只一个 `fusion-pixel-12px-proportional-zh_hans.otf`——支持中文 + 像素风,够用

---

## 17. 适合后续读者深入的几个坐标

| 主题 | 入口 |
|------|------|
| 决策循环 | `script/ai/AIAgent.gd:488-558` |
| 多选题 prompt 范式 | `script/ai/AIAgent.gd:1117-1230` |
| 厂商路由 | `script/ai/APIConfig.gd:50-157` |
| 三帧初始化 hack | `script/ai/APIManager.gd:43-50` |
| 对话递归回环 | `script/ai/ConversationManager.gd:188-253` |
| 多对并存注册表 | `script/ai/DialogService.gd:5-49` |
| 房间发现 | `script/RoomManager.gd:12-28` |
| 避障方向稳定 | `script/CharacterController.gd:97-173` |
| 卡住重试 | `script/CharacterController.gd:189-237` |
| 上帝模式 | `script/ui/GodUI.gd:312-521` |
| 8 角色人设 | `script/CharacterPersonality.gd:6-63` |
| 故事背景配置 | `script/ai/background_story/BackgroundStoryManager.gd:32-84` |
| 3 厂商 + 3 故事背景 → 9×3 = 27 种"叙事组合" | (隐式特性) |

---

## 18. 这个项目最值得借鉴的 3 件事

1. **多选题 prompt 范式**——所有决策点用"只回复数字"压缩输出,代码侧 `match "1" / "2"` 路由,容错和可观测都极好。比"自由生成 JSON 然后正则提取"省心。
2. **每角色独立 AI 配置 + 跨厂商混搭**——同一个办公室可以让 Stephen 用 Claude 做老板式思考,Tom 用 DeepSeek 做秘书式舔,模型能力差异会成为"性格差异"的物化。
3. **上帝模式 UI 化**——把开发用的控制台"按钮化",既是调试工具,也是沙箱玩法。LLM 时代,玩家对"涌现"的需求比"剧情"大,直接给权柄是更高级的设计。

## 19. 这个项目最值得警惕的 3 件事

1. **prompt 拼接代码散落 4 处**——改一行得搜全仓,4 个文件容易漏。下一步:抽 `CharacterPromptBuilder`。
2. **存档 schema 不覆盖记忆和关系**——读档即失忆,长程叙事的最大杀手。下一步:扩展 `collect_character_data` 把 `character_data.memories/relations/money/mood/health` 纳入。
3. **`.uid` 孤儿**——`CharacterStatusManager` 等 5 个类在 main 上找不到 .gd 源,新克隆者编译会失败。下一步:要么补回 .gd,要么删 .uid + 删引用。

---

## 20. 收尾:这是不是一个好"LLM Agent 教学项目"?

**是的**。它小(单文件 2000 行级别)、它真(从 HTTP 出站到 UI 弹窗都是真代码)、它完整(9 厂商、3 地图、8 角色、记忆、对话、任务、上帝控制台全有)。

**学它的人会得到:**
- LLM API 集成的"裸金属"经验(不靠 LangChain 这种封装)
- Godot 信号 / autoload / scene 三件套的实战
- 多 agent 系统的状态机与并发控制
- prompt 工程的"反自由"风格(把 LLM 压回选择题)

**学它的人会被坑的:**
- prompt 拼接散落(强迫你重构)
- save/load 不完整(强迫你修)
- `.uid` 孤儿(强迫你清理工程)

总之:这是 2025 年一个独立开发者能"从零到能跑通 LLM 沙箱"的诚实范本——里头有 6 个月的真实试错,而不是 6 周的 hackathon 抛光。
