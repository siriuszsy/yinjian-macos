import Foundation

protocol PermissionService: AnyObject {
    func currentStatus() -> SystemPermissionStatus
    @discardableResult
    func requestInputMonitoringAccess() -> Bool
    @discardableResult
    func requestAccessibilityAccess() -> Bool
    func requestMicrophoneAccess(completion: @escaping @Sendable (Bool) -> Void)
    @discardableResult
    func openSystemSettings(for permission: SystemPermissionKind) -> Bool
}
