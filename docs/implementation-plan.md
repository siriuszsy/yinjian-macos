# tinyTypeless 实施计划

最后更新：2026-04-11

## 1. 当前范围

v1 只做：

`按住 Right Option -> 说话 -> 松开 Right Option -> 转文本 -> clean-up -> 插入当前输入框`

不做任何扩展动作。

## 2. 总体策略

实现顺序必须贴着风险走，不是贴着功能表走。

先解决：

1. `Right Option` 能不能稳监听
2. 文本能不能稳插回去
3. 阿里 ASR + clean-up 串起来后延迟能不能接受

只有这三件事打通，v1 才成立。

工程权衡原则见：

- [工程权衡决策](./engineering-tradeoff-decision.md)

## 3. 阶段计划

### Phase 0：外部能力验证

目标：

确认阿里链路可用。

交付：

- `qwen3-asr-flash` 调通
- `qwen3.5-flash` clean-up 调通
- 两段串联验证通过

状态：

- 已完成

### Phase 1：输入层 Spike

目标：

验证本地最难的两个点。

交付：

- `Right Option down / up` 事件可捕获
- 固定文本可以插入 Notes
- 固定文本可以插入 Slack
- 固定文本可以插入 Chrome 文本框

验收标准：

- 3 个目标 app 至少 2 个主路径成功
- 剩下失败项能定位具体原因

### Phase 2：端到端最小闭环

目标：

完成第一条真实黄金路径。

交付：

- menubar app
- 麦克风权限引导
- Accessibility 权限引导
- `Right Option` hold-to-talk
- 录音停止后调用 `qwen3-asr-flash`
- transcript 调用 `qwen3.5-flash` clean-up
- clean text 插入当前输入框
- HUD 状态提示

验收标准：

- Notes / Slack / Chrome 中至少 2 个场景真正可用
- `Right Option up -> inserted` 小于 `1.8s`

### Phase 3：失败回退与可用性

目标：

让工具不脆。

交付：

- clean-up 失败时回退原始 transcript
- AX 插入失败时走剪贴板回退
- 最小日志 `sessions.jsonl`
- 基础设置 `settings.json`
- API key 存进 Keychain

验收标准：

- 输入链路失败时文本不丢
- 有最小调试证据能看出失败点

### Phase 4：日用打磨

目标：

把这东西从“能跑”拉到“愿意天天开”。

交付：

- 录音 HUD 反应更快
- 处理 HUD 不打断输入流
- clean-up prompt 收紧
- 麦克风切换更稳
- 性能指标记录更完整

验收标准：

- 连续使用一天不想切回 Typeless

## 4. 推荐节奏

如果单人推进，现实节奏是 `1 到 2 周`。

### 第 1 天

- 阿里链路验证
- 工程骨架

### 第 2 到 3 天

- `Right Option` 监听 spike
- AX 注入 spike

### 第 4 到 6 天

- 录音
- ASR
- clean-up
- 插入

### 第 7 到 10 天

- HUD
- fallback
- keychain
- logging

## 5. 实现顺序

严格按下面顺序做：

1. `Right Option` 捕获
2. AX 插入
3. menubar 宿主
4. 录音
5. ASR client
6. clean-up client
7. orchestrator 串联
8. HUD
9. fallback
10. logging 与 settings

不要先做设置页，不要先做漂亮 UI。

## 6. 关键风险

### 6.1 `Right Option` 不稳定

风险：

- 某些输入法或系统设置下，`Right Option` 可能与预期行为冲突

应对：

- 把 trigger 抽象出来
- 后续可切回 `Fn`
- 允许内部临时切换调试键

### 6.2 AX 插入失败

风险：

- 不同 app 的文本控件差异很大

应对：

- 固定 3 个 app 回归
- 先主路径，后剪贴板回退

### 6.3 clean-up 改坏原意

风险：

- 模型把口语改写成别的意思

应对：

- prompt 极度保守
- clean-up 失败直接回退 raw transcript

### 6.4 总延迟超预算

风险：

- 用户松键后等太久

应对：

- 每段记录耗时
- 不上任何非必要功能

## 7. 升级触发条件

下面这些条件一旦出现，就停止继续追求“更轻”，直接升级实现。

### 7.1 Trigger 升级

条件：

- `Right Option` 捕获不稳

动作：

- `CGEventTap` 之外补 `IOHIDManager`

### 7.2 ASR 升级

条件：

- `Right Option up -> inserted` 经常大于 `1200ms`
- 或主观上明显慢于 Typeless

动作：

- 从 `qwen3-asr-flash` 升级到 `qwen3-asr-flash-realtime`

### 7.3 Insertion 升级

条件：

- 某个高频 app 主路径成功率不够

动作：

- 做 app-specific insertion strategy

## 8. 当前最合理的下一步

直接开始 `Phase 1`。

也就是：

`Right Option capture spike + AX insertion spike`

只要这两个点被打通，剩下部分基本都是正常工程工作。
