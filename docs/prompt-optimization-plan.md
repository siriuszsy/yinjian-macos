# voiceKey Prompt 优化方案

最后更新：2026-04-13

## 1. 结论

当前 cleanup prompt 不是完全没做，而是已经有一套可工作的 v1：

- 先做 `plain / list_like / instruction_like` 分类
- 再按 profile 做文本整理
- 已经覆盖：
  - 去口头禅
  - 去重复
  - 改口收敛
  - 缩写合并
  - 基础标点
  - 技术术语保护

但它离“上线前稳定可控”还有明显差距。

核心问题不是规则数量不够，而是：

- 任务边界还不够硬
- 高风险内容保护不够清楚
- few-shot 样例覆盖面太窄
- 评测体系还没建立
- 远端分类链路是否值得保留，还没有用数据证明

下一版 prompt 的目标应该不是“更聪明地改写”，而是：

`更稳地做最小必要编辑。`

## 2. 当前实现

当前 cleanup 主链路：

- `AliyunCleanupService` 会先调用一次分类，再调用一次正式 cleanup。
- 当前 cleanup model 已可配置，默认是 `qwen-flash`。
- 当前 prompt context 只有：
  - `appName`
  - `bundleIdentifier`
  - `preserveMeaning`
  - `removeFillers`

当前实现中已经存在的策略：

- 分类阶段：
  - `plain`
  - `list_like`
  - `instruction_like`
- 主 prompt 已明确要求：
  - 不扩写
  - 不总结
  - 不解释
  - 删除口头禅
  - 删除重复
  - 保留最后成立的改口
  - 合并字母拆读缩写
  - 补必要标点
  - 保留命令、路径、文件名、快捷键、英文术语
- 已有少量 few-shot 样例：
  - 列表
  - 重复
  - 技术口语压缩
  - Applications 路径纠正

## 3. 当前问题

### 3.1 任务定义仍然偏宽

当前 prompt 里有“允许轻微重写”这类说法。

这对模型来说太宽了，会带来两个问题：

- 容易把“整理”做成“改写”
- 容易为了顺滑度牺牲原始语义和用户语气

更稳的定义应该是：

`只做最小必要编辑，不做风格重写。`

### 3.2 没有显式的高风险保护清单

当前 prompt 虽然提到“命令、路径、文件名、快捷键、代码、英文术语尽量原样保留”，但还不够完整，也不够刚性。

高风险内容至少应明确包括：

- 数字
- 日期
- 时间
- 百分比
- 金额
- 单位
- 否定词
- 专有名词
- app 名
- 文件名
- 路径
- 命令
- 快捷键
- URL
- 中英混合产品名

如果不显式保护，模型会更容易做这些危险动作：

- 改掉数值
- 丢掉“不/没”
- 把路径改成“更自然”的中文
- 把英文产品名改成近似词

### 3.3 语气词删除没有分层

“嗯、啊、呃、那个”这类通常可删。

但下面这些词不能一刀切：

- 但是
- 所以
- 其实
- 可能
- 大概
- 有点
- 先
- 再

它们经常承载逻辑、语气强弱或执行顺序。

下一版要把“可删语气词”和“保留语气修饰”分开。

### 3.4 样例数量太少，且分布偏技术场景

当前样例偏工程语境，覆盖不到这些高频真实输入：

- 聊天语气
- 日常短句
- 中英混说
- 数字和时间
- 产品名/人名
- 否定句
- 不该清洗掉的软化语气

few-shot 的问题不是数量少本身，而是：

- 错误类型覆盖不够
- 边界样本不够
- “该改”和“不该改”的对照不够

### 3.5 分类链路是否值得保留还不清楚

当前 cleanup 是两次远端调用：

- 一次 classifier
- 一次正式 cleanup

这在逻辑上是干净的，但在输入工具里有两个问题：

- 增加延迟
- 增加 token 消耗

如果 classifier 的收益不明显，后面应优先考虑：

- 用本地 heuristic 覆盖大部分 list 场景
- 只在少数难例上保留远端分类
- 甚至完全取消分类，直接在主 prompt 里做模式识别

## 4. 外部策略结论

### 4.1 阿里云百炼当前推荐方向

根据阿里云百炼当前文档，文本提示词设计的核心建议是：

- prompt 要清晰、具体
- 使用明确的 prompt framework
- 提供输出样例
- 用分隔符拆开不同内容单元
- prompt chaining 更适合逻辑复杂任务，不是默认方案

对 voiceKey 这类低延迟 cleanup 来说，这意味着：

- 不应继续把规则堆成一大段自然语言
- 应改成分区明确的结构化 prompt
- 应优先 few-shot，而不是运行时多轮 prompt chaining

### 4.2 通用提示词工程建议

OpenAI 当前 best practices 强调：

- clear and specific
- iterative refinement
- 用数据集而不是纯主观印象调 prompt

OpenAI Prompt Optimizer 还明确建议：

- 建评测集
- 加 `Good/Bad` 标注
- 记录具体 critique
- 用 graders 或人工 rubric 去迭代 prompt

这对 voiceKey 的直接启发是：

- prompt 调优必须离线化
- 不能只靠“今天试了感觉顺一点”
- 上线前必须有样本集和打分标准

### 4.3 研究面的启发

学术界在 ASR 后处理上长期把这些问题拆开来看：

- disfluency removal
- punctuation restoration
- style cleanup

研究结论对我们最有用的不是某个模型，而是两个判断：

- `ASR -> cleanup` 这种 pipeline 仍然是合理路线
- “清理口语”不是单一动作，而是若干高风险编辑动作的组合

所以工程上更合理的做法是：

- 明确哪些编辑允许
- 明确哪些编辑禁止
- 对每类错误单独评估

## 5. 下一版 Prompt 总原则

下一版 prompt 应遵守 6 条原则：

1. `最小编辑`

只做让文本可读、可输入、像手打的最小必要修改。

2. `原意优先`

顺滑度不能以改变语义为代价。

3. `高风险内容默认不改`

遇到数字、专有词、命令、路径、快捷键、英文名，优先原样保留。

4. `先删噪声，再补结构`

先处理口头禅、重复、改口残片，再补标点和格式。

5. `风格轻，不要润色`

目标是像用户手打，不是像编辑改稿。

6. `样例驱动，不靠规则堆叠`

与其继续加 20 条规则，不如补 8 到 12 个覆盖关键边界的好样例。

## 6. 建议的新 Prompt 结构

下一版建议改成结构化 prompt，而不是一整段连续说明。

建议结构：

- `#Role#`
- `#Task#`
- `#Allowed Edits#`
- `#Never Change#`
- `#Style#`
- `#Examples#`
- `#Input#`
- `#Output#`

建议内容方向：

### 6.1 Role

- 你是语音输入后的文本清理器
- 你不是助手
- 你不是编辑
- 你不是摘要器

### 6.2 Task

- 把口语逐字稿整理成最终可直接输入的文本
- 只做最小必要编辑
- 不新增信息
- 不删除有意义的信息

### 6.3 Allowed Edits

- 删除无信息语气词
- 合并明显重复
- 收敛明显改口
- 合并字母拆读缩写
- 补必要标点
- 保留列表结构
- 把明显口语断裂整理成自然短句

### 6.4 Never Change

- 数字
- 时间
- 日期
- 金额
- 百分比
- 单位
- 路径
- 文件名
- URL
- app 名
- 产品名
- 人名
- 命令
- 快捷键
- 代码片段
- 否定关系

### 6.5 Style

- 像用户手打
- 自然
- 克制
- 不公文化
- 不做修辞润色

### 6.6 Output contract

- 只输出最终文本
- 不输出解释
- 不输出注释
- 不输出“修改后”
- 不加引号

## 7. 推荐新增的 Few-Shot 样例类型

下一版至少补到 10 类样例。

每类最好有 1 个正例，关键边界再补 1 个反例。

建议优先级：

1. `纯语气词删除`

例子目标：

- 删掉“嗯、呃、那个”
- 不误删承载逻辑的词

2. `整句重复合并`

例子目标：

- 把重复句只保留一次

3. `改口收敛`

例子目标：

- 前半句作废
- 只保留最后成立版本

4. `列表保持`

例子目标：

- “第一点、第二点、第三点”
- 输出成稳定编号列表

5. `直接指令压缩`

例子目标：

- 去掉绕弯铺垫
- 保留请求语义

6. `技术内容保护`

例子目标：

- 路径
- 文件名
- 命令
- 快捷键
- 英文产品名

7. `数字与时间保护`

例子目标：

- 时间
- 金额
- 百分比
- 数量
- 版本号

8. `中英混说保护`

例子目标：

- 中文句子里带英文术语
- 不要硬翻译

9. `聊天场景轻清理`

例子目标：

- 保留人话感
- 不要清成公文

10. `不要过度清洗`

例子目标：

- 强调语气应保留
- 软化语气应保留
- 不是所有口语痕迹都该删除

## 8. 建议建立的评测集

上线前建议先做一个小型人工评测集。

第一版规模不用大：

- 50 到 100 条

样本来源建议：

- 真实 dogfood 录音
- 高频工作场景
- 高频错误场景

标签维度建议：

- 技术输入
- 聊天输入
- 列表输入
- 指令输入
- 中英混说
- 数字密集
- 轻口语
- 重口语
- 明显改口
- 明显重复

## 9. 评测 Rubric

每条样本建议按 5 个维度打分：

1. `原意保留`

- 0 分：明显改坏
- 1 分：有偏差
- 2 分：基本正确

2. `高风险内容保真`

- 0 分：改坏数字/专有词/路径/命令
- 1 分：轻微问题
- 2 分：完全保留

3. `去噪效果`

- 0 分：没去掉关键噪声
- 1 分：部分有效
- 2 分：删除合理

4. `自然度`

- 0 分：像逐字稿或像公文
- 1 分：可接受
- 2 分：像用户手打

5. `是否过度清洗`

- 0 分：删多了
- 1 分：边界可疑
- 2 分：删改克制

上线前应重点看 3 个坏指标：

- 误改专有词
- 误改数字和否定
- 过度润色

## 10. 不建议现在做的事

当前阶段不建议：

- 运行时 prompt chaining
- 运行时展示思维链
- 为了“更智能”继续放宽改写权限
- 继续往 system prompt 无限加规则
- 先上复杂多轮 agent 式 cleanup

这些东西更像研究项目，不像输入工具。

## 11. 分阶段执行建议

### Phase A：Prompt 重写

目标：

- 从“规则堆叠型”改成“最小编辑合同型”

交付：

- 新 prompt 结构
- 新 few-shot 样例集
- `Never Change` 清单

### Phase B：离线评测

目标：

- 用样本集比 prompt 版本

交付：

- v1 prompt
- v2 prompt
- 每条样本的人工打分

### Phase C：缩链路

目标：

- 判断远端 classifier 是否值得保留

交付：

- classifier 保留版
- heuristic-only 版
- 延迟和质量对比

### Phase D：上线前收口

目标：

- 把 prompt 和评测固定下来

交付：

- 最终 prompt 模板
- 最终样本集
- 最终上线 checklist

## 12. 我对下一步的建议

如果继续推进，最合理的顺序是：

1. 先重写 cleanup prompt 结构
2. 再补 10 类 few-shot
3. 再做 50 条小评测集
4. 最后再决定 classifier 要不要砍

不要反过来。

如果样本和 rubric 还没定，先讨论“更聪明的 prompt”意义不大。

## 13. 参考资料

- 阿里云百炼 Prompt 指南：https://www.alibabacloud.com/help/en/model-studio/prompt-engineering-guide
- 阿里云百炼 Prompt 自动优化：https://www.alibabacloud.com/help/zh/model-studio/optimize-prompt
- 阿里云百炼文本生成概述：https://www.alibabacloud.com/help/zh/model-studio/text-generation
- OpenAI Prompt Engineering Best Practices：https://help.openai.com/en/articles/10032626-prompt-engineering-best-practices-for-chatgpt
- OpenAI Prompt Optimizer：https://platform.openai.com/docs/guides/prompt-optimizer
- End-to-End Speech Recognition and Disfluency Removal (EMNLP 2020)：https://aclanthology.org/2020.findings-emnlp.186/
- Unediting: Detecting Disfluencies Without Careful Transcripts (NAACL 2015)：https://aclanthology.org/N15-1161/
- Disfluency Detection using a Noisy Channel Model and a Deep Neural Language Model (ACL 2017)：https://aclanthology.org/P17-2087/
