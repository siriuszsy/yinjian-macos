import Foundation

struct AliyunCleanupResponse: Decodable {
    struct APIErrorPayload: Decodable {
        let message: String?
        let code: String?
    }

    struct Choice: Decodable {
        struct Message: Decodable {
            let content: ContentValue?

            var contentText: String? {
                content?.textValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        let message: Message?
    }

    let choices: [Choice]?
    let error: APIErrorPayload?

    var cleanedText: String? {
        choices?.first?.message?.contentText
    }
}

extension AliyunCleanupResponse {
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
}
