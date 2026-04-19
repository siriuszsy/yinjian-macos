import Foundation

final class RuntimeIndicatorStateMachine {
    private(set) var state: RuntimeIndicatorState = .idle

    @discardableResult
    func send(_ signal: RuntimeIndicatorSignal) -> RuntimeIndicatorState {
        let nextState: RuntimeIndicatorState

        switch signal {
        case .appReady:
            nextState = .idle
        case .triggerPressed(let triggerKey):
            nextState = .listening(intent: .dictation, triggerLabel: triggerKey.displayName)
        case .triggerReleased, .audioFinalizationStarted:
            nextState = .processing(stage: .finalizingCapture)
        case .asrRequestStarted:
            nextState = .processing(stage: .transcribingAudio)
        case .asrResponseReceived, .cleanupRequestStarted:
            nextState = .processing(stage: .cleaningTranscript)
        case .cleanupResponseReceived, .insertionStarted:
            nextState = .processing(stage: .insertingText)
        case .recordingSaved(let message):
            nextState = .success(message: message)
        case .insertionSucceeded:
            nextState = .success(message: "文字已写入当前输入框")
        case .fallbackPrepared(let message):
            nextState = .fallback(message: message)
        case .microphonePermissionDenied:
            nextState = .blocked(reason: .microphonePermission)
        case .accessibilityPermissionDenied:
            nextState = .blocked(reason: .accessibilityPermission)
        case .inputMonitoringDenied:
            nextState = .blocked(reason: .inputMonitoring)
        case .networkRequestFailed(let message), .unknownFailure(let message):
            nextState = .error(message: message)
        case .autoDismiss, .reset:
            nextState = .idle
        }

        state = nextState
        return nextState
    }
}
