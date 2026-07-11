import AppKit
import ApplicationServices

enum SafariOutcome: Sendable {
    case automated
    case guided(menuPath: String)
    case needsPermission(menuPath: String)
    case safariMissing
}

/// Drives Safari's Web Inspector. macOS only allows clicking another app's menus with the
/// Accessibility permission; without it we activate Safari and show the exact menu path.
@MainActor
enum SafariAutomation {

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func promptForTrust() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openInspector(deviceName: String, pageTitle: String) -> SafariOutcome {
        let menuPath = "Develop ▸ \(deviceName) ▸ \(pageTitle)"
        guard activateSafari() else { return .safariMissing }

        guard isTrusted else { return .needsPermission(menuPath: menuPath) }

        return clickDevelopMenu(device: deviceName, page: pageTitle)
            ? .automated
            : .guided(menuPath: menuPath)
    }

    @discardableResult
    private static func activateSafari() -> Bool {
        guard let safari = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari") else {
            return false
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: safari, configuration: config)
        return true
    }

    private static func clickDevelopMenu(device: String, page: String) -> Bool {
        let script = """
        tell application "System Events"
            tell process "Safari"
                set frontmost to true
                click menu item "\(escape(page))" of menu 1 of ¬
                    menu item "\(escape(device))" of menu 1 of ¬
                    menu bar item "Develop" of menu bar 1
            end tell
        end tell
        """
        var error: NSDictionary?
        guard let apple = NSAppleScript(source: script) else { return false }
        apple.executeAndReturnError(&error)
        return error == nil
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
             .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
