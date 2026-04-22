import Foundation

@MainActor
final class AppBootstrap {
    func buildEnvironment() throws -> AppEnvironment {
        let paths = FileSystemPaths(appName: BuildInfo.storageName)
        let settingsStore = JSONSettingsStore(paths: paths)
        let loadedSettings = (try? settingsStore.load()) ?? .default
        var settings = sanitizedSettings(loadedSettings)
        if settings != loadedSettings || !settings.cleanupEnabled {
            settings.cleanupEnabled = true
            try? settingsStore.save(settings)
        }
        let apiKeyStore = ResilientAPIKeyStore(
            primary: KeychainAPIKeyStore(service: BuildInfo.bundleIdentifier),
            fallback: FileAPIKeyStore(fileURL: paths.apiKeyFallbackURL)
        )
        let permissionService = SystemPermissionService()
        let sessionLogStore = JSONLSessionLogStore(paths: paths)
        let httpClient = URLSessionHTTPClient()
        let triggerEngine = HybridTriggerEngine(
            initialDictationKey: settings.triggerKey,
            initialTranslationKey: settings.translationTriggerKey
        )
        let audioPrewarmer = AudioSessionPrewarmer()
        let recordingEngine = AVAudioRecordingEngine(
            prewarmer: audioPrewarmer,
            fileWriter: TemporaryAudioFileWriter(paths: paths)
        )
        let contextInspector: ContextInspector
        let textInserter: TextInserter
#if DEBUG
        contextInspector = AXContextInspector(appResolver: FrontmostAppResolver())
        textInserter = AccessibilityAwareTextInserter(
            permissionService: permissionService,
            accessibilityEnabledInserter: CompositeTextInserter(
                primary: AXTextInserter(),
                fallback: PasteboardFallbackInserter(executor: SyntheticPasteExecutor())
            ),
            accessibilityDisabledInserter: ClipboardTextInserter()
        )
#else
        contextInspector = FrontmostContextInspector(appResolver: FrontmostAppResolver())
        textInserter = ClipboardTextInserter()
#endif
        let promptBuilder = CleanupPromptBuilder()
        let offlineASRService = AliyunASRService(httpClient: httpClient, apiKeyStore: apiKeyStore)
        let realtimeASRService = AliyunRealtimeASRService(apiKeyStore: apiKeyStore)
        let asrService = SelectableASRService(
            settingsStore: settingsStore,
            offlineService: offlineASRService,
            realtimeService: realtimeASRService
        )
        let translationService = AliyunTranslationService(
            httpClient: httpClient,
            apiKeyStore: apiKeyStore
        )
        let cleanupService = AliyunCleanupService(
            httpClient: httpClient,
            apiKeyStore: apiKeyStore,
            settingsStore: settingsStore,
            promptBuilder: promptBuilder
        )
        let hudController = AppKitStatusHUDController()
        let clock = SystemClock()

        let orchestrator = DictationOrchestrator(
            triggerEngine: triggerEngine,
            recordingEngine: recordingEngine,
            asrService: asrService,
            translationService: translationService,
            cleanupService: cleanupService,
            contextInspector: contextInspector,
            textInserter: textInserter,
            hudController: hudController,
            sessionLogStore: sessionLogStore,
            clock: clock,
            settingsStore: settingsStore
        )
        let fixedTextInsertionProbe = FixedTextInsertionProbe(
            contextInspector: contextInspector,
            textInserter: textInserter,
            hudController: hudController
        )

        recordingEngine.levelObserver = orchestrator
        recordingEngine.chunkObserver = orchestrator
        triggerEngine.delegate = orchestrator

        return AppEnvironment(
            settingsStore: settingsStore,
            apiKeyStore: apiKeyStore,
            permissionService: permissionService,
            sessionLogStore: sessionLogStore,
            triggerEngine: triggerEngine,
            recordingEngine: recordingEngine,
            asrService: asrService,
            cleanupService: cleanupService,
            contextInspector: contextInspector,
            textInserter: textInserter,
            hudController: hudController,
            orchestrator: orchestrator,
            fixedTextInsertionProbe: fixedTextInsertionProbe
        )
    }

    private func sanitizedSettings(_ settings: AppSettings) -> AppSettings {
        guard settings.triggerKey == settings.translationTriggerKey else {
            return settings
        }

        var sanitized = settings
        sanitized.translationTriggerKey =
            TriggerKey.translationChoices.first(where: { $0 != settings.triggerKey }) ?? .fnControl
        return sanitized
    }
}

final class SelectableASRService: ASRService, @unchecked Sendable {
    private let settingsStore: SettingsStore
    private let offlineService: ASRService
    private let realtimeService: ASRService
    private let logger: OSLogLogger

    init(
        settingsStore: SettingsStore,
        offlineService: ASRService,
        realtimeService: ASRService,
        logger: OSLogLogger = OSLogLogger()
    ) {
        self.settingsStore = settingsStore
        self.offlineService = offlineService
        self.realtimeService = realtimeService
        self.logger = logger
    }

    func transcribe(_ payload: AudioPayload) async throws -> ASRTranscript {
        let asrMode = currentASRMode()
        logger.info("[ASR] Transcribe requested. mode=\(asrMode.rawValue), durationMs=\(payload.durationMs)")
        switch asrMode {
        case .offline:
            return try await offlineService.transcribe(payload)
        case .realtime:
            do {
                return try await realtimeService.transcribe(payload)
            } catch {
                logger.error(
                    "[ASR] Realtime transcription failed, falling back to offline. reason=\(error.localizedDescription)"
                )
                return try await offlineService.transcribe(payload)
            }
        }
    }

    private func currentASRMode() -> ASRMode {
        (try? settingsStore.load().asrMode) ?? .offline
    }
}

extension SelectableASRService: LiveStreamingASRService {
    func beginLiveTranscription(languageCode: String?) async throws -> Bool {
        let asrMode = currentASRMode()
        logger.info("[ASR] Begin live transcription requested. mode=\(asrMode.rawValue)")
        guard asrMode == .realtime,
              let liveService = realtimeService as? any LiveStreamingASRService else {
            return false
        }

        do {
            return try await liveService.beginLiveTranscription(languageCode: languageCode)
        } catch {
            logger.error(
                "[ASR] Realtime live start failed, will fall back to offline. reason=\(error.localizedDescription)"
            )
            throw error
        }
    }

    func appendLiveAudioChunk(_ chunk: AudioChunk) async throws {
        guard currentASRMode() == .realtime,
              let liveService = realtimeService as? any LiveStreamingASRService else {
            return
        }

        try await liveService.appendLiveAudioChunk(chunk)
    }

    func finishLiveTranscription() async throws -> ASRTranscript? {
        guard currentASRMode() == .realtime,
              let liveService = realtimeService as? any LiveStreamingASRService else {
            return nil
        }

        return try await liveService.finishLiveTranscription()
    }

    func cancelLiveTranscription() async {
        guard let liveService = realtimeService as? any LiveStreamingASRService else {
            return
        }

        await liveService.cancelLiveTranscription()
    }
}
