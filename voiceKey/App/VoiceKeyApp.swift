import SwiftUI

@main
struct VoiceKeyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            Text("\(BuildInfo.displayName) 设置")
                .frame(width: 320, height: 200)
        }
    }
}
