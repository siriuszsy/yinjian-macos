import Foundation

struct CleanupContext: Sendable {
    let appName: String
    let bundleIdentifier: String
    let preserveMeaning: Bool
    let removeFillers: Bool
}
