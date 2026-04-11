import Foundation

struct DictationSessionContext: Sendable {
    let id: UUID
    let startedAt: Date
    var triggerReleasedAt: Date?
    var focusedContext: FocusedContext?
    var audioPayload: AudioPayload?
    var rawTranscript: ASRTranscript?
    var cleanText: CleanText?

    init(id: UUID = UUID(), startedAt: Date) {
        self.id = id
        self.startedAt = startedAt
    }
}
