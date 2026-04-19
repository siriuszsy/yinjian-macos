import Foundation

struct AliyunASRRequest: Encodable {
    let model: String
    let messages: [Message]
    let stream: Bool
    let asrOptions: ASROptions

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case stream
        case asrOptions = "asr_options"
    }

    init(audioDataURI: String) {
        self.model = "qwen3-asr-flash"
        self.messages = [
            Message(
                role: "user",
                content: [
                    Content(
                        type: "input_audio",
                        inputAudio: InputAudio(data: audioDataURI)
                    )
                ]
            )
        ]
        self.stream = false
        self.asrOptions = ASROptions(enableITN: false)
    }

    struct Message: Encodable {
        let role: String
        let content: [Content]
    }

    struct Content: Encodable {
        let type: String
        let inputAudio: InputAudio

        enum CodingKeys: String, CodingKey {
            case type
            case inputAudio = "input_audio"
        }
    }

    struct InputAudio: Encodable {
        let data: String
    }

    struct ASROptions: Encodable {
        let enableITN: Bool

        enum CodingKeys: String, CodingKey {
            case enableITN = "enable_itn"
        }
    }
}
