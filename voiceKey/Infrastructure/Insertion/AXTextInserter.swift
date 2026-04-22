import ApplicationServices
import Foundation
import OSLog

final class AXTextInserter: TextInserter {
    private let logger = Logger(subsystem: BuildInfo.bundleIdentifier, category: "Insertion")

    func insert(
        _ text: String,
        into context: FocusedContext
    ) throws -> InsertionResult {
        guard AXIsProcessTrusted() else {
            logger.error("AX direct insert blocked: accessibility permission missing. targetApp=\(context.applicationName, privacy: .public)")
            return InsertionResult(
                success: false,
                usedFallback: false,
                failureReason: "需要先授予辅助功能权限。"
            )
        }

        guard let element = focusedElement(from: context) else {
            logger.error("AX direct insert failed: no focused element. targetApp=\(context.applicationName, privacy: .public)")
            return InsertionResult(
                success: false,
                usedFallback: false,
                failureReason: "没找到当前光标所在的输入框。"
            )
        }

        let previousValue = stringValue(of: element)

        if let expectedValue = replaceSelection(with: text, in: element),
           verifyWrite(
            insertedText: text,
            previousValue: previousValue,
            expectedValue: expectedValue,
            in: element
           ) {
            logger.notice("AX direct insert succeeded via value replacement. targetApp=\(context.applicationName, privacy: .public)")
            return InsertionResult(
                success: true,
                usedFallback: false,
                failureReason: nil
            )
        }

        if AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        ) == .success,
           verifyWrite(
            insertedText: text,
            previousValue: previousValue,
            expectedValue: nil,
            in: element
           ) {
            logger.notice("AX direct insert succeeded via selected text replacement. targetApp=\(context.applicationName, privacy: .public)")
            return InsertionResult(
                success: true,
                usedFallback: false,
                failureReason: nil
            )
        }

        logger.error("AX direct insert failed: unsupported input element. targetApp=\(context.applicationName, privacy: .public)")
        return InsertionResult(
            success: false,
            usedFallback: false,
            failureReason: "当前输入框不支持直接写入。"
        )
    }

    private func focusedElement(from context: FocusedContext) -> AXUIElement? {
        if let lockedElement = context.focusedElement?.element {
            return lockedElement
        }

        let systemWide = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &value
        )

        guard status == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }

        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private func replaceSelection(with insertedText: String, in element: AXUIElement) -> String? {
        guard let currentValue = stringValue(of: element) else {
            return nil
        }

        let selectedRange = selectedTextRange(of: element) ?? CFRange(
            location: (currentValue as NSString).length,
            length: 0
        )

        let currentNSString = currentValue as NSString
        let safeRange = NSRange(
            location: max(0, min(selectedRange.location, currentNSString.length)),
            length: max(0, min(selectedRange.length, currentNSString.length - max(0, min(selectedRange.location, currentNSString.length))))
        )

        let newValue = currentNSString.replacingCharacters(in: safeRange, with: insertedText)
        let setValueStatus = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            newValue as CFTypeRef
        )

        guard setValueStatus == .success else {
            return nil
        }

        let caretLocation = safeRange.location + (insertedText as NSString).length
        var newRange = CFRange(location: caretLocation, length: 0)
        if let axRange = AXValueCreate(.cfRange, &newRange) {
            _ = AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                axRange
            )
        }

        return newValue
    }

    private func stringValue(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &value
        )

        guard status == .success else {
            return nil
        }

        if let string = value as? String {
            return string
        }

        if let attributed = value as? NSAttributedString {
            return attributed.string
        }

        return nil
    }

    private func selectedText(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &value
        )

        guard status == .success else {
            return nil
        }

        return value as? String
    }

    private func selectedTextRange(of element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        )

        guard status == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }

        let axValue = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange else {
            return nil
        }

        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else {
            return nil
        }

        return range
    }

    private func verifyWrite(
        insertedText: String,
        previousValue: String?,
        expectedValue: String?,
        in element: AXUIElement
    ) -> Bool {
        Thread.sleep(forTimeInterval: 0.04)

        if let actualValue = stringValue(of: element) {
            if let expectedValue, actualValue == expectedValue {
                return true
            }

            if actualValue != previousValue, actualValue.contains(insertedText) {
                return true
            }
        }

        if let selectedText = selectedText(of: element), selectedText == insertedText {
            return true
        }

        return false
    }
}
