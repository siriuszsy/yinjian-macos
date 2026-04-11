import Foundation

final class HybridTriggerEngine: TriggerEngine, @unchecked Sendable {
    weak var delegate: TriggerEngineDelegate? {
        didSet {
            carbonEngine.delegate = delegate
            cgEventTapEngine.delegate = delegate
        }
    }

    private var triggerKey: TriggerKey
    private var isRunning = false
    private let carbonEngine: CarbonHotKeyTriggerEngine
    private let cgEventTapEngine: CGEventTapTriggerEngine

    init(initialKey: TriggerKey) {
        self.triggerKey = initialKey
        self.carbonEngine = CarbonHotKeyTriggerEngine(initialKey: initialKey)
        self.cgEventTapEngine = CGEventTapTriggerEngine(initialKey: initialKey)
    }

    func start() throws {
        try activeEngine.start()
        isRunning = true
    }

    func stop() {
        activeEngine.stop()
        isRunning = false
    }

    func updateTriggerKey(_ key: TriggerKey) throws {
        let wasRunning = isRunning
        if wasRunning {
            activeEngine.stop()
        }

        triggerKey = key
        try carbonEngine.updateTriggerKey(key)
        try cgEventTapEngine.updateTriggerKey(key)

        if wasRunning {
            try activeEngine.start()
        }
    }

    private var activeEngine: TriggerEngine {
        switch triggerKey {
        case .commandSemicolon:
            return carbonEngine
        case .rightOption, .fn:
            return cgEventTapEngine
        }
    }
}
