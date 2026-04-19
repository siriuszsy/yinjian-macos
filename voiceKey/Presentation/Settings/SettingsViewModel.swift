import Combine
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var settings: AppSettings = .default
    @Published var apiKeyInput: String = ""
    @Published private(set) var permissionStatus = SystemPermissionStatus(
        inputMonitoring: .needsSetup,
        accessibility: .needsSetup,
        microphone: .needsSetup
    )
    @Published private(set) var setupMessage: String?
    @Published private(set) var saveMessage: String?
    @Published private(set) var apiKeyStatusText: String = "未配置"

    private let settingsStore: SettingsStore
    private let apiKeyStore: APIKeyStore
    private let permissionService: PermissionService

    init(
        settingsStore: SettingsStore,
        apiKeyStore: APIKeyStore,
        permissionService: PermissionService
    ) {
        self.settingsStore = settingsStore
        self.apiKeyStore = apiKeyStore
        self.permissionService = permissionService
        self.settings = (try? settingsStore.load()) ?? .default
        self.permissionStatus = permissionService.currentStatus()
        refreshAPIKeyStatus()
    }

    var triggerKeyDisplayName: String {
        settings.triggerKey.displayName
    }

    var showsInputMonitoringSetup: Bool {
        settings.triggerKey.requiresInputMonitoring
    }

    var inputMonitoringState: PermissionState {
        if settings.triggerKey.requiresInputMonitoring {
            return permissionStatus.inputMonitoring
        }

        return .notRequired
    }

    var accessibilityState: PermissionState {
        permissionStatus.accessibility
    }

    var setupSectionSubtitle: String {
        if canUseCurrentDevelopmentFlow {
            return "先把权限含义说清楚，再做具体授权。"
        }

        return "当前阶段最重要的是弄清楚：哪个权限影响录音，哪个权限影响写回。"
    }

    var microphoneDisplayName: String {
        if settings.microphoneDeviceID == "system-default" {
            return "系统默认"
        }

        return settings.microphoneDeviceID
    }

    var asrModelDisplayName: String {
        "通义语音识别（\(settings.asrMode.displayName)）"
    }

    var cleanupModelDisplayName: String {
        settings.cleanupModel
    }

    func save() {
        let normalizedSourceLanguage = normalizedTranslationSourceLanguage(settings.translationSourceLanguage)
        let normalizedTargetLanguage = normalizedTranslationTargetLanguage(settings.translationTargetLanguage)
        guard normalizedTargetLanguage.caseInsensitiveCompare("auto") != .orderedSame else {
            saveMessage = "翻译目标语言不能设为 auto。"
            return
        }

        settings.cleanupModel = normalizedCleanupModel(settings.cleanupModel)
        settings.translationSourceLanguage = normalizedSourceLanguage
        settings.translationTargetLanguage = normalizedTargetLanguage
        try? settingsStore.save(settings)
        saveMessage = "设置已保存"
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

    func requestInputMonitoring() {
        openInputMonitoringSettings()
    }

    func requestAccessibility() {
        _ = permissionService.requestAccessibilityAccess()
        setupMessage = "辅助功能通常需要在系统设置里手动打开。完成后回到这里会自动刷新。"
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

    func openInputMonitoringSettings() {
        openSystemSettings(for: .inputMonitoring, successMessage: "已打开系统设置的键盘监听页。授权后回到这里会自动刷新；如果热键仍无效，请重启应用。")
    }

    func openAccessibilitySettings() {
        openSystemSettings(for: .accessibility, successMessage: "已打开系统设置的辅助功能页。授权后回到这里会自动刷新；如果写入仍无效，请重启应用。")
    }

    func openMicrophoneSettings() {
        openSystemSettings(for: .microphone, successMessage: "已打开系统设置的麦克风页。授权后回到这里会自动刷新。")
    }

    var permissionHintText: String {
        if canUseCurrentDevelopmentFlow {
            return "当前开发版已经能走热键和录音。真正影响“文字能不能写回当前光标”的，是辅助功能权限，不是百炼 API Key。"
        }

        if settings.triggerKey.requiresInputMonitoring {
            return "当前触发键需要键盘监听权限。完成授权后回到这个窗口会自动刷新；如果热键还是没反应，请退出并重新打开音键。"
        }

        return "当前开发版的听写键和翻译键都不依赖键盘监听。录音靠麦克风权限，跨应用写回靠辅助功能权限。"
    }

    var permissionOverviewTitle: String {
        "当前版本需要的权限"
    }

    var permissionOverviewLines: [String] {
        var lines = [
            "1. 麦克风：录音必须要开。",
            "2. 辅助功能：把转写结果写回到别的应用输入框，必须要开。",
            "3. 键盘监听：只有右侧 ⌥ / Fn 这种全局单键触发才依赖它。当前默认的 `⌘ + ;` 和翻译快捷键都不依赖。"
        ]

        lines.append("成熟同类产品大概率也不是单纯靠 Cmd+V。更像是“辅助功能直写为主，剪贴板/粘贴只做回退”。")
        return lines
    }

    private var canUseCurrentDevelopmentFlow: Bool {
        let triggerReady = !settings.triggerKey.requiresInputMonitoring || permissionStatus.inputMonitoring == .granted
        return triggerReady && permissionStatus.microphone == .granted
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
