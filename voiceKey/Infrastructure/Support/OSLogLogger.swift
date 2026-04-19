import Foundation
import OSLog

final class OSLogLogger {
    private let logger = Logger(subsystem: BuildInfo.bundleIdentifier, category: "voiceKey")

    func info(_ message: String) {
        logger.info("\(message)")
    }

    func error(_ message: String) {
        logger.error("\(message)")
    }
}
