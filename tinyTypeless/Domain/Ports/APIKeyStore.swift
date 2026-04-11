import Foundation

protocol APIKeyStore {
    func save(_ key: String) throws
    func load() throws -> String
}
