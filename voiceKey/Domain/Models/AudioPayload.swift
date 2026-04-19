import Foundation

struct AudioPayload: Sendable {
    let fileURL: URL
    let format: String
    let sampleRate: Int
    let durationMs: Int
}
