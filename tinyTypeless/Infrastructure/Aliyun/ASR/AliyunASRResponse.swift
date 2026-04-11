import Foundation

struct AliyunASRResponse: Decodable {
    let choices: [Choice]?
    let error: APIErrorPayload?

    var transcriptText: String? {
        choices?
            .first?
            .message?
            .contentText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    struct Choice: Decodable {
        let message: Message?
    }

    struct Message: Decodable {
        let content: ContentValue?

        var contentText: String? {
            content?.textValue
        }
    }

    enum ContentValue: Decodable {
        case string(String)
        case parts([ContentPart])

        var textValue: String? {
            switch self {
            case .string(let value):
                return value
            case .parts(let parts):
                return parts
                    .compactMap(\.text)
                    .joined(separator: "")
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let stringValue = try? container.decode(String.self) {
                self = .string(stringValue)
                return
            }

            self = .parts(try container.decode([ContentPart].self))
        }
    }

    struct ContentPart: Decodable {
        let text: String?
    }

    struct APIErrorPayload: Decodable {
        let message: String?
        let code: String?
    }
}
