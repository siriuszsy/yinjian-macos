import Foundation

final class DictationMetricsTracker {
    private var recordingStartedAt: Date?
    private var recordingStoppedAt: Date?
    private var asrStartedAt: Date?
    private var asrFinishedAt: Date?
    private var cleanupStartedAt: Date?
    private var cleanupFinishedAt: Date?
    private var insertionStartedAt: Date?
    private var insertionFinishedAt: Date?
    private var triggerReleasedAt: Date?

    func markTriggerReleased(at date: Date) {
        triggerReleasedAt = date
    }

    func markRecordingStarted(at date: Date) {
        recordingStartedAt = date
    }

    func markRecordingStopped(at date: Date) {
        recordingStoppedAt = date
    }

    func markASRStarted(at date: Date) {
        asrStartedAt = date
    }

    func markASRFinished(at date: Date) {
        asrFinishedAt = date
    }

    func markCleanupStarted(at date: Date) {
        cleanupStartedAt = date
    }

    func markCleanupFinished(at date: Date) {
        cleanupFinishedAt = date
    }

    func markInsertionStarted(at date: Date) {
        insertionStartedAt = date
    }

    func markInsertionFinished(at date: Date) {
        insertionFinishedAt = date
    }

    func build() -> LatencyMetrics {
        LatencyMetrics(
            recordingDurationMs: durationMs(from: recordingStartedAt, to: recordingStoppedAt),
            asrDurationMs: durationMs(from: asrStartedAt, to: asrFinishedAt),
            cleanupDurationMs: durationMs(from: cleanupStartedAt, to: cleanupFinishedAt),
            insertionDurationMs: durationMs(from: insertionStartedAt, to: insertionFinishedAt),
            totalAfterReleaseMs: durationMs(from: triggerReleasedAt, to: insertionFinishedAt)
        )
    }

    private func durationMs(from start: Date?, to end: Date?) -> Int {
        guard let start, let end else {
            return 0
        }

        return max(Int(end.timeIntervalSince(start) * 1000), 0)
    }
}
