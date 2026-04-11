# Typeless 调研

调研日期：2026-04-10

## 1. 调研范围

本次调研只回答一个问题：

`如果 tinyTypeless 要在本地替代 Typeless，最少要做到什么程度才配叫替代？`

信息来源分两类：

- Typeless 官方公开页面与发布说明
- 本机已有 Typeless 安装痕迹与既有内部调研笔记

## 2. 核心结论

Typeless 不是普通听写软件。

它本质上是一层“系统级智能输入层”，把以下几件事捏成了一个产品：

- 全局热键触发
- 低延迟语音输入
- 自动去口头禅、去重复、收敛改口
- 自动把 spoken list、步骤、要点整理成可读文本
- 对选中文本做改写、总结、解释、翻译、问答
- 按应用场景适配语气
- 维护个人词典和历史记录

如果 tinyTypeless 只做到“ASR 很准”，但没有这层输入体验，用户感知会明显低于 Typeless。

## 3. 已验证的公开事实

### 3.1 定价

根据 Typeless 官方定价页，2026-04-10 时点的信息如下：

- Pro：`$12 / member / month`，按年计费
- Pro 月付：`$30 / member / month`
- Free：`8,000 words per week`

Free 与 Pro 都公开展示了这些能力：

- Voice-to-perfect-text
- Translate
- Ask anything
- Personalized writing style and tone
- Personal dictionary
- Support for 100+ languages
- Different tones for each app
- Whisper mode

### 3.2 Typeless 官方强调的能力

在 Quickstart 和首页中，Typeless 明确强调：

- 自动去口头禅
- 自动去重复
- 说到一半改口时，保留最终意图
- 自动理解意图并优化表达
- 自动格式化 spoken lists、steps、key points
- 根据当前 app 调整语气和风格
- 支持 100+ 语言
- 个人词典
- 跨电脑上的所有 app 工作
- 零云端数据保留
- 历史保存在设备本地

### 3.3 发布说明中能看到的体验演进

公开 release notes 说明 Typeless 不是只堆功能，它在持续打磨输入层细节。

关键节点：

- `2025-08-14`，macOS Beta 上线，核心表述就是 “AI auto editing”
- `2025-09-23`，加入选中文本后的 writing assistance 和 reading assistance
- `2025-09-23`，词典支持自动学习用户纠正过的词
- `2025-09-30`，修掉蓝牙耳机延迟，支持国际键盘布局
- `2025-11-05`，Fn 键按下时立刻启用麦克风
- `2025-11-26`，继续优化 “faster and more fluid”
- `2025-12-02`，加入 translation mode
- `2025-12-24`，加入 personalization、web search、Markdown 输出

这说明它的产品判断很清楚：

`输入工具的胜负，主要看摩擦，不主要看功能数。`

### 3.4 本机安装痕迹

在本机缓存里可以看到：

- Bundle Identifier：`now.typeless.desktop`
- `CFBundleShortVersionString`：`1.1.0`
- `CFBundleVersion`：`1.1.0.89`

这和公开 release notes 中最新可见的 `v0.9.0` 并不一致。

合理推断：

- 公共发布说明页面可能落后于实际发版
- 本机已安装版本晚于公开说明页展示的版本

这是一个提醒：

`不要把官网文案当成完整产品边界。`

## 4. 从既有笔记得到的判断

已有内部笔记对 Typeless 的总结很一致，重点不在“聊天”，而在“整理”。

已经记录过的核心观察：

- 去口头禅
- 去重复
- 中途改口自动收敛
- 自动格式化 spoken lists
- 设备端历史保留

一句话总结：

`用户真正想要的不是你回一句话，而是你把我这段废话整理干净。`

这点非常关键。很多语音产品最后做成了“语音入口的聊天机器人”，而不是“真正替代键盘的输入层”。方向一偏，体验就掉了。

## 5. tinyTypeless 必须达到的体验线

要称得上替代 Typeless，最低不能少下面这几项。

### 5.1 系统级可达性

- 全局热键，最好支持 hold-to-talk
- 几乎所有常见输入框都能写进去
- 用户不用切换到某个特定窗口才能使用

### 5.2 速度

- 按下就开始
- 说话中很快看到 partial
- 松开后很快落最终文本

### 5.3 文本质量

- 输出是可以直接发出去的文本，不是“逐字稿 + 一堆口头禅”
- 能处理改口、回撤、自我修正
- 能把自然口语转成更像键入的书面表达

### 5.4 上下文动作

- 选中文本后说“缩短一点”“翻译成英文”“总结一下”
- 对只读文本也能 ask / summarize / explain

### 5.5 稳定性

- 蓝牙麦克风不能有明显延迟
- 国际键盘布局不能把热键搞废
- 权限失败时要有可恢复路径

## 6. 产品与技术判断

### 6.1 正确的产品定义

tinyTypeless 应该被定义为：

`macOS 本地智能输入层`

而不是：

- 聊天应用
- 录音笔
- 长音频转写器
- 笔记软件
- 输入法皮肤

### 6.2 正确的技术路线

最现实的路线是混合式：

- 本地流式 ASR 负责低延迟 partial 和即时反馈
- 最终文本用更强后处理负责 clean-up、改写、结构化和上下文动作

这是因为：

- 纯本地更容易快
- 混合后处理更容易接近 Typeless 的最终文本质量
- 真正影响日用体验的，不只是识别字对不对，还包括收尾和文本整理

### 6.3 错误路线

下面几条很容易做出一个“看起来像”，但日常根本替代不了 Typeless 的产品：

- 先做一个聊天框，再从聊天框里粘贴文本
- 先做长录音转写，再想办法缩成即时听写
- 纯追求模型指标，忽略热键、注入、失败回退
- 一上来做跨平台
- v1 只做逐字转录，不做 auto-edit

## 7. 可复用的参考实现与技术抓手

### 7.1 OpenSuperWhisper

用途：

- 可以作为 macOS 菜单栏听写产品的实现参考
- 已有全局快捷键、菜单栏、麦克风切换、多语言支持

局限：

- README 明确还把 `Streaming transcription`、`Custom dictionary` 列在 TODO
- 说明它更像可借壳参考，不是直接满足 tinyTypeless 要求的成品

### 7.2 WhisperKit

用途：

- 适合作为 Apple Silicon 上本地语音识别候选
- 对“本地 partial + 低延迟反馈”方向有价值

### 7.3 sherpa-onnx

用途：

- 适合作为 provider abstraction 下的离线候选
- 适合后续补齐隐私敏感或离线模式

### 7.4 macOS Accessibility API

用途：

- 获取当前 focused element
- 读取和替换选中文本
- 做系统级文本注入

这是 tinyTypeless 跨应用工作的基础，不是可选项。

## 8. 结论

tinyTypeless 如果要真的替代 Typeless，优先级应该是：

1. 系统级热键与文本注入
2. 低延迟 partial 与稳定的 turn ending
3. auto-edit 质量
4. selected-text actions
5. 个人词典、app profile、历史与隐私控制

换句话说，先把“像键盘一样随手可用”做出来，再谈别的。

## 9. 信息源

官方页面：

- https://www.typeless.com/pricing
- https://www.typeless.com/help/quickstart/key-features
- https://www.typeless.com/help/release-notes/macos
- https://www.typeless.com/help/release-notes/macos/personalized-smarter
- https://www.typeless.com/help/release-notes/macos/translation-mode

官方开发文档：

- https://developer.apple.com/documentation/applicationservices/1462095-axuielementcreatesystemwide

开源参考：

- https://github.com/Starmel/OpenSuperWhisper
- https://github.com/argmaxinc/WhisperKit
- https://github.com/k2-fsa/sherpa-onnx

本地已有笔记：

- `/Users/littlerobot/working_code/claw-phone/docs/design/listening-note-market-research-2026-03.md`
- `/Users/littlerobot/working_code/claw-phone/docs/design/listening-workbench-v2-ux.md`
- `/Users/littlerobot/working_code/claw-phone/VOICE_INTERACTION_ASR_SPEC.md`
