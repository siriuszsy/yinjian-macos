import Foundation

final class RuntimeIndicatorPreviewCoordinator: TriggerEngineDelegate, RecordingLevelObserving, @unchecked Sendable {
    private let triggerEngine: TriggerEngine
    private let recordingEngine: RecordingEngine
    private let asrService: ASRService
    private let hudController: StatusHUDControlling
    private let settingsStore: SettingsStore
    private let sessionLogStore: SessionLogStore
    private let clock: Clock
    private let stateMachine = RuntimeIndicatorStateMachine()
    private var scheduledWorkItems: [DispatchWorkItem] = []
    private var isPressed = false
    private var recordingStartedAt: Date?
    private var triggerReleasedAt: Date?

    init(
        triggerEngine: TriggerEngine,
        recordingEngine: RecordingEngine,
        asrService: ASRService,
        hudController: StatusHUDControlling,
        settingsStore: SettingsStore,
        sessionLogStore: SessionLogStore,
        clock: Clock
    ) {
        self.triggerEngine = triggerEngine
        self.recordingEngine = recordingEngine
        self.asrService = asrService
        self.hudController = hudController
        self.settingsStore = settingsStore
        self.sessionLogStore = sessionLogStore
        self.clock = clock
    }

    func start() throws {
        try triggerEngine.start()
        send(.appReady(triggerKey: currentTriggerKey))
    }

    func stop() {
        triggerEngine.stop()
        cancelScheduledSignals()
        isPressed = false
        send(.reset)
    }

    func triggerDidPressDown(for intent: SessionIntent, at timestamp: TimeInterval) {
        guard intent == .dictation else {
            return
        }
        _ = timestamp
        cancelScheduledSignals()
        guard !isPressed else {
            return
        }

        do {
            try recordingEngine.startRecording()
            isPressed = true
            recordingStartedAt = clock.now()
            send(.triggerPressed(triggerKey: currentTriggerKey))
        } catch {
            handle(error)
        }
    }

    func triggerDidRelease(for intent: SessionIntent, at timestamp: TimeInterval) {
        guard intent == .dictation else {
            return
        }
        _ = timestamp
        guard isPressed else {
            return
        }

        isPressed = false
        cancelScheduledSignals()
        send(.triggerReleased)
        let recordingStartedAt = self.recordingStartedAt
        let triggerReleasedAt = clock.now()
        self.triggerReleasedAt = triggerReleasedAt

        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let audioPayload = try await recordingEngine.stopRecording()
                await completeRecording(
                    with: audioPayload,
                    recordingStartedAt: recordingStartedAt,
                    triggerReleasedAt: triggerReleasedAt
                )
            } catch {
                handle(error)
            }
        }
    }

    func send(_ signal: RuntimeIndicatorSignal) {
        let nextState = stateMachine.send(signal)
        hudController.render(nextState)
    }

    func recordingLevelDidUpdate(normalizedLevel: Float) {
        hudController.updateInputLevel(normalizedLevel)
    }

    func recordingVisualizationDidUpdate(barLevels: [Float], normalizedLevel: Float) {
        hudController.updateVisualization(barLevels: barLevels, level: normalizedLevel)
    }

    func simulateHappyPath() {
        cancelScheduledSignals()
        send(.triggerReleased)
        schedule(.asrRequestStarted, after: 0.12)
        schedule(.cleanupRequestStarted, after: 0.58)
        schedule(.insertionStarted, after: 0.92)
        schedule(.insertionSucceeded, after: 1.18)
        schedule(.autoDismiss, after: 1.82)
    }

    func simulateFallbackFlow() {
        cancelScheduledSignals()
        send(.triggerReleased)
        schedule(.asrRequestStarted, after: 0.12)
        schedule(.cleanupRequestStarted, after: 0.56)
        schedule(.insertionStarted, after: 0.86)
        schedule(.fallbackPrepared(message: "插入失败，已复制到剪贴板"), after: 1.14)
        schedule(.autoDismiss, after: 1.88)
    }

    func simulateMicrophoneBlocked() {
        cancelScheduledSignals()
        send(.microphonePermissionDenied)
    }

    func simulateAccessibilityBlocked() {
        cancelScheduledSignals()
        send(.accessibilityPermissionDenied)
    }

    func simulateNetworkFailure() {
        cancelScheduledSignals()
        send(.networkRequestFailed(message: "调用语音服务时网络失败"))
    }

    func resetToIdle() {
        cancelScheduledSignals()
        send(.reset)
    }

    private var currentTriggerKey: TriggerKey {
        (try? settingsStore.load().triggerKey) ?? .rightOption
    }

    private func completeRecording(
        with audioPayload: AudioPayload,
        recordingStartedAt: Date?,
        triggerReleasedAt: Date
    ) async {
        do {
            await MainActor.run {
                self.send(.asrRequestStarted)
            }

            let asrStartedAt = clock.now()
            let transcript = try await asrService.transcribe(audioPayload)
            let asrFinishedAt = clock.now()
            await logRecording(
                audioPayload,
                recordingStartedAt: recordingStartedAt,
                transcript: transcript,
                asrStartedAt: asrStartedAt,
                asrFinishedAt: asrFinishedAt,
                triggerReleasedAt: triggerReleasedAt
            )

            await MainActor.run {
                self.recordingStartedAt = nil
                self.triggerReleasedAt = nil
                self.send(.recordingSaved(message: self.transcriptPreview(from: transcript.rawText)))
                self.schedule(.autoDismiss, after: 1.4)
            }
        } catch {
            await logFailure(
                audioPayload,
                recordingStartedAt: recordingStartedAt,
                triggerReleasedAt: triggerReleasedAt,
                error: error
            )
            handle(error)
        }
    }

    private func handle(_ error: Error) {
        let signal: RuntimeIndicatorSignal

        if let dictationError = error as? DictationError {
            switch dictationError {
            case .microphonePermissionDenied:
                signal = .microphonePermissionDenied
            default:
                signal = .unknownFailure(message: dictationError.errorDescription ?? "录音失败")
            }
        } else {
            signal = .unknownFailure(message: error.localizedDescription)
        }

        DispatchQueue.main.async {
            self.send(signal)
            self.schedule(.autoDismiss, after: 2.2)
        }
    }

    private func logRecording(
        _ audioPayload: AudioPayload,
        recordingStartedAt: Date?,
        transcript: ASRTranscript?,
        asrStartedAt: Date?,
        asrFinishedAt: Date?,
        triggerReleasedAt: Date?
    ) async {
        let startedAt = recordingStartedAt ?? clock.now()
        let asrDurationMs = durationMs(from: asrStartedAt, to: asrFinishedAt)
        let totalAfterReleaseMs = durationMs(from: triggerReleasedAt, to: asrFinishedAt)
        let record = SessionRecord(
            id: UUID(),
            startedAt: startedAt,
            endedAt: clock.now(),
            focusedApp: "录音阶段",
            audioFilePath: audioPayload.fileURL.path,
            rawTranscript: transcript?.rawText,
            cleanText: nil,
            inserted: false,
            fallbackUsed: false,
            failureReason: nil,
            latency: LatencyMetrics(
                recordingDurationMs: audioPayload.durationMs,
                asrDurationMs: asrDurationMs,
                cleanupDurationMs: 0,
                insertionDurationMs: 0,
                totalAfterReleaseMs: totalAfterReleaseMs
            )
        )

        await sessionLogStore.append(record)
    }

    private func logFailure(
        _ audioPayload: AudioPayload?,
        recordingStartedAt: Date?,
        triggerReleasedAt: Date?,
        error: Error
    ) async {
        let endedAt = clock.now()
        let record = SessionRecord(
            id: UUID(),
            startedAt: recordingStartedAt ?? endedAt,
            endedAt: endedAt,
            focusedApp: "录音阶段",
            audioFilePath: audioPayload?.fileURL.path,
            rawTranscript: nil,
            cleanText: nil,
            inserted: false,
            fallbackUsed: false,
            failureReason: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription,
            latency: LatencyMetrics(
                recordingDurationMs: audioPayload?.durationMs ?? 0,
                asrDurationMs: durationMs(from: triggerReleasedAt, to: endedAt),
                cleanupDurationMs: 0,
                insertionDurationMs: 0,
                totalAfterReleaseMs: durationMs(from: triggerReleasedAt, to: endedAt)
            )
        )

        await sessionLogStore.append(record)
    }

    private func transcriptPreview(from transcript: String) -> String {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 28 else {
            return trimmed
        }

        return String(trimmed.prefix(28)) + "…"
    }

    private func durationMs(from start: Date?, to end: Date?) -> Int {
        guard let start, let end else {
            return 0
        }

        return max(Int(end.timeIntervalSince(start) * 1000), 0)
    }

    private func schedule(_ signal: RuntimeIndicatorSignal, after delay: TimeInterval) {
        let workItem = DispatchWorkItem { [weak self] in
            self?.send(signal)
        }
        scheduledWorkItems.append(workItem)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func cancelScheduledSignals() {
        scheduledWorkItems.forEach { $0.cancel() }
        scheduledWorkItems.removeAll()
    }
}
