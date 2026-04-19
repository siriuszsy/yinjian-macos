import Foundation
@testable import voiceKey

struct FakeCleanupService: CleanupService {
    var result = CleanText(value: "clean text")

    func cleanup(
        transcript: ASRTranscript,
        context: CleanupContext
    ) async throws -> CleanText {
        _ = transcript
        _ = context
        return result
    }
}
