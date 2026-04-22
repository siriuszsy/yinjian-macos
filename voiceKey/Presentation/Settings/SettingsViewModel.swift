import Combine
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var settings: AppSettings = .default
    @Published var apiKeyInput: String = ""
    @Published private(set) var permissionStatus = SystemPermissionStatus(
        inputMonitoring: .notRequired,
        accessibility: .needsSetup,
        microphone: .needsSetup
    )
    @Published private(set) var setupMessage: String?
    @Published private(set) var saveMessage: String?
    @Published private(set) var apiKeyStatusText: String = "未配置"

    private let settingsStore: SettingsStore
    private let apiKeyStore: APIKeyStore
    private let permissionService: PermissionService
    private let applySettings: ((AppSettings, AppSettings) throws -> Void)?

    init(
        settingsStore: SettingsStore,
        apiKeyStore: APIKeyStore,
        permissionService: PermissionService,
        applySettings: ((AppSettings, AppSettings) throws -> Void)? = nil
    ) {
        self.settingsStore = settingsStore
        self.apiKeyStore = apiKeyStore
        self.permissionService = permissionService
        self.applySettings = applySettings
        self.settings = (try? settingsStore.load()) ?? .default
        self.permissionStatus = permissionService.currentStatus()
        refreshAPIKeyStatus()
    }

    var triggerKeyDisplayName: String {
        settings.triggerKey.displayName
    }

    var translationTriggerKeyDisplayName: String {
        settings.translationTriggerKey.displayName
    }

    var availableTranslationTriggerKeys: [TriggerKey] {
        TriggerKey.translationChoices.filter { $0 != settings.triggerKey }
    }

    var microphoneDisplayName: String {
        if settings.microphoneDeviceID == "system-default" {
            return "系统默认"
        }

        return settings.microphoneDeviceID
    }

    var accessibilityState: PermissionState {
        permissionStatus.accessibility
    }

    func save() {
        let persistedSettings = (try? settingsStore.load()) ?? .default
        let normalizedSourceLanguage = normalizedTranslationSourceLanguage(settings.translationSourceLanguage)
        let normalizedTargetLanguage = normalizedTranslationTargetLanguage(settings.translationTargetLanguage)
        guard normalizedTargetLanguage.caseInsensitiveCompare("auto") != .orderedSame else {
            saveMessage = "翻译目标语言不能设为 auto。"
            return
        }
        guard settings.triggerKey != settings.translationTriggerKey else {
            saveMessage = "听写和翻译触发键不能使用同一组按键。"
            return
        }
        guard TriggerKey.translationChoices.contains(settings.translationTriggerKey) else {
            saveMessage = "翻译触发键当前只支持 `Fn`、`Fn + Control` 和 `Fn + Shift`。"
            return
        }

        settings.cleanupModel = normalizedCleanupModel(settings.cleanupModel)
        settings.translationSourceLanguage = normalizedSourceLanguage
        settings.translationTargetLanguage = normalizedTargetLanguage
        do {
            try settingsStore.save(settings)
            try applySettings?(persistedSettings, settings)
            saveMessage = "设置已保存并已生效"
        } catch {
            saveMessage = "设置已保存，但热键应用失败：\(error.localizedDescription)"
        }
    }

    func applyASRModeChange() {
        let persistedSettings = (try? settingsStore.load()) ?? .default
        guard persistedSettings.asrMode != settings.asrMode else {
            return
        }

        var updatedSettings = persistedSettings
        updatedSettings.asrMode = settings.asrMode

        do {
            try settingsStore.save(updatedSettings)
            try applySettings?(persistedSettings, updatedSettings)
            saveMessage = "识别模式已切换并已生效"
        } catch {
            saveMessage = "识别模式已切换，但应用失败：\(error.localizedDescription)"
        }
    }

    func saveAPIKey() {
        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            apiKeyStatusText = "请输入百炼 API Key。"
            return
        }

        do {
            try apiKeyStore.save(trimmed)
            apiKeyInput = ""
            refreshAPIKeyStatus()
        } catch {
            apiKeyStatusText = "API Key 保存失败：\(error.localizedDescription)"
        }
    }

    func resetToDefaults() {
        settings = .default
        saveMessage = "已恢复默认配置"
    }

    func refreshPermissions() {
        permissionStatus = permissionService.currentStatus()
    }

    func refreshAPIKeyStatus() {
        do {
            let key = try apiKeyStore.load()
            if key.isEmpty {
                apiKeyInput = ""
                apiKeyStatusText = "未配置"
            } else {
                apiKeyInput = key
                apiKeyStatusText = "API Key 已保存到本地"
            }
        } catch {
            apiKeyInput = ""
            apiKeyStatusText = "未配置"
        }
    }

    func requestAccessibility() {
        _ = permissionService.requestAccessibilityAccess()
        setupMessage = "辅助功能通常需要在系统设置里手动打开。完成后回到这里会自动刷新；没授权前会先回退到剪贴板。"
        refreshPermissions()
    }

    func requestMicrophone() {
        permissionService.requestMicrophoneAccess { [weak self] _ in
            Task { @MainActor in
                self?.setupMessage = "麦克风权限状态已刷新。"
                self?.refreshPermissions()
            }
        }
    }

    func openAccessibilitySettings() {
        openSystemSettings(for: .accessibility, successMessage: "已打开系统设置的辅助功能页。授权后回到这里会自动刷新；如果写入仍无效，请重启应用。")
    }

    func openMicrophoneSettings() {
        openSystemSettings(for: .microphone, successMessage: "已打开系统设置的麦克风页。授权后回到这里会自动刷新。")
    }

    var permissionHintText: String {
        "默认热键是 `Fn` 听写、`Fn + Control` 翻译。当前实现会直接尝试注册；如果个别机器收不到，再去打开键盘监听。"
    }

    private func openSystemSettings(
        for permission: SystemPermissionKind,
        successMessage: String
    ) {
        if permissionService.openSystemSettings(for: permission) {
            setupMessage = successMessage
        } else {
            setupMessage = "没能直接打开系统设置，请手动进入“系统设置 > 隐私与安全性”。"
        }
    }

    private func normalizedCleanupModel(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AppSettings.default.cleanupModel : trimmed
    }

    private func normalizedTranslationSourceLanguage(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AppSettings.default.translationSourceLanguage : trimmed
    }

    private func normalizedTranslationTargetLanguage(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AppSettings.default.translationTargetLanguage : trimmed
    }
}
