import Carbon
import Foundation
import OSLog

enum CarbonHotKeyTriggerError: LocalizedError {
    case unsupportedTriggerKey
    case handlerInstallFailed(OSStatus)
    case registrationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unsupportedTriggerKey:
            return "The requested trigger key is not supported by the Carbon hotkey engine."
        case .handlerInstallFailed(let status):
            return "Failed to install Carbon hotkey handler. OSStatus: \(status)"
        case .registrationFailed(let status):
            return "Failed to register Carbon hotkey. OSStatus: \(status)"
        }
    }
}

final class CarbonHotKeyTriggerEngine: TriggerEngine, @unchecked Sendable {
    private final class WeakEngineBox {
        weak var engine: CarbonHotKeyTriggerEngine?

        init(_ engine: CarbonHotKeyTriggerEngine) {
            self.engine = engine
        }
    }

    private enum Registration {
        case triggerKey(TriggerKey)
        case fixedHotKey(FixedHotKeyShortcut)
    }

    private static let hotKeySignature = OSType(0x54545950) // TTYP
    nonisolated(unsafe) private static var sharedEventHandler: EventHandlerRef?
    nonisolated(unsafe) private static var registeredEngines: [UInt32: WeakEngineBox] = [:]

    weak var delegate: TriggerEngineDelegate?

    private let logger = Logger(subsystem: BuildInfo.bundleIdentifier, category: "Trigger")
    private var registration: Registration
    private let intent: SessionIntent
    private var isRunning = false
    private var hotKeyRef: EventHotKeyRef?
    private let hotKeyIDValue: UInt32

    init(initialKey: TriggerKey, intent: SessionIntent = .dictation, hotKeyIDValue: UInt32 = 1) {
        self.registration = .triggerKey(initialKey)
        self.intent = intent
        self.hotKeyIDValue = hotKeyIDValue
    }

    init(fixedHotKey: FixedHotKeyShortcut, intent: SessionIntent, hotKeyIDValue: UInt32) {
        self.registration = .fixedHotKey(fixedHotKey)
        self.intent = intent
        self.hotKeyIDValue = hotKeyIDValue
    }

    func start() throws {
        if Thread.isMainThread {
            try startOnMainThread()
            return
        }

        var caughtError: Error?
        DispatchQueue.main.sync {
            do {
                try self.startOnMainThread()
            } catch {
                caughtError = error
            }
        }

        if let caughtError {
            throw caughtError
        }
    }

    func stop() {
        DispatchQueue.main.async {
            self.stopOnMainThread()
        }
    }

    func updateTriggerKey(_ key: TriggerKey) throws {
        guard case .triggerKey = registration else {
            return
        }

        registration = .triggerKey(key)

        if isRunning {
            stopOnMainThread()
            try startOnMainThread()
        }
    }

    private func startOnMainThread() throws {
        guard !isRunning else {
            return
        }

        try Self.installSharedEventHandlerIfNeeded()

        let combo = try hotKeyCombo()
        let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: hotKeyIDValue)
        let registrationStatus = RegisterEventHotKey(
            combo.keyCode,
            combo.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard registrationStatus == noErr else {
            stopOnMainThread()
            throw CarbonHotKeyTriggerError.registrationFailed(registrationStatus)
        }

        Self.registeredEngines[hotKeyIDValue] = WeakEngineBox(self)
        isRunning = true
    }

    private func stopOnMainThread() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }

        Self.registeredEngines.removeValue(forKey: hotKeyIDValue)
        Self.pruneRegisteredEngines()
        Self.removeSharedEventHandlerIfPossible()
        hotKeyRef = nil
        isRunning = false
    }

    private func handleMatchedEvent(eventRef: EventRef?) -> OSStatus {
        guard let eventRef else {
            return noErr
        }

        let timestamp = Date().timeIntervalSince1970
        switch GetEventKind(eventRef) {
        case UInt32(kEventHotKeyPressed):
            logger.notice("Hotkey pressed: \(self.registrationDisplayName, privacy: .public), intent: \(self.intent.rawValue, privacy: .public), id: \(self.hotKeyIDValue)")
            delegate?.triggerDidPressDown(for: intent, at: timestamp)
        case UInt32(kEventHotKeyReleased):
            logger.notice("Hotkey released: \(self.registrationDisplayName, privacy: .public), intent: \(self.intent.rawValue, privacy: .public), id: \(self.hotKeyIDValue)")
            delegate?.triggerDidRelease(for: intent, at: timestamp)
        default:
            break
        }

        return noErr
    }

    private func hotKeyCombo() throws -> (keyCode: UInt32, modifiers: UInt32) {
        switch registration {
        case .triggerKey(let triggerKey):
            switch triggerKey {
            case .commandSemicolon:
                return (keyCode: 41, modifiers: UInt32(cmdKey))
            case .rightOption, .fn:
                throw CarbonHotKeyTriggerError.unsupportedTriggerKey
            }
        case .fixedHotKey(let hotKey):
            return (keyCode: hotKey.keyCode, modifiers: hotKey.modifiers)
        }
    }

    private var registrationDisplayName: String {
        switch registration {
        case .triggerKey(let triggerKey):
            return triggerKey.displayName
        case .fixedHotKey(let hotKey):
            return hotKey.displayName
        }
    }

    private static func installSharedEventHandlerIfNeeded() throws {
        guard sharedEventHandler == nil else {
            return
        }

        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotKeyEventHandler,
            eventTypes.count,
            &eventTypes,
            nil,
            &sharedEventHandler
        )

        guard installStatus == noErr else {
            throw CarbonHotKeyTriggerError.handlerInstallFailed(installStatus)
        }
    }

    private static func removeSharedEventHandlerIfPossible() {
        guard registeredEngines.isEmpty, let sharedEventHandler else {
            return
        }

        RemoveEventHandler(sharedEventHandler)
        self.sharedEventHandler = nil
    }

    private static func pruneRegisteredEngines() {
        registeredEngines = registeredEngines.filter { _, box in
            box.engine != nil
        }
    }

    fileprivate static func handleShared(eventRef: EventRef?) -> OSStatus {
        guard let eventRef else {
            return noErr
        }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            eventRef,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr else {
            return status
        }

        guard hotKeyID.signature == hotKeySignature else {
            return noErr
        }

        pruneRegisteredEngines()

        guard let engine = registeredEngines[hotKeyID.id]?.engine else {
            return noErr
        }

        return engine.handleMatchedEvent(eventRef: eventRef)
    }
}

private let carbonHotKeyEventHandler: EventHandlerUPP = { _, eventRef, _ in
    CarbonHotKeyTriggerEngine.handleShared(eventRef: eventRef)
}
