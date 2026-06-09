# Microverse 项目长期记忆

## 用户信息

- **Godot 初学者**：刚开始学习 Godot 开发，需要基础概念解释
- **解释风格偏好**：要求以**费曼的口吻和思维**来解释问题
  - 费曼风格特点：
    - 直指本质，不绕弯
    - 以具体例子解释抽象概念
    - 回溯问题根源
    - 教学式总结
    - 用简单语言，避免术语堆砌
    - 善用类比（鸭子、黑板、打赌）
  - 质疑"命名不等于理解"（cargo cult detection）

## 项目信息

- **项目名称**：Microverse
- **引擎**：Godot 4.6 (GL Compatibility)
- **主场景**：`scene/maps/Office.tscn`
- **编程语言**：GDScript
- **项目定位**：Godot 4.6 + 多 LLM 提供商 + 长期记忆 + 上帝模式 UI 的多智能体社交沙箱

## 开发规范

- 尽可能使用中文来思考、推理和输出
- 尽可能使用文言文的句式和白话文的表达
- 代码注释使用中文
- 命名风格：类名 PascalCase，函数/变量 snake_case，常量 UPPER_CASE

## 重要文件路径

- 主场景：`scene/maps/Office.tscn`
- AI 核心：`script/ai/AIAgent.gd`（2004 行）
- Camera 控制：`script/CameraController.gd`
- API 管理：`script/ai/APIManager.gd`
- API 配置：`script/ai/APIConfig.gd`
- UI 管理：`script/ui/GodUI.gd`
- 背景故事：`script/ai/background_story/BackgroundStoryManager.gd`

## 已知问题及修复

### Cache 命中率 0% 问题（2026-06-09 修复）
- **病因**：`log_cache_usage()` 只识别 Anthropic 的 `cache_read_input_tokens` 字段
- **修复**：兼容 DeepSeek 的 `prompt_cache_hit_tokens` 字段

### 故事背景未自动加载（2026-06-09 修复）
- **病因**：`BackgroundStoryManager.current_background` 初始为 `null`，无人调用 `initialize()`
- **修复**：在 `GodUI.gd` 的 `_ready()` 中添加 `BackgroundStoryManager.initialize()` 调用

### 画面太小（2026-06-09 修复）
- **修复**：`CameraController.gd` 的 `zoom_level` 从 0.8 改为 1.2
