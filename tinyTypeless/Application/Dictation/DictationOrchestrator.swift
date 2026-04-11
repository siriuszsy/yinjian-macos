import Foundation

final class DictationOrchestrator: TriggerEngineDelegate, RecordingLevelObserving, @unchecked Sendable {
    private(set) var state: DictationState = .idle

    private let triggerEngine: TriggerEngine
    private let recordingEngine: RecordingEngine
    private let asrService: ASRService
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

    init(
        triggerEngine: TriggerEngine,
        recordingEngine: RecordingEngine,
        asrService: ASRService,
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

    func triggerDidPressDown(at timestamp: TimeInterval) {
        handleTriggerDown(at: Date(timeIntervalSince1970: timestamp))
    }

    func triggerDidRelease(at timestamp: TimeInterval) {
        handleTriggerUp(at: Date(timeIntervalSince1970: timestamp))
    }

    func recordingLevelDidUpdate(normalizedLevel: Float) {
        hudController.updateInputLevel(normalizedLevel)
    }

    func recordingVisualizationDidUpdate(barLevels: [Float], normalizedLevel: Float) {
        hudController.updateVisualization(barLevels: barLevels, level: normalizedLevel)
    }

    private func handleTriggerDown(at date: Date) {
        guard case .idle = state else {
            return
        }

        cancelAutoDismiss()
        state = .recording(startedAt: date)
        sessionContext = DictationSessionContext(startedAt: date)
        if let focusedContext = try? contextInspector.currentContext() {
            sessionContext?.focusedContext = focusedContext
        }
        metricsTracker = DictationMetricsTracker()
        metricsTracker.markRecordingStarted(at: date)
        let triggerKey = (try? settingsStore.load().triggerKey) ?? .commandSemicolon
        hudController.render(.listening(triggerKey: triggerKey))

        do {
            try recordingEngine.startRecording()
        } catch {
            fail(error)
        }
    }

    private func handleTriggerUp(at date: Date) {
        guard case .recording = state else {
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
            let transcript = try await asrService.transcribe(audioPayload)
            metricsTracker.markASRFinished(at: clock.now())
            self.sessionContext?.rawTranscript = transcript

            let finalText: String
            if try settingsStore.load().cleanupEnabled {
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
            if let transcript = self.sessionContext?.rawTranscript {
                await fallbackInsertRawTranscript(transcript)
            } else {
                fail(error)
            }
        }
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
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        state = .failed(message: message)
        hudController.render(.error(message: message))

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
}
