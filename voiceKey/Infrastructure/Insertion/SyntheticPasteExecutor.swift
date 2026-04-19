import ApplicationServices
import Carbon.HIToolbox
import Foundation

final class SyntheticPasteExecutor {
    func executePasteShortcut() throws {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let commandDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_Command),
                keyDown: true
              ),
              let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: true
              ),
              let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: false
              ),
              let commandUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_Command),
                keyDown: false
              )
        else {
            throw DictationError.insertionFailed("无法构造粘贴快捷键事件。")
        }

        commandDown.flags = .maskCommand
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        commandDown.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.01)
        keyDown.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.01)
        keyUp.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.01)
        commandUp.post(tap: .cghidEventTap)
    }
}
