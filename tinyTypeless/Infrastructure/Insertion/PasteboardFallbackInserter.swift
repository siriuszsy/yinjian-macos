import AppKit
import Foundation

final class PasteboardFallbackInserter: TextInserter {
    private let executor: SyntheticPasteExecutor

    init(executor: SyntheticPasteExecutor) {
        self.executor = executor
    }

    func insert(
        _ text: String,
        into context: FocusedContext
    ) throws -> InsertionResult {
        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        do {
            guard activateTargetApplicationIfNeeded(context) else {
                restorePasteboard(after: 0, previousString: previousString)

                return InsertionResult(
                    success: false,
                    usedFallback: true,
                    failureReason: "无法把焦点切回目标应用。"
                )
            }

            refocusTargetElementIfPossible(context)
            try executor.executePasteShortcut()
            restorePasteboard(after: 0.25, previousString: previousString)

            return InsertionResult(
                success: true,
                usedFallback: true,
                failureReason: nil
            )
        } catch {
            restorePasteboard(after: 0, previousString: previousString)

            return InsertionResult(
                success: false,
                usedFallback: true,
                failureReason: error.localizedDescription
            )
        }
    }

    private func activateTargetApplicationIfNeeded(_ context: FocusedContext) -> Bool {
        guard let processIdentifier = context.processIdentifier,
              let application = NSRunningApplication(processIdentifier: processIdentifier)
        else {
            return true
        }

        let activate = {
            application.activate(options: [.activateIgnoringOtherApps])
        }

        if Thread.isMainThread {
            activate()
        } else {
            DispatchQueue.main.sync(execute: activate)
        }

        Thread.sleep(forTimeInterval: 0.14)

        return NSWorkspace.shared.frontmostApplication?.processIdentifier == processIdentifier
    }

    private func refocusTargetElementIfPossible(_ context: FocusedContext) {
        guard let element = context.focusedElement?.element else {
            return
        }

        _ = AXUIElementSetAttributeValue(
            element,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        )
        Thread.sleep(forTimeInterval: 0.05)
    }

    private func restorePasteboard(after delay: TimeInterval, previousString: String?) {
        let restore = {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            if let previousString {
                pasteboard.setString(previousString, forType: .string)
            }
        }

        if delay == 0 {
            restore()
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: restore)
    }
}
