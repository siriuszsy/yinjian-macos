import Foundation
@testable import tinyTypeless

struct FakeTextInserter: TextInserter {
    var result = InsertionResult(success: true, usedFallback: false, failureReason: nil)

    func insert(
        _ text: String,
        into context: FocusedContext
    ) throws -> InsertionResult {
        _ = text
        _ = context
        return result
    }
}
