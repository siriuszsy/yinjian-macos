import Foundation
import XCTest
@testable import voiceKey

final class AliyunRealtimeASRServiceTests: XCTestCase {
    func testStartSessionSucceedsWhenSessionUpdatedArrivesBeforeWaiterInstalls() async throws {
        let task = ScriptedWebSocketTask(
            initialMessages: [message(type: "session.created")]
        )
        await task.setOnSendEvent { eventType in
            guard eventType == "session.update" else {
                return
            }

            await task.enqueue(message(type: "session.updated"))
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        let service = makeService(task: task)

        _ = try await service.startSession(languageCode: nil)

        let eventTypes = await task.recordedEventTypes()
        XCTAssertEqual(eventTypes, ["session.update"])
    }

    func testFinishSucceedsWhenFinalTranscriptArrivesBeforeWaiterInstalls() async throws {
        let task = ScriptedWebSocketTask(
            initialMessages: [message(type: "session.created")]
        )
        await task.setOnSendEvent { eventType in
            switch eventType {
            case "session.update":
                await task.enqueue(message(type: "session.updated"))
                try? await Task.sleep(nanoseconds: 20_000_000)
            case "session.finish":
                await task.enqueue(
                    message(
                        type: "conversation.item.input_audio_transcription.completed",
                        transcript: "你好",
                        language: "zh-CN"
                    )
                )
                try? await Task.sleep(nanoseconds: 20_000_000)
            default:
                break
            }
        }

        let service = makeService(task: task)
        let session = try await service.startSession(languageCode: nil)

        let transcript = try await session.finish()

        XCTAssertEqual(transcript.rawText, "你好")
        XCTAssertEqual(transcript.languageCode, "zh-CN")
    }

    func testStartSessionFailsFastWhenSessionUpdatedNeverArrives() async {
        let task = ScriptedWebSocketTask(
            initialMessages: [message(type: "session.created")]
        )
        let service = makeService(
            task: task,
            timeouts: RealtimeSessionTimeouts(
                sessionCreatedNanoseconds: 100_000_000,
                sessionUpdatedNanoseconds: 20_000_000,
                finalTranscriptNanoseconds: 100_000_000
            )
        )

        do {
            _ = try await service.startSession(languageCode: nil)
            XCTFail("Expected session startup to time out.")
        } catch let error as DictationError {
            guard case .asrFailed(let message) = error else {
                XCTFail("Unexpected dictation error: \(error)")
                return
            }

            XCTAssertEqual(message, "实时识别配置已发送，但服务端迟迟没有返回 session.updated。")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeService(
        task: ScriptedWebSocketTask,
        timeouts: RealtimeSessionTimeouts = .default
    ) -> AliyunRealtimeASRService {
        AliyunRealtimeASRService(
            apiKeyStore: StubAPIKeyStore(),
            taskProvider: FixedWebSocketTaskProvider(task: task),
            timeouts: timeouts
        )
    }

}

private struct StubAPIKeyStore: APIKeyStore {
    func save(_ key: String) throws {
        _ = key
    }

    func load() throws -> String {
        "test-api-key"
    }
}

private struct FixedWebSocketTaskProvider: RealtimeWebSocketTaskProvider {
    let task: any RealtimeWebSocketTasking

    func makeTask(with request: URLRequest) -> any RealtimeWebSocketTasking {
        _ = request
        return task
    }
}

private func message(
    type: String,
    transcript: String? = nil,
    language: String? = nil
) -> URLSessionWebSocketTask.Message {
    var payload: [String: Any] = ["type": type]
    if let transcript {
        payload["transcript"] = transcript
    }
    if let language {
        payload["language"] = language
    }

    let data = try! JSONSerialization.data(withJSONObject: payload)
    return .string(String(decoding: data, as: UTF8.self))
}

private final class ScriptedWebSocketTask: RealtimeWebSocketTasking, @unchecked Sendable {
    private let state: State

    init(initialMessages: [URLSessionWebSocketTask.Message] = []) {
        self.state = State(initialMessages: initialMessages)
    }

    func setOnSendEvent(_ handler: @escaping @Sendable (String) async -> Void) async {
        await state.setOnSendEvent(handler)
    }

    func enqueue(_ message: URLSessionWebSocketTask.Message) async {
        await state.enqueue(message)
    }

    func recordedEventTypes() async -> [String] {
        await state.recordedEventTypes()
    }

    func resume() {}

    func send(_ message: URLSessionWebSocketTask.Message) async throws {
        try await state.send(message)
    }

    func receive() async throws -> URLSessionWebSocketTask.Message {
        try await state.receive()
    }

    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        _ = closeCode
        _ = reason

        Task {
            await state.cancel()
        }
    }

    private actor State {
        private var queuedMessages: [URLSessionWebSocketTask.Message]
        private var receiveContinuations: [CheckedContinuation<URLSessionWebSocketTask.Message, Error>] = []
        private var onSendEvent: (@Sendable (String) async -> Void)?
        private var sentEventTypes: [String] = []
        private var cancellationError: Error?

        init(initialMessages: [URLSessionWebSocketTask.Message]) {
            self.queuedMessages = initialMessages
        }

        func setOnSendEvent(_ handler: @escaping @Sendable (String) async -> Void) {
            onSendEvent = handler
        }

        func enqueue(_ message: URLSessionWebSocketTask.Message) {
            if let continuation = receiveContinuations.first {
                receiveContinuations.removeFirst()
                continuation.resume(returning: message)
                return
            }

            queuedMessages.append(message)
        }

        func recordedEventTypes() -> [String] {
            sentEventTypes
        }

        func send(_ message: URLSessionWebSocketTask.Message) async throws {
            let eventType = try eventType(from: message)
            sentEventTypes.append(eventType)
            if let onSendEvent {
                await onSendEvent(eventType)
            }
        }

        func receive() async throws -> URLSessionWebSocketTask.Message {
            if let cancellationError {
                throw cancellationError
            }

            if !queuedMessages.isEmpty {
                return queuedMessages.removeFirst()
            }

            return try await withCheckedThrowingContinuation { continuation in
                receiveContinuations.append(continuation)
            }
        }

        func cancel() {
            let error = URLError(.cancelled)
            cancellationError = error
            let continuations = receiveContinuations
            receiveContinuations.removeAll()
            continuations.forEach { $0.resume(throwing: error) }
        }

        private func eventType(from message: URLSessionWebSocketTask.Message) throws -> String {
            let text: String
            switch message {
            case .string(let string):
                text = string
            case .data(let data):
                guard let string = String(data: data, encoding: .utf8) else {
                    throw URLError(.cannotDecodeContentData)
                }
                text = string
            @unknown default:
                throw URLError(.cannotParseResponse)
            }

            let data = Data(text.utf8)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return (json?["type"] as? String) ?? ""
        }
    }
}
