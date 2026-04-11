import Foundation
import ApplicationServices

final class FocusedElementReference: @unchecked Sendable {
    let element: AXUIElement

    init(element: AXUIElement) {
        self.element = element
    }
}

struct FocusedContext: Sendable {
    let bundleIdentifier: String
    let applicationName: String
    let processIdentifier: pid_t?
    let windowTitle: String?
    let elementRole: String?
    let isEditable: Bool
    let focusedElement: FocusedElementReference?
}
