import CoreGraphics
import Foundation

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
    weak var delegate: TriggerEngineDelegate?

    private var triggerKey: TriggerKey
    private var isRunning = false
    private var isTriggerPressed = false
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

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
        isTriggerPressed = false
    }

    private func startOnMainThread() throws {
        guard !isRunning else {
            return
        }

        guard CGPreflightListenEventAccess() else {
            throw CGEventTapTriggerError.inputMonitoringNotTrusted
        }

        let eventMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
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

        guard type == .flagsChanged else {
            return Unmanaged.passUnretained(event)
        }

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
                delegate?.triggerDidPressDown(at: timestamp)
            }
        } else {
            isTriggerPressed = false
            DispatchQueue.main.async {
                delegate?.triggerDidRelease(at: timestamp)
            }
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
