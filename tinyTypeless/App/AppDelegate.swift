import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: AppEnvironment?
    private var menuBarController: MenuBarController?
    private let bootstrap = AppBootstrap()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if terminateIfDuplicateInstance() {
            return
        }

        do {
            let environment = try bootstrap.buildEnvironment()
            self.environment = environment
            self.menuBarController = MenuBarController(environment: environment)
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                do {
                    try await environment.orchestrator.start()
                    self.menuBarController?.openSettings()
                } catch {
                    environment.hudController.render(.idle)
                    self.menuBarController?.openSettings()
                }
            }
        } catch {
            assertionFailure("Failed to bootstrap app: \(error)")
        }
    }

    private func terminateIfDuplicateInstance() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return false
        }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let otherInstances = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0.processIdentifier != currentPID && !$0.isTerminated }

        guard let existingInstance = otherInstances.first else {
            return false
        }

        existingInstance.activate(options: [.activateIgnoringOtherApps])
        NSApp.terminate(nil)
        return true
    }
}
