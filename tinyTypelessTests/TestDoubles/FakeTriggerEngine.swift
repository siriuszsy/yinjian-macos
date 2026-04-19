import Foundation
@testable import tinyTypeless

final class FakeTriggerEngine: TriggerEngine {
    weak var delegate: TriggerEngineDelegate?

    func start() throws {}
    func stop() {}
    func updateTriggerKey(_ key: TriggerKey) throws {}

    func triggerDown(intent: SessionIntent, at timestamp: TimeInterval) {
        delegate?.triggerDidPressDown(for: intent, at: timestamp)
    }

    func triggerUp(intent: SessionIntent, at timestamp: TimeInterval) {
        delegate?.triggerDidRelease(for: intent, at: timestamp)
    }
}
