import Foundation

/// A single inspectable page: an Android WebView/Chrome tab or an iOS Safari/webview target.
/// Unified across platforms because both surface a CDP-shaped HTTP + WebSocket endpoint.
struct Target: Identifiable, Sendable, Hashable {
    /// Stable app-wide id: deviceID + cdp target id.
    let id: String
    let cdpId: String
    let deviceID: String

    var title: String
    var url: String
    var type: String
    var webSocketDebuggerURL: String
    var devtoolsFrontendURL: String?
    var faviconURL: String?

    /// Owning app, resolved from the devtools socket where possible.
    var appPackage: String?
    var appLabel: String?

    /// Human browser/engine identity, e.g. "Chrome 126", "WebView 126", "Safari".
    var engine: String

    /// Local TCP port the CDP endpoint is reachable on (adb forward or iwdp).
    var localPort: Int

    var canOpenInSafari: Bool

    var isPage: Bool { type == "page" || type.isEmpty }

    var displayTitle: String {
        if !title.isEmpty { return title }
        if let host = URL(string: url)?.host { return host }
        return url.isEmpty ? "Untitled" : url
    }

    /// Stable key for pins and custom labels: survives the CDP id churning on every
    /// reload/reconnect. Uses the URL, or the title for pages that have none.
    var pinIdentity: String { url.isEmpty ? displayTitle : url }

    /// Grouping key for the overview: owning app, or the browser engine for standalone browsers.
    var groupKey: String { appPackage ?? engine }

    var groupLabel: String {
        if let label = appLabel, let pkg = appPackage { return "\(label) · \(pkg)" }
        if let pkg = appPackage { return pkg }
        return engine
    }
}
