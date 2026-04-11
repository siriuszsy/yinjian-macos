import Foundation

enum SystemPermissionKind: Sendable {
    case inputMonitoring
    case accessibility
    case microphone
}

enum PermissionState: Equatable, Sendable {
    case granted
    case needsSetup
    case notRequired
    case later

    var title: String {
        switch self {
        case .granted:
            return "已授权"
        case .needsSetup:
            return "待设置"
        case .notRequired:
            return "当前不需要"
        case .later:
            return "后续再开"
        }
    }
}

struct SystemPermissionStatus: Equatable, Sendable {
    var inputMonitoring: PermissionState
    var accessibility: PermissionState
    var microphone: PermissionState
}
