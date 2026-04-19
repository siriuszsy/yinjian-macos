import Foundation

enum DictationError: Error, LocalizedError, Sendable {
    case invalidState
    case triggerUnavailable
    case microphonePermissionDenied
    case accessibilityPermissionDenied
    case recordingFailed(String)
    case asrFailed(String)
    case translationFailed(String)
    case cleanupFailed(String)
    case insertionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidState:
            return "当前状态不允许执行这个操作。"
        case .triggerUnavailable:
            return "触发键监听当前不可用。"
        case .microphonePermissionDenied:
            return "需要先授予麦克风权限。"
        case .accessibilityPermissionDenied:
            return "需要先授予辅助功能权限。"
        case .recordingFailed(let message):
            return "录音失败：\(message)"
        case .asrFailed(let message):
            return "语音转文字失败：\(message)"
        case .translationFailed(let message):
            return "翻译失败：\(message)"
        case .cleanupFailed(let message):
            return "文本整理失败：\(message)"
        case .insertionFailed(let message):
            return "写入失败：\(message)"
        }
    }
}
