import Foundation

struct InsertionResult: Sendable {
    let success: Bool
    let usedFallback: Bool
    let failureReason: String?
}
