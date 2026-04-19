import Foundation

final class IOHIDTriggerEngine: TriggerEngine {
    weak var delegate: TriggerEngineDelegate?

    private var triggerKey: TriggerKey

    init(initialKey: TriggerKey) {
        triggerKey = initialKey
    }

    func start() throws {
        // TODO: Install IOHID callbacks if CGEventTap proves unstable.
    }

    func stop() {
        // TODO: Tear down IOHID callbacks.
    }

    func updateTriggerKey(_ key: TriggerKey) throws {
        triggerKey = key
    }
}
