# voiceKey Runtime Indicator State Machine

最后更新：2026-04-11

## 1. 目标

这份文档只描述一件事：

`Floating Orb 在 v1 里如何根据底层信号切换 UX 状态。`

这层当前是 preview state machine。

也就是说：

- 先把交互壳子打磨顺
- 真实录音 / ASR / clean-up / insertion 之后再把真实信号接进来

## 2. UX 状态

当前所有会展现给用户的状态如下。

### 2.1 `idle`

表现：

- 完全隐藏
- 桌面上不显示常驻红点
- 只保留菜单栏入口

### 2.2 `listening(triggerKey)`

表现：

- orb 放大
- 核心点轻微跳动
- 文案提示当前触发键，例如 `Hold Right Option and speak`

### 2.3 `processing(stage)`

表现：

- 维持 orb
- 主标题统一为 `Thinking`
- 展示更明确的状态卡
- 根据不同调用阶段显示不同副标题

阶段包括：

- `finalizingCapture`
- `transcribingAudio`
- `cleaningTranscript`
- `insertingText`

### 2.4 `success(message)`

表现：

- 绿色成功态
- 短暂确认后自动回到 `idle`

### 2.5 `fallback(message)`

表现：

- 红色 fallback 态
- 例如 `Copied to clipboard as fallback`
- 短暂停留后自动隐藏

### 2.6 `blocked(reason)`

表现：

- 权限阻塞态
- 当前支持：
  - `microphonePermission`
  - `accessibilityPermission`
  - `inputMonitoring`

### 2.7 `error(message)`

表现：

- 一句短错误
- 当前主要用于网络失败或未知失败

## 3. 底层信号

当前状态机接受这些信号：

- `appReady(triggerKey)`
- `triggerPressed(triggerKey)`
- `triggerReleased`
- `audioFinalizationStarted`
- `asrRequestStarted`
- `asrResponseReceived`
- `cleanupRequestStarted`
- `cleanupResponseReceived`
- `insertionStarted`
- `insertionSucceeded`
- `fallbackPrepared(message)`
- `microphonePermissionDenied`
- `accessibilityPermissionDenied`
- `inputMonitoringDenied`
- `networkRequestFailed(message)`
- `unknownFailure(message)`
- `autoDismiss`
- `reset`

## 4. 底层调用阶段

这里只描述用户应该感知到的调用阶段，不描述底层 SDK 细节。

### 4.1 `finalizingCapture`

含义：

- 触发键已抬起
- 当前录音片段正在收口

### 4.2 `transcribingAudio`

含义：

- 正在调用 `qwen3-asr-flash`

### 4.3 `cleaningTranscript`

含义：

- 正在调用 `qwen3.5-flash`

### 4.4 `insertingText`

含义：

- 正在把文本写回当前输入框

## 5. 当前预览路径

当前 preview coordinator 里的默认 happy path 是：

1. `triggerPressed`
2. `triggerReleased`
3. `asrRequestStarted`
4. `cleanupRequestStarted`
5. `insertionStarted`
6. `insertionSucceeded`
7. `autoDismiss`

fallback 路径是：

1. `triggerPressed`
2. `triggerReleased`
3. `asrRequestStarted`
4. `cleanupRequestStarted`
5. `insertionStarted`
6. `fallbackPrepared`
7. `autoDismiss`

## 6. 状态切换原则

### 6.1 同位变形

所有状态都在同一个 orb 上发生，不弹第二个 HUD。

### 6.1.1 `idle` 必须隐藏

待机态不显示常驻悬浮点。

真正的运行时浮层只在：

- 按下 trigger 后出现
- thinking 期间保留
- 成功或 fallback 后短暂停留
- 然后自动隐藏

### 6.2 状态少，但阶段清楚

不为每个底层 API 造一个新面板，但要让用户知道当前大概在：

- 收口
- 转写
- 清理
- 插入

### 6.3 错误可解释

失败不能只有红点，必须至少能看懂：

- 是权限
- 是网络
- 还是 fallback

## 7. 当前代码入口

- 状态定义：[RuntimeIndicatorState.swift](../voiceKey/Domain/Models/RuntimeIndicatorState.swift)
- 状态机实现：[RuntimeIndicatorStateMachine.swift](../voiceKey/Application/Dictation/RuntimeIndicatorStateMachine.swift)
- preview 协调器：[RuntimeIndicatorPreviewCoordinator.swift](../voiceKey/Application/Dictation/RuntimeIndicatorPreviewCoordinator.swift)
- orb 视图：[StatusHUD.swift](../voiceKey/Presentation/HUD/StatusHUD.swift)

## 8. 结论

当前这套状态机的目的不是提前做真实业务，而是：

- 先把 UX 交互壳子做顺
- 先把状态名、信号名、调用阶段名做清楚
- 让后面接真实录音 / ASR / insertion 时，只是“换信号来源”，不是“重写交互”
