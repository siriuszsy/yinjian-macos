# voiceKey 脚手架约束

最后更新：2026-04-11

## 1. 当前阶段目标

当前阶段只做两件事：

- 把工程结构钉死
- 把依赖边界钉死

当前阶段明确不做：

- 提前实现复杂功能
- 为未来模式预建大量抽象
- 在 `Infrastructure` 里偷塞业务逻辑

## 2. 目录放置规则

### 2.1 `App/`

只放：

- 应用入口
- 对象装配
- 生命周期

不放：

- AX 逻辑
- 阿里云请求
- 业务状态机

### 2.2 `Presentation/`

只放：

- 菜单栏
- HUD
- 设置页
- 权限提示

不放：

- ASR 逻辑
- clean-up 逻辑
- 插入逻辑

### 2.3 `Application/`

只放：

- `DictationOrchestrator`
- dictation 状态模型
- 失败回退编排
- metrics 编排

这层可以知道流程，不可以知道系统 API 细节。

### 2.4 `Domain/`

只放：

- 纯模型
- 纯协议

不放：

- 具体实现
- 平台依赖细节

### 2.5 `Infrastructure/`

只放：

- macOS 能力适配
- 阿里云 API 适配
- 文件/Keychain 持久化

这层不允许做“产品策略判断”。

## 3. 依赖规则

允许：

```text
Presentation -> Application -> Domain
Infrastructure -> Domain
App -> Presentation/Application/Infrastructure
```

不允许：

```text
Presentation -> Infrastructure/Aliyun
Application -> AVAudioEngine / AXUIElement / NSPasteboard
Domain -> AppKit / SwiftUI
```

## 4. 文件粒度规则

每个文件先只放一个主类型。

允许的例外：

- 协议 + 配套 delegate
- 很小的 supporting enum

这样做的目的不是教条，而是：

- 方便快速定位
- 方便后面做 app-specific 替换
- 方便把实现和接口拆开看

## 5. TODO 规则

当前阶段允许有 `TODO`，但只允许出现在：

- 需要真实系统 API 才能落的地方
- 需要真实网络协议才好定的地方

不允许用 `TODO` 掩盖应该在当前阶段就能做清楚的边界设计。

## 6. 新文件加入规则

如果后面新增一个文件，先问自己：

1. 它属于哪一层？
2. 它是接口，还是实现？
3. 它有没有破坏 `DictationOrchestrator` 的编排边界？
4. 它是不是在提前为未来功能做抽象？

如果第 4 个问题答案是“是”，默认不要加。

## 7. 当前推荐工作流

1. 先改 `Domain`
2. 再改 `Application`
3. 再落 `Infrastructure`
4. 最后补 `Presentation`

这能避免 UI 先跑太快，把底层边界弄脏。

## 8. 当前脚手架入口

- 项目生成配置：[project.yml](../project.yml)
- 代码架构蓝图：[code-architecture-blueprint.md](./code-architecture-blueprint.md)
- Swift 骨架设计：[swift-scaffold-design.md](./swift-scaffold-design.md)

## 9. 结论

当前这套脚手架的目的不是“看起来完整”，而是：

- 让功能以后加得进去
- 让 trigger / ASR / insertion 以后换得出来
- 不让 v1 在还没做完时先烂成一坨
