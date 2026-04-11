import Foundation

enum ErrorMapper {
    static func userFacingMessage(from error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
