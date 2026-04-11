import Foundation
@testable import tinyTypeless

struct FakeASRService: ASRService {
    var transcript = ASRTranscript(rawText: "test transcript", languageCode: "zh-CN")

    func transcribe(_ payload: AudioPayload) async throws -> ASRTranscript {
        _ = payload
        return transcript
    }
}
