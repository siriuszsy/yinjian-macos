import Foundation

protocol RealtimeWebSocketTasking: AnyObject, Sendable {
    func resume()
    func send(_ message: URLSessionWebSocketTask.Message) async throws
    func receive() async throws -> URLSessionWebSocketTask.Message
    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
}

extension URLSessionWebSocketTask: RealtimeWebSocketTasking {}
extension URLSessionWebSocketTask: @unchecked Sendable {}

protocol RealtimeWebSocketTaskProvider {
    func makeTask(with request: URLRequest) -> any RealtimeWebSocketTasking
}

struct URLSessionRealtimeWebSocketTaskProvider: RealtimeWebSocketTaskProvider {
    let session: URLSession

    func makeTask(with request: URLRequest) -> any RealtimeWebSocketTasking {
        session.webSocketTask(with: request)
    }
}

struct RealtimeSessionTimeouts {
    let sessionCreatedNanoseconds: UInt64
    let sessionUpdatedNanoseconds: UInt64
    let finalTranscriptNanoseconds: UInt64

    static let `default` = RealtimeSessionTimeouts(
        sessionCreatedNanoseconds: 8_000_000_000,
        sessionUpdatedNanoseconds: 8_000_000_000,
        finalTranscriptNanoseconds: 30_000_000_000
    )
}

final class AliyunRealtimeASRService: RealtimeASRService, ASRService, LiveStreamingASRService, @unchecked Sendable {
    private enum RealtimeConstants {
        static let sampleRate = 16_000
        static let channelCount = 1
        static let chunkDurationMs = 40
        static let bytesPerSample = 2
    }

    private let apiKeyStore: APIKeyStore
    private let session: URLSession
    private let liveSessionCoordinator = LiveRealtimeSessionCoordinator()
    private let logger: OSLogLogger
    private let taskProvider: any RealtimeWebSocketTaskProvider
    private let timeouts: RealtimeSessionTimeouts

    init(
        apiKeyStore: APIKeyStore,
        session: URLSession = .shared,
        logger: OSLogLogger = OSLogLogger(),
        taskProvider: (any RealtimeWebSocketTaskProvider)? = nil,
        timeouts: RealtimeSessionTimeouts = .default
    ) {
        self.apiKeyStore = apiKeyStore
        self.session = session
        self.logger = logger
        self.taskProvider = taskProvider ?? URLSessionRealtimeWebSocketTaskProvider(session: session)
        self.timeouts = timeouts
    }

    func transcribe(_ payload: AudioPayload) async throws -> ASRTranscript {
        guard payload.format.lowercased() == "wav" else {
            throw DictationError.asrFailed("实时识别当前只支持 WAV 录音。")
        }

        guard payload.sampleRate == RealtimeConstants.sampleRate else {
            throw DictationError.asrFailed("实时识别当前只支持 16kHz 录音。")
        }

        let pcmData = try extractPCMData(from: payload.fileURL)
        let audioChunks = makeAudioChunks(from: pcmData, sampleRate: payload.sampleRate)
        let realtimeSession = try await startSession(languageCode: nil)

        do {
            for chunk in audioChunks {
                try await realtimeSession.appendAudioChunk(chunk)
            }

            return try await realtimeSession.finish()
        } catch {
            await realtimeSession.cancel()
            throw error
        }
    }

    func beginLiveTranscription(languageCode: String?) async throws -> Bool {
        await liveSessionCoordinator.cancelAndClear()
        let liveSession = try await startSession(languageCode: languageCode)
        await liveSessionCoordinator.setSession(liveSession)
        return true
    }

    func appendLiveAudioChunk(_ chunk: AudioChunk) async throws {
        try await liveSessionCoordinator.append(chunk)
    }

    func finishLiveTranscription() async throws -> ASRTranscript? {
        try await liveSessionCoordinator.finishAndClear()
    }

    func cancelLiveTranscription() async {
        await liveSessionCoordinator.cancelAndClear()
    }

    func startSession(languageCode: String?) async throws -> RealtimeASRSession {
        let apiKey = try loadAPIKey()
        var request = URLRequest(
            url: URL(string: "wss://dashscope.aliyuncs.com/api-ws/v1/realtime?model=qwen3-asr-flash-realtime")!
        )
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let task = taskProvider.makeTask(with: request)
        let realtimeSession = AliyunRealtimeASRSession(
            task: task,
            languageCode: languageCode,
            logger: logger,
            timeouts: timeouts
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

    private func extractPCMData(from fileURL: URL) throws -> Data {
        let data = try Data(contentsOf: fileURL)
        guard data.count >= 12 else {
            throw DictationError.asrFailed("录音文件格式不正确。")
        }

        let riffHeader = String(decoding: data[0..<4], as: UTF8.self)
        let waveHeader = String(decoding: data[8..<12], as: UTF8.self)
        guard riffHeader == "RIFF", waveHeader == "WAVE" else {
            throw DictationError.asrFailed("当前录音文件不是标准 WAV。")
        }

        var offset = 12
        while offset + 8 <= data.count {
            let chunkID = String(decoding: data[offset..<(offset + 4)], as: UTF8.self)
            let chunkSize = Int(uint32LE(in: data, offset: offset + 4))
            let chunkDataStart = offset + 8
            let chunkDataEnd = chunkDataStart + chunkSize

            guard chunkDataEnd <= data.count else {
                throw DictationError.asrFailed("WAV 数据块已损坏。")
            }

            if chunkID == "data" {
                return data.subdata(in: chunkDataStart..<chunkDataEnd)
            }

            offset = chunkDataEnd + (chunkSize % 2)
        }

        throw DictationError.asrFailed("WAV 文件里没有找到音频数据块。")
    }

    private func makeAudioChunks(from pcmData: Data, sampleRate: Int) -> [AudioChunk] {
        let framesPerChunk = max((sampleRate * RealtimeConstants.chunkDurationMs) / 1000, 1)
        let bytesPerChunk = framesPerChunk * RealtimeConstants.bytesPerSample * RealtimeConstants.channelCount
        var chunks: [AudioChunk] = []
        var offset = 0

        while offset < pcmData.count {
            let nextOffset = min(offset + bytesPerChunk, pcmData.count)
            chunks.append(
                AudioChunk(
                    data: pcmData.subdata(in: offset..<nextOffset),
                    sampleRate: sampleRate,
                    channelCount: RealtimeConstants.channelCount
                )
            )
            offset = nextOffset
        }

        return chunks
    }

    private func uint32LE(in data: Data, offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}

private actor LiveRealtimeSessionCoordinator {
    private var session: RealtimeASRSession?

    func setSession(_ session: RealtimeASRSession) {
        self.session = session
    }

    func append(_ chunk: AudioChunk) async throws {
        guard let session else {
            throw DictationError.asrFailed("实时识别会话未启动。")
        }

        try await session.appendAudioChunk(chunk)
    }

    func finishAndClear() async throws -> ASRTranscript {
        guard let session else {
            throw DictationError.asrFailed("实时识别会话未启动。")
        }

        self.session = nil
        return try await session.finish()
    }

    func cancelAndClear() async {
        let currentSession = session
        session = nil
        await currentSession?.cancel()
    }
}

private actor AliyunRealtimeASRSession: RealtimeASRSession {
    private enum TimeoutStage: Hashable {
        case sessionCreated
        case sessionUpdated
        case finalTranscript

        func timeoutNanoseconds(using timeouts: RealtimeSessionTimeouts) -> UInt64 {
            switch self {
            case .sessionCreated:
                return timeouts.sessionCreatedNanoseconds
            case .sessionUpdated:
                return timeouts.sessionUpdatedNanoseconds
            case .finalTranscript:
                return timeouts.finalTranscriptNanoseconds
            }
        }

        var failureMessage: String {
            switch self {
            case .sessionCreated:
                return "实时识别连接已建立，但服务端迟迟没有返回 session.created。"
            case .sessionUpdated:
                return "实时识别配置已发送，但服务端迟迟没有返回 session.updated。"
            case .finalTranscript:
                return "实时识别长时间没有返回最终结果。"
            }
        }

        var label: String {
            switch self {
            case .sessionCreated:
                return "session.created"
            case .sessionUpdated:
                return "session.updated"
            case .finalTranscript:
                return "final transcript"
            }
        }
    }

    private let task: any RealtimeWebSocketTasking
    private let languageCode: String?
    private let logger: OSLogLogger
    private let timeouts: RealtimeSessionTimeouts
    private let sessionID = UUID().uuidString

    private var receiveLoopTask: Task<Void, Never>?
    private var createdContinuation: CheckedContinuation<Void, Error>?
    private var updatedContinuation: CheckedContinuation<Void, Error>?
    private var finalTranscriptContinuation: CheckedContinuation<ASRTranscript, Error>?
    // The server can acknowledge or finish before the next waiter is installed.
    private var didReceiveCreated = false
    private var didReceiveUpdated = false
    private var completedTranscript: ASRTranscript?
    private var pendingTerminalError: Error?
    private var didRequestFinish = false
    private var timeoutTasks: [TimeoutStage: Task<Void, Never>] = [:]

    init(
        task: any RealtimeWebSocketTasking,
        languageCode: String?,
        logger: OSLogLogger,
        timeouts: RealtimeSessionTimeouts
    ) {
        self.task = task
        self.languageCode = languageCode
        self.logger = logger
        self.timeouts = timeouts
    }

    func connect() async throws {
        logger.info("[RealtimeASR][\(sessionID)] Opening websocket session.")
        task.resume()
        receiveLoopTask = Task { [weak task] in
            guard task != nil else { return }
            await self.receiveLoop()
        }

        logger.info("[RealtimeASR][\(sessionID)] Waiting for session.created.")
        try await waitForCreated()
        try await sendEvent(sessionUpdateEvent())
        logger.info("[RealtimeASR][\(sessionID)] Sent session.update, waiting for session.updated.")
        try await waitForUpdated()
        logger.info("[RealtimeASR][\(sessionID)] Session is ready.")
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
        logger.info("[RealtimeASR][\(sessionID)] Finishing session and waiting for final transcript.")

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

        if let pendingTerminalError {
            throw pendingTerminalError
        }

        if let completedTranscript {
            self.completedTranscript = nil
            return completedTranscript
        }

        return try await withCheckedThrowingContinuation { continuation in
            if let pendingTerminalError {
                continuation.resume(throwing: pendingTerminalError)
                return
            }

            if let completedTranscript {
                self.completedTranscript = nil
                continuation.resume(returning: completedTranscript)
                return
            }

            finalTranscriptContinuation = continuation
            startTimeout(for: .finalTranscript)
        }
    }

    func cancel() async {
        logger.info("[RealtimeASR][\(sessionID)] Cancelling session.")
        cancelAllTimeouts()
        receiveLoopTask?.cancel()
        task.cancel(with: .goingAway, reason: nil)
    }

    private func waitForCreated() async throws {
        if let pendingTerminalError {
            throw pendingTerminalError
        }

        if didReceiveCreated {
            return
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            if let pendingTerminalError {
                continuation.resume(throwing: pendingTerminalError)
                return
            }

            if didReceiveCreated {
                continuation.resume()
                return
            }

            createdContinuation = continuation
            startTimeout(for: .sessionCreated)
        }
    }

    private func waitForUpdated() async throws {
        if let pendingTerminalError {
            throw pendingTerminalError
        }

        if didReceiveUpdated {
            return
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            if let pendingTerminalError {
                continuation.resume(throwing: pendingTerminalError)
                return
            }

            if didReceiveUpdated {
                continuation.resume()
                return
            }

            updatedContinuation = continuation
            startTimeout(for: .sessionUpdated)
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
                if Task.isCancelled {
                    break
                }
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
            cancelTimeout(for: .sessionCreated)
            if let createdContinuation {
                createdContinuation.resume()
                self.createdContinuation = nil
            } else {
                didReceiveCreated = true
            }
            logger.info("[RealtimeASR][\(sessionID)] Received session.created.")
        case "session.updated":
            cancelTimeout(for: .sessionUpdated)
            if let updatedContinuation {
                updatedContinuation.resume()
                self.updatedContinuation = nil
            } else {
                didReceiveUpdated = true
            }
            logger.info("[RealtimeASR][\(sessionID)] Received session.updated.")
        case "conversation.item.input_audio_transcription.completed":
            cancelTimeout(for: .finalTranscript)
            let transcript = (json["transcript"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let language = json["language"] as? String
            if transcript.isEmpty {
                await handleTerminalError(DictationError.asrFailed("实时识别返回了空结果。"))
                return
            }
            let finalTranscript = ASRTranscript(rawText: transcript, languageCode: language)
            if let finalTranscriptContinuation {
                finalTranscriptContinuation.resume(returning: finalTranscript)
                self.finalTranscriptContinuation = nil
            } else {
                completedTranscript = finalTranscript
            }
            logger.info("[RealtimeASR][\(sessionID)] Received final transcript (\(transcript.count) chars).")
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

    private func startTimeout(for stage: TimeoutStage) {
        cancelTimeout(for: stage)
        timeoutTasks[stage] = Task { [stage] in
            try? await Task.sleep(nanoseconds: stage.timeoutNanoseconds(using: self.timeouts))
            await self.handleTimeout(for: stage)
        }
    }

    private func cancelTimeout(for stage: TimeoutStage) {
        timeoutTasks.removeValue(forKey: stage)?.cancel()
    }

    private func cancelAllTimeouts() {
        timeoutTasks.values.forEach { $0.cancel() }
        timeoutTasks.removeAll()
    }

    private func handleTimeout(for stage: TimeoutStage) async {
        guard pendingTerminalError == nil else {
            return
        }

        switch stage {
        case .sessionCreated:
            guard createdContinuation != nil, !didReceiveCreated else {
                return
            }
        case .sessionUpdated:
            guard updatedContinuation != nil, !didReceiveUpdated else {
                return
            }
        case .finalTranscript:
            guard finalTranscriptContinuation != nil, completedTranscript == nil else {
                return
            }
        }

        let error = DictationError.asrFailed(stage.failureMessage)
        logger.error("[RealtimeASR][\(sessionID)] Timed out waiting for \(stage.label).")
        receiveLoopTask?.cancel()
        task.cancel(with: .goingAway, reason: nil)
        await handleTerminalError(error)
    }

    private func handleTerminalError(_ error: Error) async {
        if pendingTerminalError == nil {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            logger.error("[RealtimeASR][\(sessionID)] Terminal error: \(message)")
            pendingTerminalError = error
        }

        cancelAllTimeouts()

        createdContinuation?.resume(throwing: error)
        createdContinuation = nil

        updatedContinuation?.resume(throwing: error)
        updatedContinuation = nil

        finalTranscriptContinuation?.resume(throwing: error)
        finalTranscriptContinuation = nil
    }
}
