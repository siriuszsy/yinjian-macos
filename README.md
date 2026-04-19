<p align="center">
  <img src="./docs/assets/yinjian-logo.svg" width="160" alt="音键 APP logo" />
</p>

<h1 align="center">音键 APP</h1>

<p align="center">一个面向 macOS 的语音输入工具。</p>

目标很简单：

`按住说话 -> 松开 -> 语音转文字 -> 文本整理 -> 自动写回当前光标`

当前仓库采用 `源码公开、文档公开、不提供二进制安装包` 的发布方式。  
也就是说，GitHub 上会提供：

- 源码
- 设计文档
- 架构说明
- 编译与权限说明

不会提供：

- 可直接安装的 `.app` 二进制
- 本地签名证书或私钥
- API Key

## 当前功能

- 全局触发录音与翻译
  当前开发版默认使用 `⌘ + ;` 做听写，`⌃⌘;` 做翻译
- 底部悬浮输入状态
  录音时显示波形，处理中显示 `思考中`
- 语音转文本
  使用阿里云百炼 `qwen3-asr-flash`
- 文本整理
  使用阿里云百炼 `qwen3.5-flash`
- 翻译模式
  录音后直接输出目标语言，不再经过 cleanup
- 自动写回当前输入框
  优先使用 Accessibility，失败时走粘贴回退
- 菜单栏写入测试
  菜单里提供 `写入测试文本`，可直接验证当前输入框能否被写入 `【音键写入测试】`

## UI 设计

这版 UI 的目标不是传统桌面窗口，而是尽量接近现代语音输入工具的主路径体验：

- 待机时完全隐藏
- 按住触发键时出现底部黑色胶囊
- 松开后进入 `思考中`
- 成功后直接隐藏，不打断输入流
- 只有失败时才给短提示

相关设计文档：

- [V1 系统设计](./docs/v1-system-design.md)
- [Runtime Indicator 状态机](./docs/runtime-indicator-state-machine.md)
- [技术架构](./docs/technical-architecture.md)

## 界面预览

当前仓库已经附带一组真实界面素材：

设置页：

![设置页](./docs/assets/settings-window.png)

录音态：

![录音态](./docs/assets/recording-state.png)

演示动图：

![演示动图](./docs/assets/demo-short.gif)

当前仓库里已有原型：

- [floating-orb 原型](./prototypes/floating-orb/index.html)
- [ui-states 原型](./prototypes/ui-states/index.html)
- [界面素材目录说明](./docs/assets/README.md)

## 技术栈

- `Swift + AppKit + SwiftUI`
- `AVAudioRecorder`
- `AXUIElement`
- `qwen3-asr-flash`
- `qwen3.5-flash`
- `Keychain / 本地文件存储`

当前主链路：

```text
⌘ + ; -> 录音 -> qwen3-asr-flash -> qwen3.5-flash -> 写回当前光标
```

翻译链路：

```text
⌃⌘; -> 录音 -> qwen3-asr-flash -> 翻译 -> 写回当前光标
```

## 如何从源码编译

详细步骤见：

- [源码发布说明](./docs/source-release-guide.md)
- [Vibe Coding 开发说明](./docs/vibe-coding-guide.md)

最小前提：

- macOS
- Xcode
- 阿里云百炼 API Key

另外，项目里保留的本地签名脚本，只是为了处理苹果本地编译、调试签名和权限稳定性的问题。  
这部分属于开发辅助，不是产品功能本身。  
如果你使用 `vibe coding` 方式接手项目，可以按文档一步一步完成，不需要把这层逻辑硬编码回项目里。

当前仓库默认保留两条本地调试签名路径：

- 优先使用 `login.keychain-db` 里的 `Apple Development`
- 如果本机还没有苹果正式开发证书，再回退到仓库里的本地开发签名脚本

常用本地安装脚本：

```bash
zsh scripts/install_debug_app.sh
```

最小构建命令：

```bash
xcodebuild -project voiceKey.xcodeproj \
  -scheme voiceKey \
  -configuration Debug \
  -derivedDataPath .derived \
  build
```

## 权限

当前项目涉及的主要权限：

- 麦克风
  录音必需
- 辅助功能
  写回当前输入框必需
- 键盘监听
  只有未来切回 `Fn` / 右侧 `⌥` 这类单键触发时才需要

当前开发版默认触发键是 `⌘ + ;` 和 `⌃⌘;`，都不依赖键盘监听权限。  
如果你怀疑是辅助功能没有真正生效，先从菜单栏点一次 `写入测试文本`，不要直接走整条语音链路。

## 架构

源码结构：

```text
voiceKey/
├── App/
├── Application/
├── Domain/
├── Infrastructure/
├── Presentation/
├── Resources/
└── voiceKeyTests/
```

职责划分：

- `App`：启动、装配、单实例
- `Application`：主流程编排与状态机
- `Domain`：模型和协议
- `Infrastructure`：录音、ASR、cleanup、插入、存储
- `Presentation`：悬浮 UI、设置页、菜单栏

更详细的架构说明：

- [代码架构蓝图](./docs/code-architecture-blueprint.md)
- [Swift 骨架设计](./docs/swift-scaffold-design.md)
- [工程权衡决策](./docs/engineering-tradeoff-decision.md)

## 源码发布边界

公开仓库不会包含以下本地敏感内容：

- 本地百炼 API Key
- 本地签名证书与私钥
- 本地构建产物
- 本地 `DerivedData` / `.derived`

如果你要在自己的机器上做本地签名，仓库中会保留脚本，但不会保留：

- 证书文件
- 私钥文件
- 密码

## 项目文档

- [竞品调研](./research/competitor-research-2026-04-10.md)
- [产品需求文档](./docs/product-requirements.md)
- [技术架构](./docs/technical-architecture.md)
- [V1 系统设计](./docs/v1-system-design.md)
- [代码架构蓝图](./docs/code-architecture-blueprint.md)
- [Swift 骨架设计](./docs/swift-scaffold-design.md)
- [工程权衡决策](./docs/engineering-tradeoff-decision.md)
- [实施计划](./docs/implementation-plan.md)
- [源码发布说明](./docs/source-release-guide.md)
- [Vibe Coding 开发说明](./docs/vibe-coding-guide.md)
