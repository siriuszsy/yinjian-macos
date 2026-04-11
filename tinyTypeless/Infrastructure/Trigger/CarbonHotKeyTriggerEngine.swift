import Carbon
import Foundation

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
    weak var delegate: TriggerEngineDelegate?

    private var triggerKey: TriggerKey
    private var isRunning = false
    private var eventHandler: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private let hotKeySignature = OSType(0x54545950) // TTYP
    private let hotKeyIDValue: UInt32 = 1

    init(initialKey: TriggerKey) {
        triggerKey = initialKey
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
        triggerKey = key

        if isRunning {
            stopOnMainThread()
            try startOnMainThread()
        }
    }

    private func startOnMainThread() throws {
        guard !isRunning else {
            return
        }

        let combo = try hotKeyCombo(for: triggerKey)
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotKeyEventHandler,
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        guard installStatus == noErr else {
            throw CarbonHotKeyTriggerError.handlerInstallFailed(installStatus)
        }

        let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: hotKeyIDValue)
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

        isRunning = true
    }

    private func stopOnMainThread() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }

        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }

        hotKeyRef = nil
        eventHandler = nil
        isRunning = false
    }

    fileprivate func handle(eventRef: EventRef?) -> OSStatus {
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

        guard hotKeyID.signature == hotKeySignature, hotKeyID.id == hotKeyIDValue else {
            return noErr
        }

        let timestamp = Date().timeIntervalSince1970
        switch GetEventKind(eventRef) {
        case UInt32(kEventHotKeyPressed):
            delegate?.triggerDidPressDown(at: timestamp)
        case UInt32(kEventHotKeyReleased):
            delegate?.triggerDidRelease(at: timestamp)
        default:
            break
        }

        return noErr
    }

    private func hotKeyCombo(for triggerKey: TriggerKey) throws -> (keyCode: UInt32, modifiers: UInt32) {
        switch triggerKey {
        case .commandSemicolon:
            return (keyCode: 41, modifiers: UInt32(cmdKey))
        case .rightOption, .fn:
            throw CarbonHotKeyTriggerError.unsupportedTriggerKey
        }
    }
}

private let carbonHotKeyEventHandler: EventHandlerUPP = { _, eventRef, userData in
    guard let userData else {
        return noErr
    }

    let engine = Unmanaged<CarbonHotKeyTriggerEngine>
        .fromOpaque(userData)
        .takeUnretainedValue()

    return engine.handle(eventRef: eventRef)
}
