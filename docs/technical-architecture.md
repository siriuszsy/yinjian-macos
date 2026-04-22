# voiceKey 技术架构

最后更新：2026-04-11

> 注意：这份文档保留的是早期架构草案，里面仍有 `Right Option`、`CGEventTap`、`IOHIDManager` 等历史方案。当前权威版本请优先看：
> - [内部详细设计图](./internal-design.md)
> - [类图](./class-diagram.md)

## 1. 当前权威结论

`voiceKey v1` 只做一条黄金路径：

`按住触发键 -> 录音 -> 松开触发键 -> ASR -> clean-up -> 插入当前输入框 -> 结束`

当前开发期默认触发键：

`Right Option`

未来目标触发键：

`Fn`

不做：

- selected-text edit
- ask mode
- translation mode
- partial transcript
- 历史面板
- 词典 UI
- app profile UI
- hands-free

这些不是做不到，而是现在做会把项目从“像 竞品”做成“功能平台”。

## 2. 核心技术选型

### 2.1 桌面宿主

- `Swift + AppKit`
- `SwiftUI` 仅用于设置页和少量状态视图

原因：

- menubar app、权限、热键、焦点和 Accessibility 在原生层更稳
- 这个项目的关键不在复杂 UI，而在输入体验

### 2.2 热键

- 首选：`CGEventTap`
- 备选：`IOHIDManager`

说明：

- 开发期默认监听 `Right Option`
- 未来目标切换到 `Fn`
- `Fn` 和 `Option` 都属于 modifier 路线，不能假设普通快捷键库一定能稳监听

### 2.3 录音

- `AVAudioEngine`
- 临时内存 buffer 或临时文件

原则：

- 按下立即开始
- 松开立即停止
- 默认不持久化原始音频

### 2.4 ASR

- `qwen3-asr-flash`

职责：

- 把短语音变成文本
- 不承担理解
- 不承担改写

### 2.5 Clean-up

- `qwen-flash`

职责：

- 去口头禅
- 去重复
- 合并明显改口
- 补基础标点
- 让文本更像正常键入

原则：

- 不扩写
- 不总结
- 不解释
- 不改变原意

### 2.6 文本插入

- 主路径：`AXUIElement`
- 回退路径：`NSPasteboard + synthetic paste`

### 2.7 本地存储

v1 只保留最小状态：

- `settings.json`
- `sessions.jsonl`

说明：

现在还不需要 SQLite。等功能范围扩大后再上。

### 2.8 密钥存储

- `macOS Keychain`

不把阿里云 API key 放在明文 JSON 里。

## 3. 为什么这版更对

这版设计是刻意收窄后的结果。

核心判断：

- 竞品 的核心价值不是功能列表
- 而是“说完就落成干净文本”
- 你现在最需要的是可替代，不是可扩展

所以这版架构做了 3 个收缩：

1. `ASR` 和 `理解` 明确分层
2. 去掉了说话中 partial transcript
3. 去掉了所有非黄金路径动作

这样做有两个直接好处：

- 工程复杂度明显下降
- 交互更容易做到丝滑

## 4. 轻量化自检

### 4.1 有没有更轻量级的技术

有，但都不值得当 v1 主方案。

#### A. 宿主改成 Electron

更轻吗：

- 开发者熟悉时，初期搭壳更快

为什么不选：

- 热键、权限、焦点、辅助功能链路更脆
- 你会在输入层系统集成上付额外成本

#### B. 录音改成命令行工具

更轻吗：

- 原型更快

为什么不选：

- 启动和控制粒度差
- 很难做出 竞品 那种“按下即听”的反应

#### C. ASR 改成 `qwen3-asr-flash-filetrans`

更轻吗：

- 接口形态简单

为什么不选：

- 更偏文件识别
- 与输入层短语音交互不完全匹配

#### D. Clean-up 只用本地规则

更轻吗：

- 成本和实现都更轻

为什么不选：

- 做不到自然的改口收敛和句子整理

#### E. 注入只用剪贴板

更轻吗：

- 最简单

为什么不选：

- 污染剪贴板
- 兼容性和体验都差

结论：

`Swift + AppKit + AXUIElement + 阿里双模型` 已经是足够轻，同时不明显牺牲体验的方案。

### 4.2 交互是不是丝滑

丝滑不是靠“模型强”，而是靠这 5 个细节：

- 按下立刻有录音反馈
- 松开后没有额外确认步骤
- 处理中有轻量可感知状态
- 成功后结果直接落到目标输入框
- 失败时结果不丢

## 5. 系统边界

### 5.1 v1 范围内

- menubar app
- `Fn` hold-to-talk
- 麦克风权限
- Accessibility 权限
- 短语音录音
- 阿里 ASR
- 阿里 clean-up
- 当前输入框文本插入
- 最小日志

### 5.2 v1 范围外

- 复杂模式切换
- 语音问答
- 选中文本操作
- 翻译
- 历史浏览
- 账号系统
- 云端存储

## 6. 模块拆分

### 6.1 `AppBootstrap`

职责：

- 启动应用
- 初始化菜单栏
- 加载设置
- 初始化依赖对象

### 6.2 `PermissionCoordinator`

职责：

- 检查麦克风权限
- 检查 Accessibility 权限
- 向 UI 暴露状态

### 6.3 `HotkeyEngine`

职责：

- 捕获触发键 `down`
- 捕获触发键 `up`
- 将物理键事件转换成 `PressStart / PressEnd`

### 6.4 `RecordingEngine`

职责：

- 开始录音
- 停止录音
- 产出音频数据或临时文件 URL

### 6.5 `ASRClient`

职责：

- 调用 `qwen3-asr-flash`
- 返回原始 transcript

### 6.6 `CleanupClient`

职责：

- 调用 `qwen-flash`
- 返回最终插入文本

### 6.7 `ContextInspector`

职责：

- 获取当前 focused app
- 获取当前 focused element
- 判断当前是否可编辑

### 6.8 `InsertionEngine`

职责：

- 主路径用 AX 写入文本
- 失败时走剪贴板回退

### 6.9 `StatusHUDController`

职责：

- 展示录音中状态
- 展示处理中状态
- 展示成功或失败提示

### 6.10 `SessionLogger`

职责：

- 记录开始时间、结束时间、耗时、成功与否
- 记录失败原因

## 7. 关键数据结构

### 7.1 `settings.json`

```json
{
  "triggerKey": "right_option",
  "microphoneDeviceId": "default",
  "cleanupEnabled": true,
  "showHUD": true,
  "fallbackPasteEnabled": true
}
```

### 7.2 `sessions.jsonl`

每行一条：

```json
{
  "id": "uuid",
  "startedAt": "2026-04-11T10:00:00Z",
  "endedAt": "2026-04-11T10:00:03Z",
  "focusedApp": "com.apple.Notes",
  "rawTranscript": "欢迎使用阿里云",
  "cleanText": "欢迎使用阿里云。",
  "inserted": true,
  "fallbackUsed": false,
  "failureReason": null,
  "latencyMs": {
    "recording": 1200,
    "asr": 480,
    "cleanup": 190,
    "insertion": 35,
    "totalAfterRelease": 705
  }
}
```

## 8. 性能预算

目标预算：

- `trigger down -> HUD visible`：`<100ms`
- `trigger up -> ASR done`：`<800ms`
- `trigger up -> clean-up done`：`<1100ms`
- `trigger up -> inserted`：`<1200ms`

容忍上限：

- `trigger up -> inserted`：`1800ms`

超过这个阈值，用户就会明显感觉拖。

## 9. 失败回退策略

### 9.1 没拿到权限

行为：

- 不开始录音
- HUD 提示缺少权限
- 菜单栏显示错误状态

### 9.2 ASR 失败

行为：

- 不调用 clean-up
- HUD 提示失败
- 记录失败日志

### 9.3 Clean-up 失败

行为：

- 直接使用原始 transcript 插入
- 不丢文本

### 9.4 AX 插入失败

行为：

- 进入剪贴板回退
- 保留用户原剪贴板并在操作后恢复

### 9.5 回退也失败

行为：

- 把最终文本展示在 HUD 或 alert 中
- 支持一键复制

## 10. 关键技术风险

### 10.1 触发键监听可靠性

风险：

- 不同机器和键盘布局对 modifier 键的处理不一致
- `Right Option` 和 `Fn` 的事件行为不完全一样

应对：

- 第一优先做 spike
- 抽象出 trigger interface，不把具体键位写死在深层
- 开发期先打通 `Right Option`，再切到 `Fn`

### 10.2 AX 注入兼容性

风险：

- 不同 app 的文本控件行为不同

应对：

- 先固定 3 个目标 app
- Notes、Slack、Chrome 文本框优先

### 10.3 Clean-up 过度发挥

风险：

- 模型把口语“改好”成了别的意思

应对：

- 使用非常保守的 prompt
- 失败时可以回退原始 transcript

### 10.4 总延迟超预算

风险：

- 每一段都只慢一点，叠起来就难用了

应对：

- 全链路记录 latency
- 不做与黄金路径无关的 UI 和状态

## 11. 权威结论

当前最合理的 v1 架构是：

`Swift menubar host + configurable hold-to-talk trigger + AVAudioEngine + qwen3-asr-flash + qwen-flash + AXUIElement insertion`

这版已经足够接近 竞品 的核心，不再需要扩设计。
