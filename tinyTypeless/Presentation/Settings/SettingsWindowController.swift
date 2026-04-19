import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController {
    convenience init<Content: View>(rootView: Content) {
        let controller = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: controller)
        window.title = "\(BuildInfo.displayName) 设置"
        window.setContentSize(NSSize(width: 680, height: 760))
        self.init(window: window)
    }
}
