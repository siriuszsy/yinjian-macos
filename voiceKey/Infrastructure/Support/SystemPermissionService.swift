import AVFoundation
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

final class SystemPermissionService: PermissionService {
    func currentStatus() -> SystemPermissionStatus {
        SystemPermissionStatus(
            inputMonitoring: CGPreflightListenEventAccess() ? .granted : .needsSetup,
            accessibility: AXIsProcessTrusted() ? .granted : .needsSetup,
            microphone: microphoneState
        )
    }

    func requestInputMonitoringAccess() -> Bool {
        if CGPreflightListenEventAccess() {
            return true
        }

        return CGRequestListenEventAccess()
    }

    func requestAccessibilityAccess() -> Bool {
        if AXIsProcessTrusted() {
            return true
        }

        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func requestMicrophoneAccess(completion: @escaping @Sendable (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                completion(granted)
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }

    func openSystemSettings(for permission: SystemPermissionKind) -> Bool {
        let urls = preferenceURLs(for: permission)

        for url in urls {
            if NSWorkspace.shared.open(url) {
                return true
            }
        }

        return false
    }

    private var microphoneState: PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .granted
        case .notDetermined, .denied, .restricted:
            return .needsSetup
        @unknown default:
            return .needsSetup
        }
    }

    private func preferenceURLs(for permission: SystemPermissionKind) -> [URL] {
        let rawValues: [String]

        switch permission {
        case .inputMonitoring:
            rawValues = [
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
                "x-apple.systempreferences:com.apple.preference.security?Privacy"
            ]
        case .accessibility:
            rawValues = [
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
                "x-apple.systempreferences:com.apple.preference.security?Privacy"
            ]
        case .microphone:
            rawValues = [
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
                "x-apple.systempreferences:com.apple.preference.security?Privacy"
            ]
        }

        return rawValues.compactMap(URL.init(string:))
    }
}
