import Foundation

final class AliyunCleanupService: CleanupService {
    private let httpClient: HTTPClient
    private let apiKeyStore: APIKeyStore
    private let promptBuilder: CleanupPromptBuilder

    init(
        httpClient: HTTPClient,
        apiKeyStore: APIKeyStore,
        promptBuilder: CleanupPromptBuilder
    ) {
        self.httpClient = httpClient
        self.apiKeyStore = apiKeyStore
        self.promptBuilder = promptBuilder
    }

    func cleanup(
        transcript: ASRTranscript,
        context: CleanupContext
    ) async throws -> CleanText {
        let apiKey = try loadAPIKey()
        let profile = await classifyPromptProfile(
            transcript: transcript,
            context: context,
            apiKey: apiKey
        )
        let requestBody = try JSONEncoder().encode(
            CleanupRequest(
                systemPrompt: promptBuilder.systemPrompt(for: context, profile: profile),
                userPrompt: promptBuilder.userPrompt(for: transcript, context: context, profile: profile)
            )
        )
        let request = try AliyunRequestFactory.makeCleanupRequest(apiKey: apiKey, body: requestBody)
        let (data, response) = try await httpClient.perform(request)

        guard (200..<300).contains(response.statusCode) else {
            throw DictationError.cleanupFailed(errorMessage(from: data, statusCode: response.statusCode))
        }

        let decoded = try JSONDecoder().decode(AliyunCleanupResponse.self, from: data)
        if let apiError = decoded.error?.message, !apiError.isEmpty {
            throw DictationError.cleanupFailed(apiError)
        }

        guard let cleanedText = decoded.cleanedText, !cleanedText.isEmpty else {
            throw DictationError.cleanupFailed("整理模型返回了空结果。")
        }

        return CleanText(value: cleanedText)
    }

    private func classifyPromptProfile(
        transcript: ASRTranscript,
        context: CleanupContext,
        apiKey: String
    ) async -> CleanupPromptProfile {
        if let heuristicProfile = obviousProfile(for: transcript.rawText) {
            return heuristicProfile
        }

        do {
            let requestBody = try JSONEncoder().encode(
                ClassificationRequest(
                    systemPrompt: promptBuilder.classifierSystemPrompt(for: context),
                    userPrompt: promptBuilder.classifierUserPrompt(for: transcript)
                )
            )
            let request = try AliyunRequestFactory.makeCleanupRequest(apiKey: apiKey, body: requestBody)
            let (data, response) = try await httpClient.perform(request)

            guard (200..<300).contains(response.statusCode) else {
                return .plain
            }

            let decoded = try JSONDecoder().decode(AliyunCleanupResponse.self, from: data)
            return CleanupPromptProfile.fromClassifierOutput(decoded.cleanedText)
        } catch {
            return .plain
        }
    }

    private func obviousProfile(for rawText: String) -> CleanupPromptProfile? {
        let markers = [
            "第一点", "第二点", "第三点",
            "第一，", "第二，", "第三，",
            "第一,", "第二,", "第三,",
            "第一：", "第二：", "第三：",
            "首先", "其次", "最后"
        ]

        let hits = markers.reduce(into: 0) { count, marker in
            if rawText.contains(marker) {
                count += 1
            }
        }

        return hits >= 2 ? .listLike : nil
    }

    private func loadAPIKey() throws -> String {
        if let envValue = ProcessInfo.processInfo.environment["DASHSCOPE_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !envValue.isEmpty {
            return envValue
        }

        do {
            let storedValue = try apiKeyStore.load().trimmingCharacters(in: .whitespacesAndNewlines)
            if !storedValue.isEmpty {
                return storedValue
            }
        } catch {
            // Fall through to a user-facing error below.
        }

        throw DictationError.cleanupFailed("请先在设置里配置百炼 API Key。")
    }

    private func errorMessage(from data: Data, statusCode: Int) -> String {
        if let decoded = try? JSONDecoder().decode(AliyunCleanupResponse.self, from: data),
           let message = decoded.error?.message,
           !message.isEmpty {
            return message
        }

        switch statusCode {
        case 400:
            return "整理请求格式不正确。"
        case 401, 403:
            return "百炼 API Key 无效，或当前账号没有整理模型调用权限。"
        default:
            return "整理模型请求失败，状态码 \(statusCode)。"
        }
    }
}

private extension AliyunCleanupService {
    struct ClassificationRequest: Encodable {
        let model: String
        let messages: [Message]
        let stream: Bool
        let temperature: Double
        let enableThinking: Bool

        enum CodingKeys: String, CodingKey {
            case model
            case messages
            case stream
            case temperature
            case enableThinking = "enable_thinking"
        }

        init(systemPrompt: String, userPrompt: String) {
            self.model = "qwen3.5-flash"
            self.messages = [
                Message(role: "system", content: systemPrompt),
                Message(role: "user", content: userPrompt)
            ]
            self.stream = false
            self.temperature = 0.0
            self.enableThinking = false
        }
    }

    struct CleanupRequest: Encodable {
        let model: String
        let messages: [Message]
        let stream: Bool
        let temperature: Double
        let enableThinking: Bool

        enum CodingKeys: String, CodingKey {
            case model
            case messages
            case stream
            case temperature
            case enableThinking = "enable_thinking"
        }

        init(systemPrompt: String, userPrompt: String) {
            self.model = "qwen3.5-flash"
            self.messages = [
                Message(role: "system", content: systemPrompt),
                Message(role: "user", content: userPrompt)
            ]
            self.stream = false
            self.temperature = 0.0
            self.enableThinking = false
        }
    }

    struct Message: Encodable {
        let role: String
        let content: String
    }
}
