import Foundation

protocol TriggerEngine: AnyObject {
    var delegate: TriggerEngineDelegate? { get set }
    func start() throws
    func stop()
    func updateTriggerKey(_ key: TriggerKey) throws
}

protocol TriggerEngineDelegate: AnyObject {
    func triggerDidPressDown(at timestamp: TimeInterval)
    func triggerDidRelease(at timestamp: TimeInterval)
}

enum TriggerKey: String, Codable, Sendable {
    case commandSemicolon
    case rightOption
    case fn

    var displayName: String {
        switch self {
        case .commandSemicolon:
            return "⌘ + ;"
        case .rightOption:
            return "右侧 ⌥ 键"
        case .fn:
            return "功能键 Fn"
        }
    }

    var requiresInputMonitoring: Bool {
        switch self {
        case .commandSemicolon:
            return false
        case .rightOption, .fn:
            return true
        }
    }
}
