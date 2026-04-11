import Foundation

final class AliyunRealtimeASRService: RealtimeASRService {
    private let apiKeyStore: APIKeyStore
    private let session: URLSession

    init(
        apiKeyStore: APIKeyStore,
        session: URLSession = .shared
    ) {
        self.apiKeyStore = apiKeyStore
        self.session = session
    }

    func startSession(languageCode: String?) async throws -> RealtimeASRSession {
        let apiKey = try loadAPIKey()
        var request = URLRequest(
            url: URL(string: "wss://dashscope.aliyuncs.com/api-ws/v1/realtime?model=qwen3-asr-flash-realtime")!
        )
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let task = session.webSocketTask(with: request)
        let realtimeSession = AliyunRealtimeASRSession(
            task: task,
            languageCode: languageCode
        )
        try await realtimeSession.connect()
        return realtimeSession
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
            // Fall through to user-facing error below.
        }

        throw DictationError.asrFailed("请先在设置里配置百炼 API Key。")
    }
}

private actor AliyunRealtimeASRSession: RealtimeASRSession {
    private let task: URLSessionWebSocketTask
    private let languageCode: String?

    private var receiveLoopTask: Task<Void, Never>?
    private var createdContinuation: CheckedContinuation<Void, Error>?
    private var updatedContinuation: CheckedContinuation<Void, Error>?
    private var finalTranscriptContinuation: CheckedContinuation<ASRTranscript, Error>?
    private var pendingTerminalError: Error?
    private var didRequestFinish = false

    init(
        task: URLSessionWebSocketTask,
        languageCode: String?
    ) {
        self.task = task
        self.languageCode = languageCode
    }

    func connect() async throws {
        task.resume()
        receiveLoopTask = Task { [weak task] in
            guard task != nil else { return }
            await self.receiveLoop()
        }

        try await waitForCreated()
        try await sendEvent(sessionUpdateEvent())
        try await waitForUpdated()
    }

    func appendAudioChunk(_ chunk: AudioChunk) async throws {
        try await sendEvent(
            [
                "event_id": UUID().uuidString,
                "type": "input_audio_buffer.append",
                "audio": chunk.data.base64EncodedString()
            ]
        )
    }

    func finish() async throws -> ASRTranscript {
        didRequestFinish = true

        try await sendEvent(
            [
                "event_id": UUID().uuidString,
                "type": "input_audio_buffer.commit"
            ]
        )

        try await sendEvent(
            [
                "event_id": UUID().uuidString,
                "type": "session.finish"
            ]
        )

        return try await withCheckedThrowingContinuation { continuation in
            if let pendingTerminalError {
                continuation.resume(throwing: pendingTerminalError)
                return
            }

            finalTranscriptContinuation = continuation
        }
    }

    func cancel() async {
        receiveLoopTask?.cancel()
        task.cancel(with: .goingAway, reason: nil)
    }

    private func waitForCreated() async throws {
        try await withCheckedThrowingContinuation { continuation in
            createdContinuation = continuation
        }
    }

    private func waitForUpdated() async throws {
        try await withCheckedThrowingContinuation { continuation in
            updatedContinuation = continuation
        }
    }

    private func sessionUpdateEvent() -> [String: Any] {
        var transcription: [String: Any] = [:]
        if let languageCode, !languageCode.isEmpty {
            transcription["language"] = languageCode
        }

        return [
            "event_id": UUID().uuidString,
            "type": "session.update",
            "session": [
                "input_audio_format": "pcm",
                "sample_rate": 16000,
                "turn_detection": NSNull(),
                "input_audio_transcription": transcription
            ]
        ]
    }

    private func sendEvent(_ payload: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let text = String(data: data, encoding: .utf8) else {
            throw DictationError.asrFailed("无法构造实时识别请求。")
        }
        try await task.send(.string(text))
    }

    private func receiveLoop() async {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                try await handle(message: message)
            } catch {
                await handleTerminalError(error)
                break
            }
        }
    }

    private func handle(message: URLSessionWebSocketTask.Message) async throws {
        let text: String
        switch message {
        case .string(let string):
            text = string
        case .data(let data):
            guard let string = String(data: data, encoding: .utf8) else { return }
            text = string
        @unknown default:
            return
        }

        guard let data = text.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        switch type {
        case "session.created":
            createdContinuation?.resume()
            createdContinuation = nil
        case "session.updated":
            updatedContinuation?.resume()
            updatedContinuation = nil
        case "conversation.item.input_audio_transcription.completed":
            let transcript = (json["transcript"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let language = json["language"] as? String
            if transcript.isEmpty {
                await handleTerminalError(DictationError.asrFailed("实时识别返回了空结果。"))
                return
            }
            finalTranscriptContinuation?.resume(returning: ASRTranscript(rawText: transcript, languageCode: language))
            finalTranscriptContinuation = nil
            receiveLoopTask?.cancel()
            task.cancel(with: .normalClosure, reason: nil)
        case "conversation.item.input_audio_transcription.failed":
            let message = (((json["error"] as? [String: Any])?["message"]) as? String) ?? "实时识别失败。"
            await handleTerminalError(DictationError.asrFailed(message))
        case "error":
            let message = (((json["error"] as? [String: Any])?["message"]) as? String) ?? "实时识别服务发生错误。"
            await handleTerminalError(DictationError.asrFailed(message))
        case "session.finished":
            if didRequestFinish, finalTranscriptContinuation != nil {
                await handleTerminalError(DictationError.asrFailed("实时识别已结束，但没有返回最终结果。"))
            }
            receiveLoopTask?.cancel()
            task.cancel(with: .normalClosure, reason: nil)
        default:
            break
        }
    }

    private func handleTerminalError(_ error: Error) async {
        pendingTerminalError = error

        createdContinuation?.resume(throwing: error)
        createdContinuation = nil

        updatedContinuation?.resume(throwing: error)
        updatedContinuation = nil

        finalTranscriptContinuation?.resume(throwing: error)
        finalTranscriptContinuation = nil
    }
}
