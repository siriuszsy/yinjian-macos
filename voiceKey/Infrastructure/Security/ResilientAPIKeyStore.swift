import Foundation

final class ResilientAPIKeyStore: APIKeyStore {
    private let primary: APIKeyStore
    private let fallback: APIKeyStore

    init(primary: APIKeyStore, fallback: APIKeyStore) {
        self.primary = primary
        self.fallback = fallback
    }

    func save(_ key: String) throws {
        do {
            try primary.save(key)
        } catch {
            try fallback.save(key)
        }
    }

    func load() throws -> String {
        do {
            return try primary.load()
        } catch {
            return try fallback.load()
        }
    }
}
