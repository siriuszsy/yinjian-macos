import Foundation

protocol ASRService: Sendable {
    func transcribe(_ payload: AudioPayload) async throws -> ASRTranscript
}

protocol LiveStreamingASRService: Sendable {
    func beginLiveTranscription(languageCode: String?) async throws -> Bool
    func appendLiveAudioChunk(_ chunk: AudioChunk) async throws
    func finishLiveTranscription() async throws -> ASRTranscript?
    func cancelLiveTranscription() async
}
