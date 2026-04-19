import AppKit

@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let environment: AppEnvironment
    private let menuBuilder = MenuContentBuilder()
    private let settingsActionTarget: ClosureMenuAction
    private let insertionProbeActionTarget: ClosureMenuAction
    private var settingsWindowController: SettingsWindowController?

    init(environment: AppEnvironment) {
        self.environment = environment
        self.settingsActionTarget = ClosureMenuAction(targetAction: {})
        self.insertionProbeActionTarget = ClosureMenuAction(targetAction: {})
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.settingsActionTarget.replaceAction { [weak self] in
            self?.openSettings()
        }
        self.insertionProbeActionTarget.replaceAction { [weak self] in
            self?.environment.fixedTextInsertionProbe.run()
        }

        if let button = statusItem.button {
            button.title = BuildInfo.displayName
        }

        let settings = (try? environment.settingsStore.load()) ?? .default
        statusItem.menu = menuBuilder.buildMenu(
            settings: settings,
            settingsTarget: settingsActionTarget,
            insertionProbeTarget: insertionProbeActionTarget
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
