import Foundation

struct DictationSessionContext: Sendable {
    let id: UUID
    let startedAt: Date
    let intent: SessionIntent
    var triggerReleasedAt: Date?
    var focusedContext: FocusedContext?
    var audioPayload: AudioPayload?
    var rawTranscript: ASRTranscript?
    var translatedText: String?
    var cleanText: CleanText?

    init(id: UUID = UUID(), startedAt: Date, intent: SessionIntent) {
        self.id = id
        self.startedAt = startedAt
        self.intent = intent
    }
}
