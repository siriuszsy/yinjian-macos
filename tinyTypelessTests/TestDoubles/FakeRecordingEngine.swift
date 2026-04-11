import Foundation
@testable import tinyTypeless

struct FakeRecordingEngine: RecordingEngine {
    var levelObserver: RecordingLevelObserving?
    var chunkObserver: RecordingChunkObserving?
    var payload = AudioPayload(
        fileURL: URL(fileURLWithPath: "/tmp/fake.wav"),
        format: "wav",
        sampleRate: 16000,
        durationMs: 500
    )

    func prepare() async throws {}
    func startRecording() throws {}
    func stopRecording() async throws -> AudioPayload { payload }
}
