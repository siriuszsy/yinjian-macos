import SwiftUI

@main
struct TinyTypelessApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            Text("tinyTypeless 设置")
                .frame(width: 320, height: 200)
        }
    }
}
