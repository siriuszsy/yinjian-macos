import Foundation

enum CleanupPromptProfile: String, Sendable {
    case plain = "plain"
    case listLike = "list_like"
    case instructionLike = "instruction_like"

    var label: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .plain:
            return "普通叙述"
        case .listLike:
            return "分点/清单"
        case .instructionLike:
            return "直接指令"
        }
    }

    static func fromClassifierOutput(_ value: String?) -> CleanupPromptProfile {
        let normalized = value?
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if normalized.contains("list_like") || normalized.contains("list-like") || normalized.contains("list") {
            return .listLike
        }

        if normalized.contains("instruction_like") || normalized.contains("instruction-like") || normalized.contains("instruction") {
            return .instructionLike
        }

        return .plain
    }
}

struct CleanupPromptBuilder {
    func classifierSystemPrompt(for context: CleanupContext) -> String {
        """
        你是一个语音输入整理前的路由器。
        你的任务不是改写文本，而是判断这段转写更适合哪一种整理模板。

        你只能输出以下三个标签之一，不要输出其他任何内容：
        - plain
        - list_like
        - instruction_like

        判定规则：
        1. 如果内容里有“第一点/第二点/第三点”、“第一/第二/第三”、“首先/其次/最后”、编号、多个并列事项、清单、待办、多项要求，输出 list_like。
        2. 如果内容主要是在直接要求别人执行一件事，口吻偏命令或请求，但不是多项列表，输出 instruction_like。
        3. 其他普通叙述、提问、说明，输出 plain。

        当前目标应用：\(context.appName) (\(context.bundleIdentifier))
        """
    }

    func classifierUserPrompt(for transcript: ASRTranscript) -> String {
        """
        请只输出标签。

        转写内容：
        \(transcript.rawText)
        """
    }

    func systemPrompt(for context: CleanupContext, profile: CleanupPromptProfile) -> String {
        """
        你是一个 macOS 语音输入后的最终文本整理器。
        你的任务不是回答问题，而是把逐字转写的口语，整理成用户真的会敲出来的自然文本。

        目标：
        - 保留原意和信息点。
        - 允许轻微重写，让句子更像自然输入，而不是逐字稿。
        - 输出要干净、顺滑、像用户自己打出来的。

        必须遵守：
        1. 不要扩写，不要总结，不要解释，不要回答问题。
        2. 删除不承载信息的口头禅、起句废话、重复词、迟疑、自我修正残片。
        3. 对明显改口，只保留最后成立的说法。
        4. 对明显重复的整句、短语或主谓结构，只保留一次。
        5. 对字母逐个念出的缩写，合并成正常写法，例如 A P P -> APP，P D F -> PDF。
        6. 对明显口语化的组织语言，例如“嗯”“那个”“你知道吧”“我意思是”“那我们先这样”，如果不承载实际信息就删掉。
        7. 补必要的标点和分句，但不要过度书面化，不要写得像公文。
        8. 如果内容像命令、路径、文件名、快捷键、代码、英文术语，尽量原样保留。
        9. 不要加引号，不要加前后说明，只输出最终文本。

        当前目标应用：\(context.appName) (\(context.bundleIdentifier))
        当前输出风格：\(styleGuidance(for: context))
        当前整理模式：\(profile.displayName)

        模式附加要求：
        \(profileSpecificRules(for: profile))

        示例 1
        原始：嗯，我第一点，你要帮我描述清楚这个 A P P 的作用，第二点你帮我画一下它的架构，第三点你帮我呃看一下它的整体的输出。
        输出：
        1. 帮我描述清楚这个 APP 的作用。
        2. 帮我画一下它的架构。
        3. 帮我看一下它的整体输出。

        示例 1.1
        原始：第一，看一下整体状态，第二，明确需求，第三，测试整体功能。
        输出：
        1. 看一下整体状态。
        2. 明确需求。
        3. 测试整体功能。

        示例 2
        原始：他好了，他好了，他好了，他好了。
        输出：他好了。

        示例 3
        原始：整体反应有点慢，要不你给我转换成那种那个实时的那个模型，然后用实时的那个模型回的文本可能会快一点，然后再发给我们的 text 模型。
        输出：整体反应有点慢，要不你给我转换成实时模型，然后用实时模型回的文本可能会快一点，再发给我们的 text 模型。

        示例 4
        原始：下面你帮我做一个清理战场的工作吧，现在我的这个 A P P 安装的路径是不是不对，没有在应用里，在 application 里，把把它给我放到这个应用里。
        输出：下面帮我做一个清理战场的工作。现在我的 APP 安装路径是不是不对，没有在 Applications 里？把它放到 Applications 里。
        """
    }

    func userPrompt(
        for transcript: ASRTranscript,
        context: CleanupContext,
        profile: CleanupPromptProfile
    ) -> String {
        """
        请把下面这段转写结果整理成最终可直接输入的文本。

        原始转写：
        \(transcript.rawText)

        要求：
        - \(context.preserveMeaning ? "严格保持原意" : "允许轻微改写")
        - \(context.removeFillers ? "删除口头禅和重复" : "尽量保留口语习惯")
        - 尽量让结果像用户手工输入，不像语音逐字稿
        - 如果有明显改口，只保留最后成立的版本
        - 如果有明显字母拆读，合并成正常写法
        - 当前模式：\(profile.label)
        - 只输出整理后的最终文本
        """
    }

    private func styleGuidance(for context: CleanupContext) -> String {
        let bundleIdentifier = context.bundleIdentifier.lowercased()

        if bundleIdentifier.contains("iterm")
            || bundleIdentifier.contains("terminal")
            || bundleIdentifier.contains("cursor")
            || bundleIdentifier.contains("vscode")
            || bundleIdentifier.contains("xcode") {
            return "偏直接、偏自然，像技术用户在终端或编辑器里自己敲出来的文本。保留技术术语、快捷键、路径、命令和英文产品名。"
        }

        if bundleIdentifier.contains("slack")
            || bundleIdentifier.contains("discord")
            || bundleIdentifier.contains("wechat") {
            return "偏口语、偏聊天，但仍然要干净，去掉多余重复和废话。"
        }

        return "自然、克制、干净，像用户自己手工输入，不要过度润色。"
    }

    private func profileSpecificRules(for profile: CleanupPromptProfile) -> String {
        switch profile {
        case .plain:
            return "按普通句子整理。删除废话，保留自然语气，不要强行改成列表。"
        case .listLike:
            return """
            如果内容本身带有“第一点/第二点/第三点”或多项并列结构，必须保留分点结构。
            默认输出成竖排编号列表，每一项单独一行。
            优先用阿拉伯数字编号，格式固定为：
            1. 第一项
            2. 第二项
            3. 第三项
            如果原文已经有“第一点”“第二点”“第三点”，可以保留语义，但最终排版仍然要变成逐行编号列表。
            每一项都压成短句，删掉每项前后的组织语言。
            不要把多项内容重新写成一整段散文，不要用分号把多项压回一行。
            """
        case .instructionLike:
            return "整理成直接、明确、可执行的请求或指令。去掉绕弯子的铺垫，但不要扩写。"
        }
    }
}
