import Foundation

struct AudioChunk: Sendable {
    let data: Data
    let sampleRate: Int
    let channelCount: Int
}
