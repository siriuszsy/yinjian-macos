import Foundation

final class DictationOrchestrator: TriggerEngineDelegate, RecordingLevelObserving, RecordingChunkObserving, @unchecked Sendable {
    private enum LiveTranscriptionPhase {
        case inactive
        case starting
        case active
    }

    private(set) var state: DictationState = .idle

    private let triggerEngine: TriggerEngine
    private let recordingEngine: RecordingEngine
    private let asrService: ASRService
    private let translationService: TranslationService
    private let cleanupService: CleanupService
    private let contextInspector: ContextInspector
    private let textInserter: TextInserter
    private let hudController: StatusHUDControlling
    private let sessionLogStore: SessionLogStore
    private let clock: Clock
    private let settingsStore: SettingsStore

    private var sessionContext: DictationSessionContext?
    private var metricsTracker = DictationMetricsTracker()
    private var autoDismissWorkItem: DispatchWorkItem?
    private let liveChunkStateQueue = DispatchQueue(label: "voiceKey.dictation.live-transcription")
    private var liveTranscriptionPhase: LiveTranscriptionPhase = .inactive
    private var pendingLiveChunks: [AudioChunk] = []
    private var liveChunkDrainTask: Task<Void, Never>?
    private var liveTranscriptionStartTask: Task<Bool, Error>?

    init(
        triggerEngine: TriggerEngine,
        recordingEngine: RecordingEngine,
        asrService: ASRService,
        translationService: TranslationService,
        cleanupService: CleanupService,
        contextInspector: ContextInspector,
        textInserter: TextInserter,
        hudController: StatusHUDControlling,
        sessionLogStore: SessionLogStore,
        clock: Clock,
        settingsStore: SettingsStore
    ) {
        self.triggerEngine = triggerEngine
        self.recordingEngine = recordingEngine
        self.asrService = asrService
        self.translationService = translationService
        self.cleanupService = cleanupService
        self.contextInspector = contextInspector
        self.textInserter = textInserter
        self.hudController = hudController
        self.sessionLogStore = sessionLogStore
        self.clock = clock
        self.settingsStore = settingsStore
    }

    func start() async throws {
        try triggerEngine.start()
        try await recordingEngine.prepare()
        hudController.render(.idle)
    }

    func triggerDidPressDown(for intent: SessionIntent, at timestamp: TimeInterval) {
        handleTriggerDown(for: intent, at: Date(timeIntervalSince1970: timestamp))
    }

    func triggerDidRelease(for intent: SessionIntent, at timestamp: TimeInterval) {
        handleTriggerUp(for: intent, at: Date(timeIntervalSince1970: timestamp))
    }

    func recordingLevelDidUpdate(normalizedLevel: Float) {
        hudController.updateInputLevel(normalizedLevel)
    }

    func recordingVisualizationDidUpdate(barLevels: [Float], normalizedLevel: Float) {
        hudController.updateVisualization(barLevels: barLevels, level: normalizedLevel)
    }

    func recordingDidProduceAudioChunk(_ chunk: AudioChunk) {
        liveChunkStateQueue.async { [weak self] in
            guard let self else {
                return
            }

            guard self.liveTranscriptionPhase != .inactive else {
                return
            }

            self.pendingLiveChunks.append(chunk)
            self.scheduleLiveChunkDrainLocked()
        }
    }

    private func handleTriggerDown(for intent: SessionIntent, at date: Date) {
        guard case .idle = state else {
            return
        }

        resetLiveTranscriptionState(cancelRemoteSession: false)
        cancelAutoDismiss()
        state = .recording(startedAt: date)
        sessionContext = DictationSessionContext(startedAt: date, intent: intent)
        if let focusedContext = try? contextInspector.currentContext() {
            sessionContext?.focusedContext = focusedContext
        }
        metricsTracker = DictationMetricsTracker()
        metricsTracker.markRecordingStarted(at: date)
        let triggerKey = (try? settingsStore.load().triggerKey) ?? .commandSemicolon
        hudController.render(.listening(intent: intent, triggerLabel: intent.triggerDisplayName(dictationTriggerKey: triggerKey)))

        do {
            try recordingEngine.startRecording()
            beginLiveTranscriptionIfNeeded()
        } catch {
            fail(error)
        }
    }

    private func handleTriggerUp(for intent: SessionIntent, at date: Date) {
        guard case .recording = state,
              sessionContext?.intent == intent else {
            return
        }

        state = .stopping
        metricsTracker.markTriggerReleased(at: date)
        metricsTracker.markRecordingStopped(at: date)
        hudController.render(.processing(stage: .finalizingCapture))

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                let audioPayload = try await recordingEngine.stopRecording()
                await process(audioPayload: audioPayload)
            } catch {
                fail(error)
            }
        }
    }

    private func process(audioPayload: AudioPayload) async {
        guard var sessionContext else {
            fail(DictationError.invalidState)
            return
        }

        sessionContext.audioPayload = audioPayload
        self.sessionContext = sessionContext

        do {
            let focusedContext: FocusedContext
            if let storedContext = self.sessionContext?.focusedContext {
                focusedContext = storedContext
            } else {
                focusedContext = try contextInspector.currentContext()
            }
            self.sessionContext?.focusedContext = focusedContext

            state = .asrProcessing
            metricsTracker.markASRStarted(at: clock.now())
            hudController.render(.processing(stage: .transcribingAudio))
            let transcript: ASRTranscript
            if let liveTranscript = try await finishLiveTranscriptionIfAvailable() {
                transcript = liveTranscript
            } else {
                transcript = try await asrService.transcribe(audioPayload)
            }
            metricsTracker.markASRFinished(at: clock.now())
            self.sessionContext?.rawTranscript = transcript

            let finalText: String
            if sessionContext.intent == .translation {
                state = .translationProcessing
                hudController.render(.processing(stage: .translatingText))
                let translatedText = try await translationService.translate(
                    transcript.rawText,
                    options: currentTranslationOptions()
                )
                self.sessionContext?.translatedText = translatedText
                finalText = translatedText
            } else if try settingsStore.load().cleanupEnabled {
                state = .cleanupProcessing
                metricsTracker.markCleanupStarted(at: clock.now())
                hudController.render(.processing(stage: .cleaningTranscript))
                let cleanText = try await cleanupService.cleanup(
                    transcript: transcript,
                    context: CleanupContext(
                        appName: focusedContext.applicationName,
                        bundleIdentifier: focusedContext.bundleIdentifier,
                        preserveMeaning: true,
                        removeFillers: true
                    )
                )
                metricsTracker.markCleanupFinished(at: clock.now())
                self.sessionContext?.cleanText = cleanText
                finalText = cleanText.value
            } else {
                finalText = transcript.rawText
            }

            state = .inserting
            metricsTracker.markInsertionStarted(at: clock.now())
            hudController.render(.processing(stage: .insertingText))
            let insertionResult = try textInserter.insert(finalText, into: focusedContext)
            metricsTracker.markInsertionFinished(at: clock.now())

            if insertionResult.success {
                await finishSuccessfully(result: insertionResult)
            } else {
                fail(DictationError.insertionFailed(insertionResult.failureReason ?? "Unknown insertion failure."))
            }
        } catch {
            if self.sessionContext?.intent == .dictation,
               let transcript = self.sessionContext?.rawTranscript {
                await fallbackInsertRawTranscript(transcript)
            } else {
                fail(error)
            }
        }
    }

    private func currentTranslationOptions() -> TranslationOptions {
        let settings = (try? settingsStore.load()) ?? .default
        let sourceLanguage = settings.translationSourceLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetLanguage = settings.translationTargetLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        return TranslationOptions(
            sourceLanguage: sourceLanguage.isEmpty ? "auto" : sourceLanguage,
            targetLanguage: targetLanguage.isEmpty ? "English" : targetLanguage
        )
    }

    private func fallbackInsertRawTranscript(_ transcript: ASRTranscript) async {
        do {
            guard let focusedContext = self.sessionContext?.focusedContext ?? (try? contextInspector.currentContext()) else {
                throw DictationError.insertionFailed("No focused context available.")
            }

            state = .inserting
            metricsTracker.markInsertionStarted(at: clock.now())
            let insertionResult = try textInserter.insert(transcript.rawText, into: focusedContext)
            metricsTracker.markInsertionFinished(at: clock.now())

            if insertionResult.success {
                await finishSuccessfully(result: insertionResult)
            } else {
                fail(DictationError.insertionFailed(insertionResult.failureReason ?? "Fallback insertion failed."))
            }
        } catch {
            fail(error)
        }
    }

    private func finishSuccessfully(result: InsertionResult) async {
        resetLiveTranscriptionState(cancelRemoteSession: false)
        await logSession(
            inserted: result.success,
            fallbackUsed: result.usedFallback,
            failureReason: result.failureReason
        )

        state = .idle
        sessionContext = nil
        hudController.updateInputLevel(0)
        hudController.render(.idle)
    }

    private func fail(_ error: Error) {
        resetLiveTranscriptionState(cancelRemoteSession: true)
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        state = .failed(message: message)
        switch error {
        case DictationError.microphonePermissionDenied:
            hudController.render(.blocked(reason: .microphonePermission))
        case DictationError.accessibilityPermissionDenied:
            hudController.render(.blocked(reason: .accessibilityPermission))
        case DictationError.triggerUnavailable:
            hudController.render(.blocked(reason: .inputMonitoring))
        default:
            hudController.render(.error(message: message))
        }

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            await logSession(
                inserted: false,
                fallbackUsed: false,
                failureReason: message
            )
            scheduleAutoDismiss()
        }
    }

    private func logSession(
        inserted: Bool,
        fallbackUsed: Bool,
        failureReason: String?
    ) async {
        guard let sessionContext else {
            return
        }

        let record = SessionRecord(
            id: sessionContext.id,
            startedAt: sessionContext.startedAt,
            endedAt: clock.now(),
            focusedApp: sessionContext.focusedContext?.applicationName ?? "Unknown",
            audioFilePath: sessionContext.audioPayload?.fileURL.path,
            rawTranscript: sessionContext.rawTranscript?.rawText,
            cleanText: sessionContext.cleanText?.value,
            inserted: inserted,
            fallbackUsed: fallbackUsed,
            failureReason: failureReason,
            latency: metricsTracker.build()
        )

        await sessionLogStore.append(record)
    }

    private func scheduleAutoDismiss() {
        cancelAutoDismiss()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }

            self.state = .idle
            self.sessionContext = nil
            self.hudController.updateInputLevel(0)
            self.hudController.render(.idle)
        }

        autoDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: workItem)
    }

    private func cancelAutoDismiss() {
        autoDismissWorkItem?.cancel()
        autoDismissWorkItem = nil
    }

    private func beginLiveTranscriptionIfNeeded() {
        guard let liveService = asrService as? any LiveStreamingASRService else {
            return
        }

        liveChunkStateQueue.sync {
            liveTranscriptionPhase = .starting
            pendingLiveChunks.removeAll()
            liveChunkDrainTask = nil
        }

        let startTask = Task {
            try await liveService.beginLiveTranscription(languageCode: nil)
        }
        liveTranscriptionStartTask = startTask

        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let started = try await startTask.value
                if started {
                    self.markLiveTranscriptionActive()
                } else {
                    self.resetLiveTranscriptionState(cancelRemoteSession: false)
                }
            } catch {
                await self.handleLiveTranscriptionFailure(error)
            }
        }
    }

    private func markLiveTranscriptionActive() {
        liveChunkStateQueue.async { [weak self] in
            guard let self else {
                return
            }

            guard self.liveTranscriptionPhase != .inactive else {
                return
            }

            self.liveTranscriptionPhase = .active
            self.scheduleLiveChunkDrainLocked()
        }
    }

    private func scheduleLiveChunkDrainLocked() {
        guard liveTranscriptionPhase == .active else {
            return
        }

        guard liveChunkDrainTask == nil else {
            return
        }

        guard !pendingLiveChunks.isEmpty else {
            return
        }

        guard let liveService = asrService as? any LiveStreamingASRService else {
            return
        }

        liveChunkDrainTask = Task { [weak self] in
            guard let self else {
                return
            }

            while true {
                let nextChunk = self.liveChunkStateQueue.sync { () -> AudioChunk? in
                    guard self.liveTranscriptionPhase == .active,
                          !self.pendingLiveChunks.isEmpty else {
                        self.liveChunkDrainTask = nil
                        return nil
                    }

                    return self.pendingLiveChunks.removeFirst()
                }

                guard let nextChunk else {
                    return
                }

                do {
                    try await liveService.appendLiveAudioChunk(nextChunk)
                } catch {
                    self.liveChunkStateQueue.sync {
                        self.liveTranscriptionPhase = .inactive
                        self.pendingLiveChunks.removeAll()
                        self.liveChunkDrainTask = nil
                    }
                    await self.handleLiveTranscriptionFailure(error)
                    return
                }
            }
        }
    }

    private func finishLiveTranscriptionIfAvailable() async throws -> ASRTranscript? {
        guard let liveService = asrService as? any LiveStreamingASRService,
              let startTask = liveTranscriptionStartTask else {
            return nil
        }

        liveTranscriptionStartTask = nil

        let started: Bool
        do {
            started = try await startTask.value
        } catch {
            resetLiveTranscriptionState(cancelRemoteSession: true)
            return nil
        }

        guard started else {
            resetLiveTranscriptionState(cancelRemoteSession: false)
            return nil
        }

        markLiveTranscriptionActive()
        await waitForLiveChunkDrain()

        do {
            let transcript = try await liveService.finishLiveTranscription()
            resetLiveTranscriptionState(cancelRemoteSession: false)
            return transcript
        } catch {
            resetLiveTranscriptionState(cancelRemoteSession: true)
            return nil
        }
    }

    private func waitForLiveChunkDrain() async {
        while true {
            let drainTask = liveChunkStateQueue.sync { liveChunkDrainTask }
            guard let drainTask else {
                return
            }

            _ = await drainTask.result

            let hasPendingChunks = liveChunkStateQueue.sync {
                !pendingLiveChunks.isEmpty && liveTranscriptionPhase == .active
            }
            guard hasPendingChunks else {
                return
            }

            liveChunkStateQueue.sync { [weak self] in
                self?.scheduleLiveChunkDrainLocked()
            }
        }
    }

    private func resetLiveTranscriptionState(cancelRemoteSession: Bool) {
        liveTranscriptionStartTask?.cancel()
        liveTranscriptionStartTask = nil

        liveChunkStateQueue.sync {
            liveTranscriptionPhase = .inactive
            pendingLiveChunks.removeAll()
            liveChunkDrainTask = nil
        }

        guard cancelRemoteSession,
              let liveService = asrService as? any LiveStreamingASRService else {
            return
        }

        Task {
            await liveService.cancelLiveTranscription()
        }
    }

    private func handleLiveTranscriptionFailure(_ error: Error) async {
        _ = error
        resetLiveTranscriptionState(cancelRemoteSession: true)
    }
}
