import Foundation

@MainActor
final class AppBootstrap {
    func buildEnvironment() throws -> AppEnvironment {
        let paths = FileSystemPaths(appName: BuildInfo.appName)
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
        let apiKeyStore = FileAPIKeyStore(fileURL: paths.apiKeyFallbackURL)
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
        let asrService = AliyunASRService(httpClient: httpClient, apiKeyStore: apiKeyStore)
        let cleanupService = AliyunCleanupService(
            httpClient: httpClient,
            apiKeyStore: apiKeyStore,
            promptBuilder: promptBuilder
        )
        let hudController = AppKitStatusHUDController()
        let clock = SystemClock()

        let orchestrator = DictationOrchestrator(
            triggerEngine: triggerEngine,
            recordingEngine: recordingEngine,
            asrService: asrService,
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
