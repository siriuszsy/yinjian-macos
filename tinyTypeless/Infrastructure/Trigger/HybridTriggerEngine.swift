import Carbon
import Foundation
import OSLog

struct FixedHotKeyShortcut: Sendable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let displayName: String
}

enum TranslationHotKeyCatalog {
    static let primary = FixedHotKeyShortcut(
        keyCode: 41,
        modifiers: UInt32(cmdKey | controlKey),
        displayName: "⌃⌘;"
    )

    static let all = [primary]
}

final class HybridTriggerEngine: TriggerEngine, @unchecked Sendable {
    private let logger = Logger(subsystem: BuildInfo.bundleIdentifier, category: "Trigger")

    weak var delegate: TriggerEngineDelegate? {
        didSet {
            dictationCarbonEngine.delegate = delegate
            cgEventTapEngine.delegate = delegate
            translationCarbonEngines.forEach { $0.delegate = delegate }
        }
    }

    private var triggerKey: TriggerKey
    private var isRunning = false
    private let dictationCarbonEngine: CarbonHotKeyTriggerEngine
    private let cgEventTapEngine: CGEventTapTriggerEngine
    private let translationCarbonEngines: [CarbonHotKeyTriggerEngine]

    init(initialKey: TriggerKey) {
        self.triggerKey = initialKey
        self.dictationCarbonEngine = CarbonHotKeyTriggerEngine(initialKey: initialKey, hotKeyIDValue: 1)
        self.cgEventTapEngine = CGEventTapTriggerEngine(initialKey: initialKey)
        self.translationCarbonEngines = TranslationHotKeyCatalog.all.enumerated().map { index, hotKey in
            CarbonHotKeyTriggerEngine(
                fixedHotKey: hotKey,
                intent: .translation,
                hotKeyIDValue: UInt32(100 + index)
            )
        }
    }

    func start() throws {
        do {
            try startTranslationHotKeys()
            try activeEngine.start()
        } catch {
            stopTranslationHotKeys()
            throw error
        }
        isRunning = true
    }

    func stop() {
        activeEngine.stop()
        stopTranslationHotKeys()
        isRunning = false
    }

    func updateTriggerKey(_ key: TriggerKey) throws {
        let wasRunning = isRunning
        if wasRunning {
            activeEngine.stop()
        }

        triggerKey = key
        try dictationCarbonEngine.updateTriggerKey(key)
        try cgEventTapEngine.updateTriggerKey(key)

        if wasRunning {
            try activeEngine.start()
        }
    }

    private var activeEngine: TriggerEngine {
        switch triggerKey {
        case .commandSemicolon:
            return dictationCarbonEngine
        case .rightOption, .fn:
            return cgEventTapEngine
        }
    }

    private func startTranslationHotKeys() throws {
        var registeredShortcuts: [String] = []
        var failedShortcuts: [String] = []

        for (engine, shortcut) in zip(translationCarbonEngines, TranslationHotKeyCatalog.all) {
            do {
                try engine.start()
                registeredShortcuts.append(shortcut.displayName)
                logger.notice("Registered translation hotkey: \(shortcut.displayName, privacy: .public)")
            } catch {
                failedShortcuts.append("\(shortcut.displayName): \(error.localizedDescription)")
                logger.error("Failed to register translation hotkey \(shortcut.displayName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        if registeredShortcuts.isEmpty {
            logger.error("No translation hotkeys registered. Translation trigger is unavailable in this run.")
        } else if !failedShortcuts.isEmpty {
            let registeredSummary = registeredShortcuts.joined(separator: ", ")
            let failedSummary = failedShortcuts.joined(separator: " | ")
            logger.warning("Translation hotkeys partially available. Registered: \(registeredSummary, privacy: .public). Failed: \(failedSummary, privacy: .public)")
        }
    }

    private func stopTranslationHotKeys() {
        translationCarbonEngines.forEach { $0.stop() }
    }
}
