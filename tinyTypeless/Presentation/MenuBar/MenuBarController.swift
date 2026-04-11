import AppKit

@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let environment: AppEnvironment
    private let menuBuilder = MenuContentBuilder()
    private let settingsActionTarget: ClosureMenuAction
    private let debugIdleTarget: ClosureMenuAction
    private let debugHappyPathTarget: ClosureMenuAction
    private let debugFallbackTarget: ClosureMenuAction
    private let debugMicBlockedTarget: ClosureMenuAction
    private let debugAXBlockedTarget: ClosureMenuAction
    private let debugInputMonitoringBlockedTarget: ClosureMenuAction
    private let debugNetworkErrorTarget: ClosureMenuAction
    private let signalPressedTarget: ClosureMenuAction
    private let signalReleasedTarget: ClosureMenuAction
    private let signalASRTarget: ClosureMenuAction
    private let signalCleanupTarget: ClosureMenuAction
    private let signalInsertTarget: ClosureMenuAction
    private let probeInsertionTarget: ClosureMenuAction
    private var settingsWindowController: SettingsWindowController?

    init(environment: AppEnvironment) {
        self.environment = environment
        self.settingsActionTarget = ClosureMenuAction(targetAction: {})
        self.debugIdleTarget = ClosureMenuAction(targetAction: {})
        self.debugHappyPathTarget = ClosureMenuAction(targetAction: {})
        self.debugFallbackTarget = ClosureMenuAction(targetAction: {})
        self.debugMicBlockedTarget = ClosureMenuAction(targetAction: {})
        self.debugAXBlockedTarget = ClosureMenuAction(targetAction: {})
        self.debugInputMonitoringBlockedTarget = ClosureMenuAction(targetAction: {})
        self.debugNetworkErrorTarget = ClosureMenuAction(targetAction: {})
        self.signalPressedTarget = ClosureMenuAction(targetAction: {})
        self.signalReleasedTarget = ClosureMenuAction(targetAction: {})
        self.signalASRTarget = ClosureMenuAction(targetAction: {})
        self.signalCleanupTarget = ClosureMenuAction(targetAction: {})
        self.signalInsertTarget = ClosureMenuAction(targetAction: {})
        self.probeInsertionTarget = ClosureMenuAction(targetAction: {})
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.settingsActionTarget.replaceAction { [weak self] in
            self?.openSettings()
        }
        self.debugIdleTarget.replaceAction { [weak self] in
            self?.environment.runtimePreviewCoordinator.resetToIdle()
        }
        self.debugHappyPathTarget.replaceAction { [weak self] in
            self?.environment.runtimePreviewCoordinator.simulateHappyPath()
        }
        self.debugFallbackTarget.replaceAction { [weak self] in
            self?.environment.runtimePreviewCoordinator.simulateFallbackFlow()
        }
        self.debugMicBlockedTarget.replaceAction { [weak self] in
            self?.environment.runtimePreviewCoordinator.simulateMicrophoneBlocked()
        }
        self.debugAXBlockedTarget.replaceAction { [weak self] in
            self?.environment.runtimePreviewCoordinator.simulateAccessibilityBlocked()
        }
        self.debugInputMonitoringBlockedTarget.replaceAction { [weak self] in
            self?.environment.runtimePreviewCoordinator.send(.inputMonitoringDenied)
        }
        self.debugNetworkErrorTarget.replaceAction { [weak self] in
            self?.environment.runtimePreviewCoordinator.simulateNetworkFailure()
        }
        self.signalPressedTarget.replaceAction { [weak self] in
            guard let self else { return }
            self.environment.runtimePreviewCoordinator.send(.triggerPressed(triggerKey: ((try? self.environment.settingsStore.load().triggerKey) ?? .rightOption)))
        }
        self.signalReleasedTarget.replaceAction { [weak self] in
            self?.environment.runtimePreviewCoordinator.send(.triggerReleased)
        }
        self.signalASRTarget.replaceAction { [weak self] in
            self?.environment.runtimePreviewCoordinator.send(.asrRequestStarted)
        }
        self.signalCleanupTarget.replaceAction { [weak self] in
            self?.environment.runtimePreviewCoordinator.send(.cleanupRequestStarted)
        }
        self.signalInsertTarget.replaceAction { [weak self] in
            self?.environment.runtimePreviewCoordinator.send(.insertionStarted)
        }
        self.probeInsertionTarget.replaceAction { [weak self] in
            self?.environment.fixedTextInsertionProbe.run()
        }

        if let button = statusItem.button {
            button.title = "听写"
        }

        let settings = (try? environment.settingsStore.load()) ?? .default
        statusItem.menu = menuBuilder.buildMenu(
            settings: settings,
            settingsTarget: settingsActionTarget,
            debugItems: [
                MenuDebugItem(title: "隐藏到待命", actionTarget: debugIdleTarget),
                MenuDebugItem(title: "流程：正常路径", actionTarget: debugHappyPathTarget),
                MenuDebugItem(title: "流程：回退路径", actionTarget: debugFallbackTarget),
                MenuDebugItem(title: "状态：麦克风未授权", actionTarget: debugMicBlockedTarget),
                MenuDebugItem(title: "状态：辅助功能未授权", actionTarget: debugAXBlockedTarget),
                MenuDebugItem(title: "状态：键盘监听未授权", actionTarget: debugInputMonitoringBlockedTarget),
                MenuDebugItem(title: "状态：网络错误", actionTarget: debugNetworkErrorTarget),
                MenuDebugItem(title: "测试：写入当前光标", actionTarget: probeInsertionTarget),
                MenuDebugItem(title: "信号：按下触发键", actionTarget: signalPressedTarget),
                MenuDebugItem(title: "信号：松开触发键", actionTarget: signalReleasedTarget),
                MenuDebugItem(title: "信号：开始转写", actionTarget: signalASRTarget),
                MenuDebugItem(title: "信号：开始整理", actionTarget: signalCleanupTarget),
                MenuDebugItem(title: "信号：开始写入", actionTarget: signalInsertTarget)
            ]
        )

        environment.hudController.render(.idle)
    }

    func openSettings() {
        let controller = settingsWindowController ?? SettingsWindowController(
            rootView: SettingsView(
                viewModel: SettingsViewModel(
                    settingsStore: environment.settingsStore,
                    apiKeyStore: environment.apiKeyStore,
                    permissionService: environment.permissionService
                )
            )
        )
        settingsWindowController = controller
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        controller.window?.orderFrontRegardless()
    }
}
