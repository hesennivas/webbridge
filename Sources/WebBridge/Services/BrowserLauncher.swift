import AppKit

/// Opens a CDP target's DevTools frontend in Chrome. The frontend's WebSocket is pointed at a
/// local relay port (see DevToolsRelay) so it can attach to WebView/Chrome 111+ despite their
/// origin check. Debug traffic stays on 127.0.0.1.
@MainActor
enum BrowserLauncher {
    static var hasChrome: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") != nil
    }

    static func openChromeDevTools(_ target: Target, relay: (port: Int, token: String)?) {
        guard let url = frontendURL(target, wsPort: relay?.port ?? target.localPort, token: relay?.token) else { return }
        if let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.open([url], withApplicationAt: chrome, configuration: config)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    /// Uses the device-provided hosted frontend (revision-matched to the WebView) but rewrites
    /// its `ws=` target to the given port. Falls back to the device-local frontend. `token`
    /// authenticates the relay handshake (see DevToolsRelay); nil when there's no relay.
    private static func frontendURL(_ target: Target, wsPort: Int, token: String?) -> URL? {
        let tokenSuffix = token.map { "?t=\($0)" } ?? ""
        let wsParam = "127.0.0.1:\(wsPort)/devtools/page/\(target.cdpId)\(tokenSuffix)"
        if let hosted = target.devtoolsFrontendURL, let rewritten = rewriteWSParam(hosted, to: wsParam) {
            return rewritten
        }
        return URL(string: "http://127.0.0.1:\(target.localPort)/devtools/inspector.html?ws=\(wsParam)")
    }

    private static func rewriteWSParam(_ urlString: String, to wsParam: String) -> URL? {
        let normalized = urlString.hasPrefix("//") ? "https:\(urlString)" : urlString
        guard let range = normalized.range(of: "ws=") else { return URL(string: normalized) }
        let head = normalized[normalized.startIndex..<range.upperBound]
        let rest = normalized[range.upperBound...]
        let tail = rest.firstIndex(of: "&").map { String(rest[$0...]) } ?? ""
        return URL(string: head + wsParam + tail)
    }

    static func openChromeInspectPage() {
        guard let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") else {
            return
        }
        let script = "tell application \"Google Chrome\"\nactivate\nopen location \"chrome://inspect/#devices\"\nend tell"
        if let apple = NSAppleScript(source: script) {
            var error: NSDictionary?
            apple.executeAndReturnError(&error)
        } else {
            NSWorkspace.shared.open(chrome)
        }
    }
}
