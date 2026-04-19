import Foundation

protocol SettingsStore {
    func load() throws -> AppSettings
    func save(_ settings: AppSettings) throws
}
