import XCTest
@testable import voiceKey

@MainActor
final class SettingsViewModelTests: XCTestCase {
    func testApplyASRModeChangePersistsImmediately() throws {
        let settingsStore = SpySettingsStore()
        settingsStore.settings.asrMode = .realtime
        let apiKeyStore = SpyAPIKeyStore()
        let permissionService = StubPermissionService()
        var appliedTransitions: [(AppSettings, AppSettings)] = []
        let viewModel = SettingsViewModel(
            settingsStore: settingsStore,
            apiKeyStore: apiKeyStore,
            permissionService: permissionService,
            applySettings: { previousSettings, settings in
                appliedTransitions.append((previousSettings, settings))
            }
        )

        viewModel.settings.asrMode = .offline
        viewModel.applyASRModeChange()

        XCTAssertEqual(try settingsStore.load().asrMode, .offline)
        XCTAssertEqual(appliedTransitions.last?.0.asrMode, .realtime)
        XCTAssertEqual(appliedTransitions.last?.1.asrMode, .offline)
        XCTAssertEqual(viewModel.saveMessage, "识别模式已切换并已生效")
    }

    func testApplyASRModeChangeIsNotBlockedByOtherUnsavedInvalidFields() throws {
        let settingsStore = SpySettingsStore()
        settingsStore.settings.asrMode = .realtime
        let apiKeyStore = SpyAPIKeyStore()
        let permissionService = StubPermissionService()
        let viewModel = SettingsViewModel(
            settingsStore: settingsStore,
            apiKeyStore: apiKeyStore,
            permissionService: permissionService,
            applySettings: nil
        )

        viewModel.settings.translationTargetLanguage = "auto"
        viewModel.settings.asrMode = .offline
        viewModel.applyASRModeChange()

        let persistedSettings = try settingsStore.load()
        XCTAssertEqual(persistedSettings.asrMode, .offline)
        XCTAssertEqual(persistedSettings.translationTargetLanguage, "English")
    }
}

private final class SpySettingsStore: SettingsStore {
    var settings = AppSettings.default

    func load() throws -> AppSettings {
        settings
    }

    func save(_ settings: AppSettings) throws {
        self.settings = settings
    }
}

private final class SpyAPIKeyStore: APIKeyStore {
    func save(_ key: String) throws {
        _ = key
    }

    func load() throws -> String {
        throw NSError(domain: "SettingsViewModelTests", code: 1)
    }
}

private final class StubPermissionService: PermissionService {
    func currentStatus() -> SystemPermissionStatus {
        SystemPermissionStatus(
            inputMonitoring: .notRequired,
            accessibility: .granted,
            microphone: .granted
        )
    }

    func requestAccessibilityAccess() -> Bool {
        true
    }

    func requestMicrophoneAccess(completion: @escaping @Sendable (Bool) -> Void) {
        completion(true)
    }

    func openSystemSettings(for permission: SystemPermissionKind) -> Bool {
        _ = permission
        return true
    }
}
