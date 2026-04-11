import Foundation

enum Constants {
    enum App {
        static let displayName = "tinyTypeless"
    }

    enum Metrics {
        static let targetInsertLatencyMs = 1200
        static let targetRecordingFeedbackMs = 100
    }

    enum Paths {
        static let settingsFileName = "settings.json"
        static let sessionsLogFileName = "sessions.jsonl"
    }
}
