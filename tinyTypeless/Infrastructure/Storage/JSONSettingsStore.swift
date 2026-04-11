import Foundation

final class JSONSettingsStore: SettingsStore {
    private let paths: FileSystemPaths
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(paths: FileSystemPaths) {
        self.paths = paths
    }

    func load() throws -> AppSettings {
        try paths.ensureDirectoriesExist()

        guard FileManager.default.fileExists(atPath: paths.settingsURL.path) else {
            try save(.default)
            return .default
        }

        let data = try Data(contentsOf: paths.settingsURL)
        return try decoder.decode(AppSettings.self, from: data)
    }

    func save(_ settings: AppSettings) throws {
        try paths.ensureDirectoriesExist()
        let data = try encoder.encode(settings)
        try data.write(to: paths.settingsURL, options: .atomic)
    }
}
