import Foundation

struct SessionRecord: Codable, Sendable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let focusedApp: String
    let audioFilePath: String?
    let rawTranscript: String?
    let cleanText: String?
    let inserted: Bool
    let fallbackUsed: Bool
    let failureReason: String?
    let latency: LatencyMetrics
}
