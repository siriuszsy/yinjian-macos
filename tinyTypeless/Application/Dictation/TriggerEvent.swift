import Foundation

enum TriggerEvent: Sendable {
    case pressed(Date)
    case released(Date)
}
