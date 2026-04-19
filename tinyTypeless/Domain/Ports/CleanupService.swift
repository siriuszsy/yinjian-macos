import Foundation

protocol CleanupService {
    func cleanup(
        transcript: ASRTranscript,
        context: CleanupContext
    ) async throws -> CleanText
}

struct TranslationOptions: Sendable {
    let sourceLanguage: String
    let targetLanguage: String
}

protocol TranslationService: Sendable {
    func translate(_ text: String, options: TranslationOptions) async throws -> String
}
