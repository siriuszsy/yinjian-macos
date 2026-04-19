import Foundation

enum ASRMode: String, Codable, CaseIterable, Sendable {
    case offline
    case realtime

    var displayName: String {
        switch self {
        case .offline:
            return "Offline"
        case .realtime:
            return "Realtime"
        }
    }

    var settingsSubtitle: String {
        switch self {
        case .offline:
            return "继续使用当前文件识别链路，默认更稳。"
        case .realtime:
            return "切到实时识别模型，便于排查实时链路问题。"
        }
    }
}

struct AppSettings: Codable, Sendable {
    var triggerKey: TriggerKey
    var microphoneDeviceID: String
    var asrMode: ASRMode
    var cleanupModel: String
    var cleanupEnabled: Bool
    var showHUD: Bool
    var fallbackPasteEnabled: Bool
    var translationSourceLanguage: String
    var translationTargetLanguage: String

    enum CodingKeys: String, CodingKey {
        case triggerKey
        case microphoneDeviceID
        case asrMode
        case cleanupModel
        case cleanupEnabled
        case showHUD
        case fallbackPasteEnabled
        case translationSourceLanguage
        case translationTargetLanguage
    }

    init(
        triggerKey: TriggerKey,
        microphoneDeviceID: String,
        asrMode: ASRMode,
        cleanupModel: String,
        cleanupEnabled: Bool,
        showHUD: Bool,
        fallbackPasteEnabled: Bool,
        translationSourceLanguage: String,
        translationTargetLanguage: String
    ) {
        self.triggerKey = triggerKey
        self.microphoneDeviceID = microphoneDeviceID
        self.asrMode = asrMode
        self.cleanupModel = AppSettings.normalizedCleanupModel(cleanupModel)
        self.cleanupEnabled = cleanupEnabled
        self.showHUD = showHUD
        self.fallbackPasteEnabled = fallbackPasteEnabled
        self.translationSourceLanguage = AppSettings.normalizedTranslationSourceLanguage(translationSourceLanguage)
        self.translationTargetLanguage = AppSettings.normalizedTranslationTargetLanguage(translationTargetLanguage)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        triggerKey = try container.decodeIfPresent(TriggerKey.self, forKey: .triggerKey) ?? .commandSemicolon
        microphoneDeviceID = try container.decodeIfPresent(String.self, forKey: .microphoneDeviceID) ?? "system-default"
        asrMode = try container.decodeIfPresent(ASRMode.self, forKey: .asrMode) ?? .offline
        cleanupModel = AppSettings.normalizedCleanupModel(
            try container.decodeIfPresent(String.self, forKey: .cleanupModel)
        )
        cleanupEnabled = try container.decodeIfPresent(Bool.self, forKey: .cleanupEnabled) ?? true
        showHUD = try container.decodeIfPresent(Bool.self, forKey: .showHUD) ?? true
        fallbackPasteEnabled = try container.decodeIfPresent(Bool.self, forKey: .fallbackPasteEnabled) ?? true
        translationSourceLanguage = AppSettings.normalizedTranslationSourceLanguage(
            try container.decodeIfPresent(String.self, forKey: .translationSourceLanguage)
        )
        translationTargetLanguage = AppSettings.normalizedTranslationTargetLanguage(
            try container.decodeIfPresent(String.self, forKey: .translationTargetLanguage)
        )
    }

    private static func normalizedCleanupModel(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "qwen-flash" : trimmed
    }

    private static func normalizedTranslationSourceLanguage(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "auto" : trimmed
    }

    private static func normalizedTranslationTargetLanguage(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            return "English"
        }

        return trimmed.caseInsensitiveCompare("auto") == .orderedSame ? "English" : trimmed
    }

    static let `default` = AppSettings(
        triggerKey: .commandSemicolon,
        microphoneDeviceID: "system-default",
        asrMode: .offline,
        cleanupModel: "qwen-flash",
        cleanupEnabled: true,
        showHUD: true,
        fallbackPasteEnabled: true,
        translationSourceLanguage: "auto",
        translationTargetLanguage: "English"
    )
}
