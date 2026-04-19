import AppKit
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: AppEnvironment?
    private var menuBarController: MenuBarController?
    private let bootstrap = AppBootstrap()
    private let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    private let logger = Logger(subsystem: BuildInfo.bundleIdentifier, category: "App")

    func applicationDidFinishLaunching(_ notification: Notification) {
        if isRunningTests {
            return
        }

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
                    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    self.logger.error("Failed to start orchestrator: \(message, privacy: .public)")
                    environment.hudController.render(.error(message: "启动失败：\(message)"))
                    self.menuBarController?.openSettings()
                }
            }
        } catch {
            logger.error("Failed to bootstrap app: \(error.localizedDescription, privacy: .public)")
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

        existingInstance.activate()
        NSApp.terminate(nil)
        return true
    }
}
