import Foundation

protocol ContextInspector {
    func currentContext() throws -> FocusedContext
}
