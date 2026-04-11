import Foundation

final class CompositeTextInserter: TextInserter {
    private let primary: TextInserter
    private let fallback: TextInserter?

    init(primary: TextInserter, fallback: TextInserter?) {
        self.primary = primary
        self.fallback = fallback
    }

    func insert(
        _ text: String,
        into context: FocusedContext
    ) throws -> InsertionResult {
        let primaryResult = try primary.insert(text, into: context)
        if primaryResult.success {
            return primaryResult
        }

        guard let fallback else {
            return primaryResult
        }

        return try fallback.insert(text, into: context)
    }
}
