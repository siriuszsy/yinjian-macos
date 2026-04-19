import Carbon
import CoreGraphics
import Foundation
import OSLog

enum CGEventTapTriggerError: LocalizedError {
    case inputMonitoringNotTrusted
    case tapCreationFailed

    var errorDescription: String? {
        switch self {
        case .inputMonitoringNotTrusted:
            return "Input Monitoring permission is required to monitor the trigger key."
        case .tapCreationFailed:
            return "Failed to create CGEvent tap for trigger key listening."
        }
    }
}

final class CGEventTapTriggerEngine: TriggerEngine, @unchecked Sendable {
    private enum Registration {
        case triggerKey(TriggerKey)
        case fixedHotKey(FixedHotKeyShortcut)
    }

    weak var delegate: TriggerEngineDelegate?

    private let logger = Logger(subsystem: BuildInfo.bundleIdentifier, category: "Trigger")
    private var registration: Registration
    private let intent: SessionIntent
    private var isRunning = false
    private var isTriggerPressed = false
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(initialKey: TriggerKey, intent: SessionIntent = .dictation) {
        registration = .triggerKey(initialKey)
        self.intent = intent
    }

    init(fixedHotKey: FixedHotKeyShortcut, intent: SessionIntent) {
        registration = .fixedHotKey(fixedHotKey)
        self.intent = intent
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
        isTriggerPressed = false
    }

    private func startOnMainThread() throws {
        guard !isRunning else {
            return
        }

        guard CGPreflightListenEventAccess() || CGRequestListenEventAccess() else {
            throw CGEventTapTriggerError.inputMonitoringNotTrusted
        }

        let eventMask = eventMaskForCurrentRegistration()
        guard let eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: cgEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw CGEventTapTriggerError.tapCreationFailed
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        self.eventTap = eventTap
        self.runLoopSource = runLoopSource
        self.isRunning = true
    }

    private func stopOnMainThread() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }

        runLoopSource = nil
        eventTap = nil
        isTriggerPressed = false
        isRunning = false
    }

    fileprivate func handleEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        _ = proxy

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        switch registration {
        case .triggerKey(let triggerKey):
            guard type == .flagsChanged else {
                return Unmanaged.passUnretained(event)
            }
            return handleModifierTriggerEvent(event: event, triggerKey: triggerKey)
        case .fixedHotKey:
            guard type == .flagsChanged || type == .keyDown || type == .keyUp else {
                return Unmanaged.passUnretained(event)
            }
            return handleFixedHotKeyEvent(type: type, event: event)
        }
    }

    private func handleModifierTriggerEvent(
        event: CGEvent,
        triggerKey: TriggerKey
    ) -> Unmanaged<CGEvent>? {
        let keyCodeValue = event.getIntegerValueField(.keyboardEventKeycode)
        let keyCode = CGKeyCode(keyCodeValue)

        guard TriggerKeyMapper.matches(keyCode: keyCode, triggerKey: triggerKey) else {
            return Unmanaged.passUnretained(event)
        }

        let timestamp = Date().timeIntervalSince1970
        let delegate = self.delegate
        let pressed = isPressed(event: event, triggerKey: triggerKey)

        guard pressed != isTriggerPressed else {
            return Unmanaged.passUnretained(event)
        }

        if pressed {
            isTriggerPressed = true
            DispatchQueue.main.async {
                delegate?.triggerDidPressDown(for: self.intent, at: timestamp)
            }
        } else {
            isTriggerPressed = false
            DispatchQueue.main.async {
                delegate?.triggerDidRelease(for: self.intent, at: timestamp)
            }
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleFixedHotKeyEvent(
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        guard case .fixedHotKey(let hotKey) = registration else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        let modifiers = normalizedModifiers(event.flags)
        logInterestingFixedHotKeyEvent(type: type, keyCode: keyCode, modifiers: modifiers)

        switch type {
        case .keyDown:
            guard keyCode == hotKey.keyCode, modifiers == hotKey.modifiers, !isTriggerPressed else {
                return Unmanaged.passUnretained(event)
            }

            isTriggerPressed = true
            let timestamp = Date().timeIntervalSince1970
            let delegate = self.delegate
            logger.notice("Event tap matched key down: \(hotKey.displayName, privacy: .public), intent: \(self.intent.rawValue, privacy: .public)")
            DispatchQueue.main.async {
                delegate?.triggerDidPressDown(for: self.intent, at: timestamp)
            }

        case .keyUp:
            guard keyCode == hotKey.keyCode, isTriggerPressed else {
                return Unmanaged.passUnretained(event)
            }

            isTriggerPressed = false
            let timestamp = Date().timeIntervalSince1970
            let delegate = self.delegate
            logger.notice("Event tap matched key up: \(hotKey.displayName, privacy: .public), intent: \(self.intent.rawValue, privacy: .public)")
            DispatchQueue.main.async {
                delegate?.triggerDidRelease(for: self.intent, at: timestamp)
            }

        case .flagsChanged:
            guard isTriggerPressed, modifiers != hotKey.modifiers else {
                return Unmanaged.passUnretained(event)
            }

            isTriggerPressed = false
            let timestamp = Date().timeIntervalSince1970
            let delegate = self.delegate
            logger.notice("Event tap released by modifier change: \(hotKey.displayName, privacy: .public), intent: \(self.intent.rawValue, privacy: .public), modifiers: 0x\(String(modifiers, radix: 16), privacy: .public)")
            DispatchQueue.main.async {
                delegate?.triggerDidRelease(for: self.intent, at: timestamp)
            }

        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }

    private func isPressed(event: CGEvent, triggerKey: TriggerKey) -> Bool {
        switch triggerKey {
        case .commandSemicolon:
            return false
        case .rightOption:
            return event.flags.contains(.maskAlternate)
        case .fn:
            return event.flags.contains(.maskSecondaryFn)
        }
    }

    private func eventMaskForCurrentRegistration() -> CGEventMask {
        switch registration {
        case .triggerKey:
            return CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        case .fixedHotKey:
            return
                CGEventMask(1 << CGEventType.flagsChanged.rawValue) |
                CGEventMask(1 << CGEventType.keyDown.rawValue) |
                CGEventMask(1 << CGEventType.keyUp.rawValue)
        }
    }

    private func normalizedModifiers(_ flags: CGEventFlags) -> UInt32 {
        var value: UInt32 = 0
        if flags.contains(.maskCommand) {
            value |= UInt32(cmdKey)
        }
        if flags.contains(.maskShift) {
            value |= UInt32(shiftKey)
        }
        if flags.contains(.maskAlternate) {
            value |= UInt32(optionKey)
        }
        if flags.contains(.maskControl) {
            value |= UInt32(controlKey)
        }
        return value
    }

    private func logInterestingFixedHotKeyEvent(
        type: CGEventType,
        keyCode: UInt32,
        modifiers: UInt32
    ) {
        let interestingKeyCodes: Set<UInt32> = [37, 39, 41]
        let hasPrimaryModifier = modifiers & UInt32(cmdKey | controlKey) != 0

        guard interestingKeyCodes.contains(keyCode) || hasPrimaryModifier else {
            return
        }

        logger.notice("Event tap raw event: type=\(type.rawValue), keyCode=\(keyCode), modifiers=0x\(String(modifiers, radix: 16), privacy: .public)")
    }
}

private let cgEventTapCallback: CGEventTapCallBack = { proxy, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let engine = Unmanaged<CGEventTapTriggerEngine>
        .fromOpaque(userInfo)
        .takeUnretainedValue()

    return engine.handleEvent(proxy: proxy, type: type, event: event)
}
