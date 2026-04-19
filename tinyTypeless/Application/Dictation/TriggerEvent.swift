import Foundation

enum SessionIntent: String, Codable, Sendable {
    case dictation
    case translation

    var displayName: String {
        switch self {
        case .dictation:
            return "听写"
        case .translation:
            return "翻译"
        }
    }

    func triggerDisplayName(dictationTriggerKey: TriggerKey) -> String {
        switch self {
        case .dictation:
            return dictationTriggerKey.displayName
        case .translation:
            return TranslationHotKeyCatalog.primary.displayName
        }
    }
}

enum TriggerEvent: Sendable {
    case pressed(SessionIntent, Date)
    case released(SessionIntent, Date)
}
