import Foundation

protocol RealtimeASRSession: Sendable {
    func appendAudioChunk(_ chunk: AudioChunk) async throws
    func finish() async throws -> ASRTranscript
    func cancel() async
}

protocol RealtimeASRService {
    func startSession(languageCode: String?) async throws -> RealtimeASRSession
}
