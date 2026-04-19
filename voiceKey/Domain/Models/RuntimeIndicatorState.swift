import Foundation

enum RuntimeIndicatorCallStage: String, Codable, Sendable {
    case finalizingCapture
    case transcribingAudio
    case translatingText
    case cleaningTranscript
    case insertingText

    var title: String {
        "思考中"
    }

    var subtitle: String {
        switch self {
        case .finalizingCapture:
            return "正在收尾本次录音"
        case .transcribingAudio:
            return "正在把语音转成文字"
        case .translatingText:
            return "正在翻译文本"
        case .cleaningTranscript:
            return "正在整理转写结果"
        case .insertingText:
            return "正在写入当前输入框"
        }
    }

    var pill: String {
        switch self {
        case .finalizingCapture:
            return "收尾"
        case .transcribingAudio:
            return "转写"
        case .translatingText:
            return "翻译"
        case .cleaningTranscript:
            return "整理"
        case .insertingText:
            return "写入"
        }
    }
}

enum RuntimeIndicatorBlockedReason: String, Codable, Sendable {
    case microphonePermission
    case accessibilityPermission
    case inputMonitoring

    var title: String {
        switch self {
        case .microphonePermission:
            return "麦克风未授权"
        case .accessibilityPermission:
            return "辅助功能未授权"
        case .inputMonitoring:
            return "键盘监听未授权"
        }
    }

    var subtitle: String {
        switch self {
        case .microphonePermission:
            return "请在系统设置中允许麦克风访问"
        case .accessibilityPermission:
            return "请在系统设置中允许辅助功能访问"
        case .inputMonitoring:
            return "请允许键盘监听，这样才能捕获右侧 ⌥ 键"
        }
    }
}

enum RuntimeIndicatorState: Equatable, Sendable {
    case idle
    case listening(intent: SessionIntent, triggerLabel: String)
    case processing(stage: RuntimeIndicatorCallStage)
    case success(message: String)
    case fallback(message: String)
    case blocked(reason: RuntimeIndicatorBlockedReason)
    case error(message: String)

    var presentsOrb: Bool {
        switch self {
        case .idle:
            return false
        case .listening, .processing, .success, .fallback, .blocked, .error:
            return true
        }
    }
}

enum RuntimeIndicatorSignal: Equatable, Sendable {
    case appReady(triggerKey: TriggerKey)
    case triggerPressed(triggerKey: TriggerKey)
    case triggerReleased
    case audioFinalizationStarted
    case asrRequestStarted
    case asrResponseReceived
    case cleanupRequestStarted
    case cleanupResponseReceived
    case insertionStarted
    case insertionSucceeded
    case recordingSaved(message: String)
    case fallbackPrepared(message: String)
    case microphonePermissionDenied
    case accessibilityPermissionDenied
    case inputMonitoringDenied
    case networkRequestFailed(message: String)
    case unknownFailure(message: String)
    case autoDismiss
    case reset
}
