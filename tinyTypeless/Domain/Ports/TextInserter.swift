import Foundation

protocol TextInserter {
    func insert(
        _ text: String,
        into context: FocusedContext
    ) throws -> InsertionResult
}
