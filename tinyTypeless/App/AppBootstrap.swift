import Foundation

@MainActor
final class AppBootstrap {
    func buildEnvironment() throws -> AppEnvironment {
        let paths = FileSystemPaths(appName: BuildInfo.storageName)
        let settingsStore = JSONSettingsStore(paths: paths)
        var settings = (try? settingsStore.load()) ?? .default
        if settings.triggerKey.requiresInputMonitoring {
            settings.triggerKey = .commandSemicolon
            try? settingsStore.save(settings)
        }
        if !settings.cleanupEnabled {
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
        let triggerEngine = HybridTriggerEngine(initialKey: settings.triggerKey)
        let audioPrewarmer = AudioSessionPrewarmer()
        let recordingEngine = AVAudioRecordingEngine(
            prewarmer: audioPrewarmer,
            fileWriter: TemporaryAudioFileWriter(paths: paths)
        )
        let contextInspector = AXContextInspector(appResolver: FrontmostAppResolver())
        let textInserter = CompositeTextInserter(
            primary: AXTextInserter(),
            fallback: PasteboardFallbackInserter(executor: SyntheticPasteExecutor())
        )
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
        let runtimePreviewCoordinator = RuntimeIndicatorPreviewCoordinator(
            triggerEngine: triggerEngine,
            recordingEngine: recordingEngine,
            asrService: asrService,
            hudController: hudController,
            settingsStore: settingsStore,
            sessionLogStore: sessionLogStore,
            clock: clock
        )
        let fixedTextInsertionProbe = FixedTextInsertionProbe(
            contextInspector: contextInspector,
            textInserter: textInserter,
            hudController: hudController,
            clock: clock
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
            runtimePreviewCoordinator: runtimePreviewCoordinator,
            fixedTextInsertionProbe: fixedTextInsertionProbe
        )
    }
}

private final class SelectableASRService: ASRService, @unchecked Sendable {
    private let settingsStore: SettingsStore
    private let offlineService: ASRService
    private let realtimeService: ASRService

    init(
        settingsStore: SettingsStore,
        offlineService: ASRService,
        realtimeService: ASRService
    ) {
        self.settingsStore = settingsStore
        self.offlineService = offlineService
        self.realtimeService = realtimeService
    }

    func transcribe(_ payload: AudioPayload) async throws -> ASRTranscript {
        let asrMode = currentASRMode()
        switch asrMode {
        case .offline:
            return try await offlineService.transcribe(payload)
        case .realtime:
            return try await realtimeService.transcribe(payload)
        }
    }

    private func currentASRMode() -> ASRMode {
        (try? settingsStore.load().asrMode) ?? .offline
    }
}

extension SelectableASRService: LiveStreamingASRService {
    func beginLiveTranscription(languageCode: String?) async throws -> Bool {
        guard currentASRMode() == .realtime,
              let liveService = realtimeService as? any LiveStreamingASRService else {
            return false
        }

        return try await liveService.beginLiveTranscription(languageCode: languageCode)
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
