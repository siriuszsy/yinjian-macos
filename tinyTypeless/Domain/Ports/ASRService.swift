import Foundation

protocol ASRService {
    func transcribe(_ payload: AudioPayload) async throws -> ASRTranscript
}
