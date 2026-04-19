import Foundation

struct LatencyMetrics: Codable, Sendable {
    var recordingDurationMs: Int
    var asrDurationMs: Int
    var cleanupDurationMs: Int
    var insertionDurationMs: Int
    var totalAfterReleaseMs: Int

    static let zero = LatencyMetrics(
        recordingDurationMs: 0,
        asrDurationMs: 0,
        cleanupDurationMs: 0,
        insertionDurationMs: 0,
        totalAfterReleaseMs: 0
    )
}
