# voiceKey 类图

最后更新：2026-04-22

这份文档只描述当前仓库主线实现，不描述已经删除的旧触发器实验代码。

当前主线：

- `Fn` 听写
- `Fn + Control` 翻译
- `Fn + Shift` 备选
- `Offline` 默认，`Realtime` 可切换
- 有辅助功能权限时优先直写，无权限时回退到剪贴板

## 核心类图

```mermaid
classDiagram
    direction LR

    class AppBootstrap {
      +buildEnvironment() AppEnvironment
    }

    class AppEnvironment {
      +settingsStore: SettingsStore
      +apiKeyStore: APIKeyStore
      +permissionService: PermissionService
      +sessionLogStore: SessionLogStore
      +triggerEngine: TriggerEngine
      +recordingEngine: RecordingEngine
      +asrService: ASRService
      +cleanupService: CleanupService
      +contextInspector: ContextInspector
      +textInserter: TextInserter
      +hudController: StatusHUDControlling
      +orchestrator: DictationOrchestrator
      +fixedTextInsertionProbe: FixedTextInsertionProbe
    }

    class MenuBarController {
      +openSettings()
    }

    class SettingsViewModel {
      +settings: AppSettings
      +save()
      +applyASRModeChange()
      +saveAPIKey()
      +requestAccessibility()
      +requestMicrophone()
    }

    class AppSettings {
      +triggerKey: TriggerKey
      +translationTriggerKey: TriggerKey
      +asrMode: ASRMode
      +cleanupEnabled: Bool
      +fallbackPasteEnabled: Bool
      +translationSourceLanguage: String
      +translationTargetLanguage: String
    }

    class HybridTriggerEngine {
      +delegate: TriggerEngineDelegate
      +start()
      +stop()
      +updateTriggerKey(key)
      +updateTriggerConfiguration(dictationKey, translationKey)
    }

    class CarbonHotKeyTriggerEngine {
      +start()
      +stop()
      +updateTriggerKey(key)
    }

    class ModifierChordTriggerEngine {
      +start()
      +stop()
      +updateBindings(dictationTrigger, translationTrigger)
    }

    class DictationOrchestrator {
      +state: DictationState
      +start()
      +triggerDidPressDown(intent, timestamp)
      +triggerDidRelease(intent, timestamp)
      +recordingDidProduceAudioChunk(chunk)
    }

    class AVAudioRecordingEngine {
      +prepare()
      +startRecording()
      +stopRecording() AudioPayload
    }

    class SelectableASRService {
      +transcribe(payload) ASRTranscript
      +beginLiveTranscription(languageCode) Bool
      +appendLiveAudioChunk(chunk)
      +finishLiveTranscription() ASRTranscript
      +cancelLiveTranscription()
    }

    class AliyunASRService {
      +transcribe(payload) ASRTranscript
    }

    class AliyunRealtimeASRService {
      +transcribe(payload) ASRTranscript
      +startSession(languageCode)
    }

    class AliyunCleanupService {
      +cleanup(transcript, context) CleanText
    }

    class AliyunTranslationService {
      +translate(text, options) String
    }

    class AccessibilityAwareTextInserter {
      +insert(text, context) InsertionResult
    }

    class CompositeTextInserter {
      +insert(text, context) InsertionResult
    }

    class AXTextInserter {
      +insert(text, context) InsertionResult
    }

    class PasteboardFallbackInserter {
      +insert(text, context) InsertionResult
    }

    class ClipboardTextInserter {
      +insert(text, context) InsertionResult
    }

    class JSONSettingsStore {
      +load() AppSettings
      +save(settings)
    }

    class JSONLSessionLogStore {
      +append(record)
    }

    class SystemPermissionService {
      +currentStatus() SystemPermissionStatus
      +requestAccessibilityAccess() Bool
      +requestMicrophoneAccess(completion)
    }

    AppBootstrap --> AppEnvironment
    AppBootstrap --> HybridTriggerEngine
    AppBootstrap --> AVAudioRecordingEngine
    AppBootstrap --> SelectableASRService
    AppBootstrap --> AliyunCleanupService
    AppBootstrap --> AliyunTranslationService
    AppBootstrap --> AccessibilityAwareTextInserter
    AppBootstrap --> JSONSettingsStore
    AppBootstrap --> JSONLSessionLogStore
    AppBootstrap --> SystemPermissionService

    MenuBarController --> AppEnvironment
    MenuBarController --> SettingsViewModel
    SettingsViewModel --> AppSettings
    SettingsViewModel --> JSONSettingsStore
    SettingsViewModel --> SystemPermissionService

    HybridTriggerEngine *-- CarbonHotKeyTriggerEngine
    HybridTriggerEngine *-- ModifierChordTriggerEngine
    HybridTriggerEngine --> DictationOrchestrator : delegate

    AVAudioRecordingEngine --> DictationOrchestrator : level/chunk callbacks

    DictationOrchestrator --> HybridTriggerEngine
    DictationOrchestrator --> AVAudioRecordingEngine
    DictationOrchestrator --> SelectableASRService
    DictationOrchestrator --> AliyunCleanupService
    DictationOrchestrator --> AliyunTranslationService
    DictationOrchestrator --> AccessibilityAwareTextInserter
    DictationOrchestrator --> JSONSettingsStore
    DictationOrchestrator --> JSONLSessionLogStore

    SelectableASRService *-- AliyunASRService
    SelectableASRService *-- AliyunRealtimeASRService

    AccessibilityAwareTextInserter *-- CompositeTextInserter
    AccessibilityAwareTextInserter *-- ClipboardTextInserter
    CompositeTextInserter *-- AXTextInserter
    CompositeTextInserter *-- PasteboardFallbackInserter
```

## 读图要点

- `AppBootstrap` 是唯一的装配入口，所有运行时依赖都在这里接起来。
- `HybridTriggerEngine` 统一管理两条触发路径：
  一条是 `CarbonHotKeyTriggerEngine`，用于 `⌘ + ;` 这类 Carbon 可注册热键。
  另一条是 `ModifierChordTriggerEngine`，用于 `Fn`、`Fn + Control`、`Fn + Shift`。
- `DictationOrchestrator` 是主流程核心。它不关心具体热键实现，只消费 `press/release` 语义，并驱动录音、识别、翻译、清理、写入和日志。
- `SelectableASRService` 把 `offline` 和 `realtime` 两条识别链路收口到一个接口里，并负责在单次转写失败时回退到 `offline`。
- `AccessibilityAwareTextInserter` 只做一个判断：
  有辅助功能权限时走 `AX + paste fallback`，没有时直接落到剪贴板。
