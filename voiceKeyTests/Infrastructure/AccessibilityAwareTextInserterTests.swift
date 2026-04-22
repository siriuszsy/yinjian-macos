import XCTest
@testable import voiceKey

final class AccessibilityAwareTextInserterTests: XCTestCase {
    func testUsesClipboardFallbackWhenAccessibilityIsMissing() throws {
        let permissionService = StubPermissionService(accessibility: .needsSetup)
        let directInserter = RecordingTextInserter(
            result: InsertionResult(success: true, usedFallback: false, failureReason: nil)
        )
        let clipboardInserter = RecordingTextInserter(
            result: InsertionResult(success: true, usedFallback: true, failureReason: nil)
        )
        let inserter = AccessibilityAwareTextInserter(
            permissionService: permissionService,
            accessibilityEnabledInserter: directInserter,
            accessibilityDisabledInserter: clipboardInserter
        )

        let result = try inserter.insert("hello", into: sampleContext())

        XCTAssertTrue(result.success)
        XCTAssertTrue(result.usedFallback)
        XCTAssertEqual(directInserter.callCount, 0)
        XCTAssertEqual(clipboardInserter.callCount, 1)
    }

    func testUsesDirectFlowWhenAccessibilityIsGranted() throws {
        let permissionService = StubPermissionService(accessibility: .granted)
        let directInserter = RecordingTextInserter(
            result: InsertionResult(success: true, usedFallback: false, failureReason: nil)
        )
        let clipboardInserter = RecordingTextInserter(
            result: InsertionResult(success: true, usedFallback: true, failureReason: nil)
        )
        let inserter = AccessibilityAwareTextInserter(
            permissionService: permissionService,
            accessibilityEnabledInserter: directInserter,
            accessibilityDisabledInserter: clipboardInserter
        )

        let result = try inserter.insert("hello", into: sampleContext())

        XCTAssertTrue(result.success)
        XCTAssertFalse(result.usedFallback)
        XCTAssertEqual(directInserter.callCount, 1)
        XCTAssertEqual(clipboardInserter.callCount, 0)
    }

    private func sampleContext() -> FocusedContext {
        FocusedContext(
            bundleIdentifier: "com.example.app",
            applicationName: "Example",
            processIdentifier: nil,
            windowTitle: nil,
            elementRole: nil,
            isEditable: true,
            focusedElement: nil
        )
    }
}

private final class StubPermissionService: PermissionService {
    private let accessibility: PermissionState

    init(accessibility: PermissionState) {
        self.accessibility = accessibility
    }

    func currentStatus() -> SystemPermissionStatus {
        SystemPermissionStatus(
            inputMonitoring: .notRequired,
            accessibility: accessibility,
            microphone: .granted
        )
    }

    func requestAccessibilityAccess() -> Bool {
        accessibility == .granted
    }

    func requestMicrophoneAccess(completion: @escaping @Sendable (Bool) -> Void) {
        completion(true)
    }

    func openSystemSettings(for permission: SystemPermissionKind) -> Bool {
        _ = permission
        return true
    }
}

private final class RecordingTextInserter: TextInserter {
    private(set) var callCount = 0
    private let result: InsertionResult

    init(result: InsertionResult) {
        self.result = result
    }

    func insert(
        _ text: String,
        into context: FocusedContext
    ) throws -> InsertionResult {
        _ = text
        _ = context
        callCount += 1
        return result
    }
}
