import Foundation

struct AppSettings: Codable, Sendable {
    var triggerKey: TriggerKey
    var microphoneDeviceID: String
    var cleanupEnabled: Bool
    var showHUD: Bool
    var fallbackPasteEnabled: Bool

    static let `default` = AppSettings(
        triggerKey: .commandSemicolon,
        microphoneDeviceID: "system-default",
        cleanupEnabled: true,
        showHUD: true,
        fallbackPasteEnabled: true
    )
}
