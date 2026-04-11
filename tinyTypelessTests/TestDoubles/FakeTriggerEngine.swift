import Foundation
@testable import tinyTypeless

final class FakeTriggerEngine: TriggerEngine {
    weak var delegate: TriggerEngineDelegate?

    func start() throws {}
    func stop() {}
    func updateTriggerKey(_ key: TriggerKey) throws {}
}
