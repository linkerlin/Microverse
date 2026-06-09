# AGENTS.md — Microverse

> 中文项目；AGENTS.md 兼用中英双语叙述，方便后续代理阅读。
> 一句话定位：**Godot 4.6 + 多 LLM 提供商 + 长期记忆 + 上帝模式 UI** 的多智能体社交沙箱。

---

## 0. 项目元信息

| 字段 | 值 | 证据 |
|------|----|------|
| 项目名 | Microverse | `project.godot:17` |
| 引擎版本 | Godot 4.6 (GL Compatibility) | `project.godot:19`（README 写"4.3+"是滞后） |
| 主场景 | `scene/maps/Office.tscn` | `project.godot:18` |
| 编程语言 | GDScript | `script/**/*.gd` |
| 资源目录 | `res://`（根目录） | 默认 |
| 主菜单与地图选择 | `script/ui/MainMenu.gd`、`script/ui/MapSelection.gd` | 顶场景未走自动加载 |
| README | `README.md`（中文）、`README_EN.md`（English） | 双语 |
| 许可证 | MIT | `LICENSE` |
| GitHub | `https://github.com/KsanaDock/Microverse` | `README.md:99` |
| Steam | 《Microverse In Box 盒中小世界》 | `README.md:184-198` |

> **没有** `.github/`、`Makefile`、`package.json`、CI workflow。所有命令必须手动跑。

---

## 1. 关键命令

> 没有构建系统。下列命令是本项目"事实上的"工作流。

### 1.1 跑游戏

```bash
# 方式 A：编辑器内
#   1) 启动 Godot 4.6+，点击"导入"，选 project.godot
#   2) F5 跑主场景
# 方式 B：命令行
godot --path .                              # 跑主场景（run/main_scene）
godot --path . res://scene/maps/Office.tscn  # 显式跑 Office 场景
godot --path . res://scene/ui/SaveLoadUIManager.tscn  # 调试存档 UI
```

### 1.2 跑测试（GUT，Godot Unit Test 9.6.0）

```bash
# 跑全部 unit 测试（headless）
godot --headless --path . -s addons/gut/gut_cmdln.gd \
    -gdir=res://test/unit -gexit

# 单文件
godot --headless --path . -s addons/gut/gut_cmdln.gd \
    -gtest=res://test/unit/test_tool_registry.gd -gexit

# 编辑器内：在 GUT 面板里点 "Run All"
```

> **注**：GUT 插件已启用（`project.godot:44-46` `enabled=PackedStringArray("res://addons/gut/plugin.cfg")`）。`addons/gut/` 整套是 GUT 9.6.0 的 vendor 代码（**勿改**），跑测试时只动 `test/`。

### 1.3 Lint / 静态检查

- 无 `gdlint`、无 CI。
- 编辑器自带的"GDScript 警告"项目设置可见：`addons/gut/` 里的脚本带 `warnings_manager.gd`，**GUT 的脚本故意把警告压到 0**，别被它误导。
- 提交前肉眼过一遍：tab 缩进、`_ready` 内不重 IO、HTTPRequest 异步而非同步。

### 1.4 重新生成 import

```bash
# 删除 .godot 缓存 + 重新打开项目
rm -rf .godot
godot --path . --import   # 或 --editor --quit
```

`.import` 文件**全部**走 `.gitignore`（见 `IMPORT_FILES_SOLUTION.md`），跨机器哈希值不同会冲突。

### 1.5 提交 / 分支

```bash
git checkout -b feature/<name>
# ... 改动 ...
git add .
git commit -m "feat: ..."   # 提交前缀见 CONTRIBUTING.md
```

> **不要** `git push --force`、`git push` 默认**不**推远端（用户需显式说明）。

---

## 2. 仓库目录地图

```
Microverse/
├── project.godot                 # Godot 4.6 项目配置（autoload/输入/特性）
├── README.md / README_EN.md      # 双语
├── CONTRIBUTING.md               # 贡献规范、提交前缀
├── LICENSE                       # MIT
├── IMPORT_FILES_SOLUTION.md      # .import 文件为何 gitignore
│
├── Microverse架构分析.md          # ★ 仓库作者写的深度架构文档（必读）
├── Microverse改进方案.md          # 痛点与改进
├── Microverse Agentic重构方案.md  # Gen 2 (JSON tool call) 设计
├── Microverse Agentic方案 v2.md
├── Microverse Gen3 GDScript沙箱.md # Gen 3 (LLM 写 GDScript) 设计
│
├── script/                       # 所有 GDScript
│   ├── ai/                       # AI 核心
│   │   ├── AIAgent.gd            # 2004 行，单智能体主控（每 60s 决策一次）
│   │   ├── APIManager.gd         # HTTP 出站
│   │   ├── APIConfig.gd          # 9 厂商请求/响应模板
│   │   ├── ConversationManager.gd # 单次对话
│   │   ├── DialogManager.gd      # 对话门面（autoload）
│   │   ├── DialogService.gd      # 多对并存对话注册表
│   │   ├── agent/                # Gen 2 Agentic 子系统
│   │   │   ├── AgentSandbox.gd   # 沙箱方法集（LLM 调的安全世界）
│   │   │   ├── ToolRegistry.gd   # 9 个 tool 的 JSON dispatch
│   │   │   └── CharacterPromptBuilder.gd # 三段式 prompt
│   │   ├── memory/MemoryManager.gd
│   │   └── background_story/    # 预设三地图背景（Office/School/Jail）
│   ├── ui/                       # 全部 UI（GodUI、设置、对话框、AI 模型标签）
│   ├── CharacterController.gd    # 角色移动 + 路径 + 避障 + 坐下
│   ├── CharacterManager.gd       # 玩家点击选中（autoload）
│   ├── CharacterPersonality.gd   # 8 个角色的人设（硬编码 const）
│   ├── ChatHistory.gd            # 角色私聊记录（user:// 持久化）
│   ├── GameSaveManager.gd        # 存档（autoload）
│   ├── RoomManager.gd + RoomData.gd + RoomArea.gd  # 房间抽象
│   ├── Chair.gd / Desk.gd        # 家具
│   └── CameraController.gd       # 相机拖拽/缩放/跟随
│
├── scene/                        # Godot 场景 (.tscn)
│   ├── maps/Office.tscn          # 248 KB 主场景（占仓库大头）
│   ├── characters/Alice.tscn     # 8 个角色场景，每个 ~700 行
│   ├── ui/                       # UI 场景
│   └── prefab/                   # 家具预制
│
├── asset/                        # 全部美术/字体
│   ├── characters/{body,portraits}/
│   ├── maps/{exteriors,interiors}/
│   ├── objects/                  # 250+ 个 32x32 物品精灵
│   ├── fonts/fusion-pixel-12px-proportional-zh_hans.otf
│   └── ui/                       # GUI、shaders
│
├── test/                         # GUT 测试
│   ├── unit/
│   │   ├── test_tiered_prompt.gd
│   │   └── test_tool_registry.gd
│   └── integration/              # 目录在，文件尚未写
│
├── addons/gut/                   # GUT 9.6.0 完整 vendor 源码（勿动）
│
└── .chong/                       # Crush 项目记忆（与本仓代码无关）
```

---

## 3. Autoload（单例）清单

`project.godot:22-30` 声明 7 个 autoload——项目的"服务总线"：

| 单例 | 路径 | 职责 |
|------|------|------|
| `SettingsManager` | `script/ui/SettingsManager.gd` | 全局配置、角色独立 AI 配置、用户偏好持久化 |
| `DialogManager` | `script/ai/DialogManager.gd` | 对话门面，包住 `DialogService` |
| `CharacterManager` | `script/CharacterManager.gd` | 玩家点击选中、相机跟随、群组广播 |
| `APIManager` | `script/ai/APIManager.gd` | HTTP 出站、9 厂商路由、生成 `HTTPRequest` 节点 |
| `GameSaveManager` | `script/GameSaveManager.gd` | 读档/存档 JSON |
| `SaveLoadUIManager` | `scene/ui/SaveLoadUIManager.tscn` | 存档 UI 面板（场景型 autoload） |
| `MemoryManager` | `script/ai/memory/MemoryManager.gd` | 长程记忆增删改查 + 排序 |

**模式**：5/7 名字以 `Manager` 结尾，所有跨场景状态全塞进单例——Godot 项目典型"全知单例"风格。`APIConfig` 不在 autoload，但 `class_name APIConfig` + 全静态方法，等价"被动单例"。

---

## 4. AI 核心循环（必读，灵魂在 `AIAgent.gd`）

`script/ai/AIAgent.gd` 总长 2004 行，**核心循环**在 `make_decision()` (行 488-558)：

1. **并发互斥**：`waiting_responses[character.name]` 防同一角色并发请求
2. **对话中分叉**：若在对话则走 `make_conversation_decision()`（决定继续/结束）
3. **任务兜底**：`await _check_and_initialize_tasks()` 若任务列表空则先生成
4. **三段式 prompt**（Gen 2，详见 §5）
5. **HTTP 出站**：`await api_manager.generate_tiered_dialog(t1, t2, t3, char_name)`
6. **回调解构**：从响应中提 `#REASONING#` 与 `#ACTIONS#`
7. **串行执行 actions**：`for action in actions: _tool_registry.execute(...)`
8. **失败回退**：`_execute_default_decision()` 走随机任务

`AIAgent` 挂在 `CharacterController.gd:39` 子节点上；每个 `scene/characters/*.tscn` 都有。

**决策周期**：默认 60s 一次（`AIAgent.gd:47`），启动后 10s 第一次（`AIAgent.gd:54`）。

---

## 5. 三段式 Prompt（Context Cache 优化）

`script/ai/agent/CharacterPromptBuilder.gd:9-126`：

| Tier | 内容 | 缓存 |
|------|------|------|
| **TIER 1** 永久 | 人设 + 性格 + 说话风格 + 工作职责 + 公司信息 + 员工名单 + 工具定义 + 输出格式 | 不变 |
| **TIER 2** 缓变 | 状态（钱/心情/健康） + 记忆（按 importance 排序） + 任务（top 3） + 关系（top 3） | 1min 内基本不动 |
| **TIER 3** 即时 | 时间 + 当前房间 + 房间内角色 + 房间内物品 | 每次必变 |

**调用入口**：`APIManager.generate_tiered_dialog(tier1, tier2, tier3, character_name)` (`APIManager.gd:93-126`)，内部按 `APIConfig.request_format` 路由到 OpenAI / Claude / Gemini / Ollama 不同格式（`APIConfig.gd:227-267`）。Anthropic 的 `cache_control: ephemeral` 已写在 `APIConfig.gd:251-252`。

---

## 6. Tool Registry（9 个工具）

`script/ai/agent/ToolRegistry.gd` 注册：

| 工具 | 用途 | 必填参数 |
|------|------|----------|
| `move_to` | 移动（"x,y" 坐标或房间名） | `target` |
| `talk_to` | 与某人对话（需在同一房间） | `name` |
| `think` | 内心独白，写入记忆 | `content` |
| `complete_task` | 标记任务完成 | `task_id`（描述或时间戳） |
| `adjust_tasks` | 调整任务（add/reorder/set_priority/complete） | `actions` |
| `remember` | 写入长期记忆 | `content`, `importance`（1-10） |
| `observe` | 观察某人/某物/自己 | `target`（可选） |
| `change_mood` | 改心情 | `mood`, `reason` |
| `wait` | 等待一回合 | `reason`（可选） |

**所有 handler 转发到 `AgentSandbox`**（`AgentSandbox.gd`）——`ToolRegistry` 只做 dispatch，业务逻辑全部在沙箱里。Gen 3 计划让 LLM 直接写 GDScript 调沙箱，省去 JSON 中间层（见 `Microverse Gen3 GDScript沙箱.md`）。

**安全模型**：`AgentSandbox` 是 `RefCounted`，**不暴露 OS / FileAccess / Engine 任何符号**（注释见 `AgentSandbox.gd:7`）。

---

## 7. 8 个角色（人设硬编码）

`script/CharacterPersonality.gd:6-63` `const PERSONALITY_CONFIG`：

| 名字 | 职位 | 性格（粗略） |
|------|------|--------------|
| Stephen | 公司老板 | 虚伪 PUA 持证上岗 |
| Tom | 老板秘书 | 彩虹屁发射器 |
| Lea | 前台 | 八面玲珑社交天花板 |
| Alice | 前端/UI | 怼人带刺玫瑰 |
| Grace | HR | 细节控 + 数据派 |
| Jack | 后端 | 极客、代码洁癖 |
| Joe | 测试 | 强迫症话痨 |
| Monica | 产品经理 | 雷厉风行完美主义 |

> **限制**：LLM prompt 里写死"只能提及以上列出的员工"（`CharacterPromptBuilder.gd:151`、`ConversationManager.gd:264`）。新增角色必须改 `PERSONALITY_CONFIG`，否则 LLM 会幻觉名字。

**公司设定**（写死，不可让 LLM 编）：SleepySheep 公司 / 产品《CountSheep》小游戏 / 宣传语 "Can't Sleep? Count Sheep" / 玩法是数跳过的小羊。

---

## 8. 房间系统

- **声明**：`Area2D` + `CollisionShape2D`（`script/RoomArea.gd`），挂 `room_name`、`room_desc`
- **管理**：`script/RoomManager.gd`，`rooms` 字典 `area.name → RoomData`
- **数据**：`script/RoomData.gd` 持有 `name`、`position`、`size`、`description`
- **判定**：`is_position_in_room(pos, room)` 用矩形边界（`RoomManager.gd:38-50`）
- **初始化**：`call_deferred("_init_rooms")`（`RoomManager.gd:10`）—— **必须在 _ready 后等一帧再读** `rooms`
- **场景约定**：所有 `RoomArea` 节点挂 `room_area` group
- **当前主场景**：`Office.tscn` 内的 `RoomManager` 在 `/root/Office/RoomManager`（`AIAgent.gd:36` 用了这个硬编码路径）

---

## 9. 9 个 LLM 提供商

`script/ai/APIConfig.gd:50-157` `_providers` 字典：

| Key | URL | request_format | response_parser |
|-----|-----|----------------|-----------------|
| Ollama | `http://localhost:11434/api/generate` | `ollama` | `ollama` |
| OpenAI | `https://api.openai.com/v1/chat/completions` | `openai` | `openai` |
| DeepSeek | `https://api.deepseek.com/v1/chat/completions` | `openai` | `openai` |
| Doubao (豆包) | `https://ark.cn-beijing.volces.com/api/v3/chat/completions` | `openai` | `openai` |
| Gemini | `https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent` | `gemini` | `gemini` |
| Claude | `https://api.anthropic.com/v1/messages` | `claude` | `claude` |
| KIMI | `https://api.moonshot.cn/v1/chat/completions` | `openai` | `openai` |
| SiliconFlow | `https://api.siliconflow.cn/v1/chat/completions` | `openai` | `openai` |
| OpenAICompatible | 占位 URL，需运行时替换 | `openai` | `openai` |

**默认**（`SettingsManager.gd:15`）：`api_type=DeepSeek, model=deepseek-v4-flash`。

**API Key 解析优先级**（`SettingsManager._resolve_api_key`）：
1. 设置文件 `user://settings.cfg` 中的 `api_key`
2. 环境变量 `DEEPSEEK_API_KEY`
3. 留空 → 玩家在 ESC 菜单里手填

> **安全**：`api_keys.json`、`secrets.json`、`config/private/`、`*.key`、`*.pem` 全部 `.gitignore`。**绝不**入库任何真实 key。

---

## 10. 持久化路径

| 路径 | 内容 |
|------|------|
| `user://settings.cfg` | 全局设置（JSON） |
| `user://character_ai_settings.cfg` | 角色独立 AI 设置（JSON） |
| `user://saves/*.json` | 游戏存档 |
| `user://chat_history/` | 角色私聊记录 |
| `user://custom_social_rules.json` | 用户自定义社会规则 |

`user://` 在 Linux 是 `~/.local/share/godot/app_userdata/Microverse/`、Windows 是 `%APPDATA%\Godot\app_userdata\Microverse\`。

---

## 11. 命名与代码风格

按 `CONTRIBUTING.md:60-87` + 现有代码：

| 类别 | 风格 | 例 |
|------|------|-----|
| 类名 | PascalCase | `CharacterManager`、`DialogService` |
| 函数 / 变量 | snake_case | `make_decision`、`current_state` |
| 常量 | UPPER_CASE / PascalCase const | `PERCEPTION_RADIUS`、`DIALOG_DISTANCE` |
| 缩进 | **Tab**（Godot 默认） |  |
| 行宽 | ≤ 100 字符 |  |
| 函数间空一行 | 是 |  |
| 注释 | **中文**（项目主要面向中文用户） |  |
| 信号 | 过去时态 | `conversation_started`、`settings_changed` |
| 私有方法 | 前缀 `_` | `_init_rooms`、`_on_request_completed` |
| RefCounted 工具类 | 继承 `RefCounted` 而非 `Node` | `AgentSandbox`、`ToolRegistry`、`RoomData` |

**autoload 取名约定**：跨场景服务用 `*Manager` 或 `*Service`，单一职责。**禁止**新建依赖 Godot 编辑器拖拽节点的服务类（破坏 autoload 单例风格）。

---

## 12. 重要陷阱与不显惯例

### 12.1 5 个孤立的 `.gd.uid`（无对应 .gd）

`script/` 与 `script/ui/` 里有 5 个 `.gd.uid` 文件**没有**对应的 `.gd`：

| uid 文件 | 状态 |
|----------|------|
| `script/CharacterStatusManager.gd.uid` | 缺失，场景里若引用会报错 |
| `script/DialogUI.gd.uid` | 缺失 |
| `script/ScenePerceptionManager.gd.uid` | 缺失 |
| `script/TaskManager.gd.uid` | 缺失 |
| `script/ui/SettingsUI.gd.uid` | 缺失 |

**怎么办**：
- 提交前 `grep -r "Script" scene/ script/ | grep "uid://"` 检查引用方
- 这些 uid 是 Godot 4.4+ 引入的资源 ID，重命名/移动文件时 Godot 会自动迁移
- 若场景引用了缺失脚本，编辑器打开会弹"missing script"错误——必须用编辑器 UI 重新指派或恢复原文件

### 12.2 HTTPRequest 并发

`APIManager.generate_dialog` 每次创建新 `HTTPRequest` 节点加进 `self`，1 秒后自清理（`APIManager.gd:57-71`）。**禁止**在 `_ready` 内同时发起多个不同 LLM 的并发请求——`waiting_responses` 在 `AIAgent` 里有，但没有全局锁。

### 12.3 角色元数据（`metadata`）字段

写到 `character.set_meta("character_data", ...)` 里的字段：

| 字段 | 类型 | 来源 |
|------|------|------|
| `character_data.tasks` | `Array[Dictionary]`（description, priority, created_at, completed, completed_at） | `_generate_initial_tasks` |
| `character_data.memories` | `Array[Dictionary]`（content, timestamp, type, importance, created_at） | `MemoryManager.add_memory` |
| `money` | `int` | 直接 `set_meta` |
| `mood` | `String` | 直接 `set_meta` |
| `health` | `String` | 直接 `set_meta` |
| `relations` | `Dictionary{name: {type, strength}}` | 直接 `set_meta` |
| `last_task_refresh` | `float`（unix ts） | `AIAgent._refresh_daily_tasks` |

**注意**：`tasks` 字段**既**有 `character_data.tasks` **也**有 `tasks`（裸 set_meta），`CharacterPromptBuilder._get_task_info` 优先读前者（`CharacterPromptBuilder.gd:155-158`），但 `AIAgent` 写时用裸 `tasks`（`AIAgent.gd:419`、`1814`）。**两路并存**，读时优先 `character_data.tasks`，写时分裂。

### 12.4 记忆上限 50

`MemoryManager._cleanup_old_memories` 默认 50（`MemoryManager.gd:130`），按 importance + 时间排序裁剪。**重要事情写 9-10 重要性**，否则会被裁。

### 12.5 任务 priority 1-10 范围

`AgentSandbox.adjust_tasks` 内 `max(1, min(10, pri))`（`AgentSandbox.gd:144`）。**别传 0 或 100**，会被钳到边界。

### 12.6 房间 `position` 含义

`RoomData.position` 是**中心点 + CollisionShape 相对偏移**（`RoomManager.gd:20`），不是 Area2D 的 `global_position`。写工具代码别直接用 `area.global_position`。

### 12.7 AIAgent 依赖硬编码路径

`@onready var room_manager = get_node("/root/Office/RoomManager")`（`AIAgent.gd:36`）—— **只在 Office 场景下工作**。School / Jail 场景若不加 `/root/Office/RoomManager` 节点，AIAgent 一启动就崩。

### 12.8 任务"渴望程度"= 优先级

UI、prompt、AIAgent 全用"渴望程度"作 priority 的同义词，别混。

### 12.9 Conversation ID 格式

`{speaker}_{listener}_{unix_ts}`（`ConversationManager.gd:42`），不是 UUID。同名两角色同一秒会冲突。

### 12.10 `dialog_manager` vs `DialogService`

`DialogManager`（autoload）= 门面；`DialogService`（其子节点）= 多对并存对话注册表（`DialogManager.gd:16-17`）。直接用 `DialogService` 时是裸 Node，**不要** new 一个孤立的 Service——它没被父节点管理会丢信号。

### 12.11 SettingsManager 的角色独立配置

`set_character_ai_settings(name, settings)` 改了之后**不会**自动应用到角色——只是保存到 `user://character_ai_settings.cfg`。`APIManager.generate_dialog(prompt, character_name)` 会在调用时按 `character_name` 查独立设置（`APIManager.gd:74-78`）。

### 12.12 UID 文件的 gitignore

`.gitignore` 显式排除 `*.import`、`export.cfg`、`.godot/`、`*.translation`。**新加的资源路径**若发现 `.import` 入了 git，先 `git rm --cached <file>` 再 commit。

### 12.13 3 个地图背景，只有 Office 实现

`BackgroundStoryManager.gd:32-83` 定义 Office / School / Jail 三套，**但只有 `Office.tscn` 实际存在**。School / Jail 是为 Gen 3 留的占位，加新场景时复用 `set_background("School")` 即可。

---

## 13. 测试

- **框架**：[GUT 9.6.0](https://github.com/bitwes/Gut) Godot Unit Test（`addons/gut/`）
- **已写测试**：
  - `test/unit/test_tiered_prompt.gd` — TIER 1/3 结构断言
  - `test/unit/test_tool_registry.gd` — 9 个 tool 注册、dispatch、错误路径
- **空目录**：`test/integration/` —— 准备写但**还没有文件**
- **运行**：见 §1.2

> **测试哲学**（来自 `MemoryManager` 的"清理旧记忆"代码）：**测不变量**。Prompt 结构、tool 数量、记忆排序规则这些跨 API 改动必坏的属性，是测试该守的底线。**不要**为单次 prompt 输出写断言（LLM 输出不稳定）。

写新测试的范式（`test_tiered_prompt.gd` 风格）：

```gdscript
extends GutTest

func before_each():
    _registry = ToolRegistry.new(null)  # 不依赖 SceneTree

func test_xxx():
    assert_eq(...)
    assert_has(...)
    assert_contains(...)
```

**禁止**在测试里 new `Node` / `SceneTree`——保持纯逻辑测试。GUT 9 的 `GutTest` 在 headless 下可用。

---

## 14. 修改工作流（强制流程）

1. **改前先读**——见 `Microverse架构分析.md` 锁定目标模块的 file:line
2. **依赖方向**：`script/ai/*.gd` 不依赖 `script/ui/*.gd`；改 UI 别动 AI 核心
3. **同一份 prompt 拼接代码被四处复制**（`AIAgent`、`DialogManager`、`ConversationManager`、`GodUI` 都写自己的 `get_company_basic_info()` / `get_character_status_info()` / `get_company_employees_info()`）—— 改一处请同步四处
4. **改 autoload 启动顺序**：新增 autoload 要更新 `project.godot:22-30`
5. **改角色元数据 schema**：先 grep `get_meta("character_data"`、`get_meta("tasks"`、`get_meta("memories"` 看所有读方
6. **跑测试**：见 §1.2
7. **跨场景调试**：在 `Office.tscn` 之外加场景时，**必须**保留 `/root/Office/RoomManager` 节点（见 §12.7），或修改 `AIAgent.gd:36` 的硬编码路径

---

## 15. 关键阅读顺序（新代理上手）

按"读一行懂一行"排序：

1. `project.godot`（24 行 + autoload + input）
2. `script/ai/APIManager.gd`（HTTP 出站 + cache 统计）
3. `script/ai/APIConfig.gd`（9 厂商模板）
4. `script/ai/agent/CharacterPromptBuilder.gd`（三段式 prompt）
5. `script/ai/agent/ToolRegistry.gd` + `script/ai/agent/AgentSandbox.gd`（tool → 沙箱）
6. `script/ai/AIAgent.gd` `make_decision`（行 488-558）
7. `script/ai/ConversationManager.gd`（单次对话）
8. `script/ai/DialogManager.gd` + `script/ai/DialogService.gd`（多对话管理）
9. `script/CharacterPersonality.gd`（8 个角色人设）
10. `script/CharacterController.gd` + `script/CharacterManager.gd`（玩家控制）
11. `script/RoomManager.gd` + `script/RoomArea.gd` + `script/RoomData.gd`（房间抽象）
12. `script/ai/memory/MemoryManager.gd`（记忆）
13. `script/ai/background_story/BackgroundStoryManager.gd`（地图背景）
14. `script/ui/GodUI.gd`（上帝模式 UI，40754 字节）
15. **`Microverse架构分析.md`**（仓库作者写的 33635 字节深度文档）—— 必读
16. `Microverse Agentic重构方案.md` + `Microverse Gen3 GDScript沙箱.md`（设计方向）

---

## 16. 与 LLM 协作的提示（for the agent writing code here）

- 改 prompt 字符串前**先**在 Godot 里跑一遍——LLM 响应是异步的，调试时 `print` 在 `_on_request_completed` 加，别去改工具链
- 写新 tool：`AgentSandbox` 加方法 + `ToolRegistry._reg(...)` 注册 + `ToolRegistry._handler_xxx` 转发
- 写新人设：`CharacterPersonality.PERSONALITY_CONFIG` 加键 + `scene/characters/<Name>.tscn` 新建（按 Alice.tscn 模板复制）
- 写新地图：`scene/maps/<Name>.tscn` 新建 + `BackgroundStoryManager.BACKGROUND_CONFIGS` 加键 + `CharacterPersonality.get_personality` 不动
- 写新 LLM 提供商：`APIConfig._providers` 加键 + `request_format` / `response_parser` 配 match 分支
- 中文注释优先；本项目主要用户与开发者都是中文母语
- API Key 绝不写进 `script/`；只在 `SettingsManager._resolve_api_key` 用 `OS.get_environment("DEEPSEEK_API_KEY")` 走 env

---

## 17. 已知技术债（来自 `Microverse架构分析.md`）

- 4 处 prompt 拼接重复（`AIAgent` / `DialogManager` / `ConversationManager` / `GodUI`）
- `character_data.tasks` 与裸 `tasks` 字段两路并存
- 8 个角色场景（`Alice.tscn` 等）几乎相同结构只换贴图，应脚本化生成
- `AIAgent.gd` 单文件 2004 行，应拆为 `decision_loop` / `task_management` / `memory_integration` 三个 RefCounted
- 5 个孤立 `.gd.uid`（见 §12.1）—— 仓库未清理
- 没有 CI、没有 PR 模板、没有 issue 模板
- `AIAgent.gd:36` 硬编码 `/root/Office/RoomManager` —— 跨地图崩溃
- 中文 README（`README.md`）有 Steam 链接与 Steam 愿望单按钮；改 README 时保留
