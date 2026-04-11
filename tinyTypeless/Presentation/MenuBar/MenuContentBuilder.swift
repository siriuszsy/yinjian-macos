import AppKit

struct MenuDebugItem {
    let title: String
    let actionTarget: ClosureMenuAction
}

struct MenuContentBuilder {
    func buildMenu(
        settings: AppSettings,
        settingsTarget: ClosureMenuAction,
        debugItems: [MenuDebugItem]
    ) -> NSMenu {
        let menu = NSMenu()

        let titleItem = NSMenuItem(title: BuildInfo.appName, action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "设置", action: nil, keyEquivalent: ",")
        settingsItem.target = settingsTarget
        settingsItem.action = #selector(ClosureMenuAction.invoke)
        menu.addItem(settingsItem)

        let triggerItem = NSMenuItem(
            title: "触发键：\(settings.triggerKey.displayName)",
            action: nil,
            keyEquivalent: ""
        )
        triggerItem.isEnabled = false
        menu.addItem(triggerItem)

        let runtimeItem = NSMenuItem(
            title: "运行态：悬浮球预览",
            action: nil,
            keyEquivalent: ""
        )
        runtimeItem.isEnabled = false
        menu.addItem(runtimeItem)

        if !debugItems.isEmpty {
            menu.addItem(.separator())

            let debugHeader = NSMenuItem(title: "调试悬浮球", action: nil, keyEquivalent: "")
            debugHeader.isEnabled = false
            menu.addItem(debugHeader)

            for item in debugItems {
                let menuItem = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
                menuItem.target = item.actionTarget
                menuItem.action = #selector(ClosureMenuAction.invoke)
                menu.addItem(menuItem)
            }
        }

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 \(BuildInfo.appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        return menu
    }
}

final class ClosureMenuAction: NSObject {
    private var targetAction: () -> Void

    init(targetAction: @escaping () -> Void) {
        self.targetAction = targetAction
    }

    func replaceAction(_ action: @escaping () -> Void) {
        targetAction = action
    }

    @objc func invoke() {
        targetAction()
    }
}
