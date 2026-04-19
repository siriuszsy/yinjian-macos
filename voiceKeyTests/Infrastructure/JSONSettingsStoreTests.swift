import Carbon
import XCTest
@testable import voiceKey

final class JSONSettingsStoreTests: XCTestCase {
    func testLegacySettingsDefaultToOfflineASRMode() throws {
        let legacyJSON = """
        {
          "triggerKey": "commandSemicolon",
          "microphoneDeviceID": "system-default",
          "cleanupEnabled": true,
          "showHUD": true,
          "fallbackPasteEnabled": true
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(AppSettings.self, from: legacyJSON)

        XCTAssertEqual(settings.asrMode, .offline)
        XCTAssertEqual(settings.cleanupModel, "qwen-flash")
        XCTAssertEqual(settings.translationSourceLanguage, "auto")
        XCTAssertEqual(settings.translationTargetLanguage, "English")
    }

    func testTranslationShortcutsExposeControlCommandSemicolonHotkey() {
        XCTAssertEqual(
            TranslationHotKeyCatalog.all,
            [
                FixedHotKeyShortcut(
                    keyCode: 41,
                    modifiers: UInt32(cmdKey | controlKey),
                    displayName: "⌃⌘;"
                )
            ]
        )
    }

    func testTranslationIntentUsesPrimaryShortcutDisplayName() {
        XCTAssertEqual(
            SessionIntent.translation.triggerDisplayName(dictationTriggerKey: .commandSemicolon),
            TranslationHotKeyCatalog.primary.displayName
        )
    }
}
