import AppKit

struct FrontmostApp {
    let bundleIdentifier: String
    let applicationName: String
    let processIdentifier: pid_t?
}

struct FrontmostAppResolver {
    func resolve() -> FrontmostApp {
        let app = NSWorkspace.shared.frontmostApplication
        return FrontmostApp(
            bundleIdentifier: app?.bundleIdentifier ?? "unknown",
            applicationName: app?.localizedName ?? "Unknown",
            processIdentifier: app?.processIdentifier
        )
    }
}
