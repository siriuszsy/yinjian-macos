import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController {
    convenience init<Content: View>(rootView: Content) {
        let controller = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: controller)
        window.title = "\(BuildInfo.appName) 设置"
        window.setContentSize(NSSize(width: 560, height: 620))
        self.init(window: window)
    }
}
