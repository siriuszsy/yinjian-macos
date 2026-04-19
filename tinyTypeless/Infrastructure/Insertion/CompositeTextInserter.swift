import Foundation
import OSLog

final class CompositeTextInserter: TextInserter {
    private let logger = Logger(subsystem: BuildInfo.bundleIdentifier, category: "Insertion")
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

        logger.notice("Primary insert failed, falling back. reason=\(primaryResult.failureReason ?? "unknown", privacy: .public), targetApp=\(context.applicationName, privacy: .public)")
        return try fallback.insert(text, into: context)
    }
}
