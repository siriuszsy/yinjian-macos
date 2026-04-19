import Foundation

enum DictationState: Sendable {
    case idle
    case recording(startedAt: Date)
    case stopping
    case asrProcessing
    case translationProcessing
    case cleanupProcessing
    case inserting
    case failed(message: String)
}
