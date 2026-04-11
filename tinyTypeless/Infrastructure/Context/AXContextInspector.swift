import ApplicationServices
import Foundation

final class AXContextInspector: ContextInspector {
    private let appResolver: FrontmostAppResolver

    init(appResolver: FrontmostAppResolver) {
        self.appResolver = appResolver
    }

    func currentContext() throws -> FocusedContext {
        let app = appResolver.resolve()
        let focusedElement = focusedElement()
        let role = focusedElement.flatMap(role(of:))
        let editable = focusedElement.map(isEditable(element:)) ?? false

        return FocusedContext(
            bundleIdentifier: app.bundleIdentifier,
            applicationName: app.applicationName,
            processIdentifier: app.processIdentifier,
            windowTitle: nil,
            elementRole: role,
            isEditable: editable,
            focusedElement: focusedElement.map(FocusedElementReference.init(element:))
        )
    }

    private func focusedElement() -> AXUIElement? {
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

        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func role(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            element,
            kAXRoleAttribute as CFString,
            &value
        )
        guard status == .success else {
            return nil
        }
        return value as? String
    }

    private func isEditable(element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)

        if AXUIElementIsAttributeSettable(
            element,
            kAXValueAttribute as CFString,
            &settable
        ) == .success, settable.boolValue {
            return true
        }

        if AXUIElementIsAttributeSettable(
            element,
            kAXSelectedTextAttribute as CFString,
            &settable
        ) == .success, settable.boolValue {
            return true
        }

        if let role = role(of: element) {
            return role == kAXTextFieldRole as String
                || role == kAXTextAreaRole as String
                || role == kAXComboBoxRole as String
        }

        return false
    }
}
