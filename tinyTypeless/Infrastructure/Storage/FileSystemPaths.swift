import Foundation

struct FileSystemPaths {
    let rootDirectory: URL
    let settingsURL: URL
    let sessionsLogURL: URL
    let apiKeyFallbackURL: URL
    let temporaryDirectory: URL

    init(appName: String) {
        let baseDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(appName, isDirectory: true)

        rootDirectory = baseDirectory
        settingsURL = baseDirectory.appendingPathComponent("settings.json")
        sessionsLogURL = baseDirectory.appendingPathComponent("sessions.jsonl")
        apiKeyFallbackURL = baseDirectory.appendingPathComponent("dashscope-api-key.txt")
        temporaryDirectory = baseDirectory.appendingPathComponent("tmp", isDirectory: true)
    }

    func ensureDirectoriesExist() throws {
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }
}
