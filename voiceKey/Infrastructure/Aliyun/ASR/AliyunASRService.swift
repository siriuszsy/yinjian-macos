import Foundation

final class AliyunASRService: ASRService, @unchecked Sendable {
    private let httpClient: HTTPClient
    private let apiKeyStore: APIKeyStore

    init(httpClient: HTTPClient, apiKeyStore: APIKeyStore) {
        self.httpClient = httpClient
        self.apiKeyStore = apiKeyStore
    }

    func transcribe(_ payload: AudioPayload) async throws -> ASRTranscript {
        let apiKey = try loadAPIKey()
        let requestBody = try JSONEncoder().encode(
            AliyunASRRequest(audioDataURI: try makeAudioDataURI(for: payload))
        )
        let request = try AliyunRequestFactory.makeASRRequest(apiKey: apiKey, body: requestBody)
        let (data, response) = try await httpClient.perform(request)

        guard (200..<300).contains(response.statusCode) else {
            throw DictationError.asrFailed(errorMessage(from: data, statusCode: response.statusCode))
        }

        let decoded = try JSONDecoder().decode(AliyunASRResponse.self, from: data)
        if let apiError = decoded.error?.message, !apiError.isEmpty {
            throw DictationError.asrFailed(apiError)
        }

        guard let text = decoded.transcriptText, !text.isEmpty else {
            throw DictationError.asrFailed("语音服务返回了空结果。")
        }

        return ASRTranscript(rawText: text, languageCode: nil)
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

        throw DictationError.asrFailed("请先在设置里配置百炼 API Key。")
    }

    private func makeAudioDataURI(for payload: AudioPayload) throws -> String {
        let audioData = try Data(contentsOf: payload.fileURL)
        let base64String = audioData.base64EncodedString()
        let mimeType = mimeType(for: payload)
        return "data:\(mimeType);base64,\(base64String)"
    }

    private func mimeType(for payload: AudioPayload) -> String {
        switch payload.format.lowercased() {
        case "wav":
            return "audio/wav"
        case "mp3":
            return "audio/mpeg"
        case "m4a":
            return "audio/m4a"
        case "aac":
            return "audio/aac"
        default:
            return "application/octet-stream"
        }
    }

    private func errorMessage(from data: Data, statusCode: Int) -> String {
        if let decoded = try? JSONDecoder().decode(AliyunASRResponse.self, from: data),
           let message = decoded.error?.message,
           !message.isEmpty {
            return message
        }

        switch statusCode {
        case 400:
            return "请求格式不正确。"
        case 401, 403:
            return "百炼 API Key 无效，或当前账号没有调用权限。"
        case 413:
            return "音频文件过大。"
        default:
            return "语音服务请求失败，状态码 \(statusCode)。"
        }
    }
}
