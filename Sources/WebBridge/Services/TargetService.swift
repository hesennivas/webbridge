import Foundation

/// Fetches CDP target lists over the forwarded HTTP endpoint. Shared by Android and iOS.
enum TargetService {
    private struct RawTarget: Decodable {
        let id: String?
        let title: String?
        let url: String?
        let type: String?
        let webSocketDebuggerUrl: String?
        let devtoolsFrontendUrl: String?
        let faviconUrl: String?
        let description: String?
    }

    private struct Version: Decodable {
        let Browser: String?
        let webSocketDebuggerUrl: String?
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    static func engine(port: Int) async -> String {
        guard let url = URL(string: "http://127.0.0.1:\(port)/json/version"),
              let (data, _) = try? await session.data(from: url),
              let version = try? JSONDecoder().decode(Version.self, from: data),
              let browser = version.Browser else { return "WebView" }
        return browser.replacingOccurrences(of: "/", with: " ")
    }

    static func targets(port: Int,
                        deviceID: String,
                        engine: String,
                        appPackage: String?,
                        appLabel: String?,
                        canOpenInSafari: Bool) async -> [Target] {
        guard let url = URL(string: "http://127.0.0.1:\(port)/json/list"),
              let (data, _) = try? await session.data(from: url) else { return [] }
        return parseTargets(data, port: port, deviceID: deviceID, engine: engine,
                            appPackage: appPackage, appLabel: appLabel, canOpenInSafari: canOpenInSafari)
    }

    /// Decodes a CDP `/json/list` payload into targets. Split out from the HTTP fetch so the
    /// parsing (notably the iOS `id` fallback) is unit-testable against captured payloads.
    static func parseTargets(_ data: Data,
                             port: Int,
                             deviceID: String,
                             engine: String,
                             appPackage: String?,
                             appLabel: String?,
                             canOpenInSafari: Bool) -> [Target] {
        guard let raw = try? JSONDecoder().decode([RawTarget].self, from: data) else { return [] }

        return raw.compactMap { item in
            guard let ws = item.webSocketDebuggerUrl else { return nil }
            // Chrome/Android include a top-level `id`; ios_webkit_debug_proxy does not. The
            // page id is the trailing path component of the debugger URL (…/devtools/page/3).
            // Without this fallback every iOS target was silently dropped here.
            guard let cdpId = item.id ?? pageID(fromWebSocketURL: ws) else { return nil }
            return Target(
                id: "\(deviceID)#\(cdpId)",
                cdpId: cdpId,
                deviceID: deviceID,
                title: item.title ?? "",
                url: item.url ?? "",
                type: item.type ?? "page",
                webSocketDebuggerURL: rewriteHost(ws, port: port),
                devtoolsFrontendURL: item.devtoolsFrontendUrl,
                faviconURL: item.faviconUrl,
                appPackage: appPackage,
                appLabel: appLabel,
                engine: engine,
                localPort: port,
                canOpenInSafari: canOpenInSafari)
        }
    }

    /// Extracts the CDP page id from a debugger WebSocket URL, e.g.
    /// `ws://localhost:9222/devtools/page/3` → `3`. Used when the target list omits `id`.
    private static func pageID(fromWebSocketURL ws: String) -> String? {
        guard let path = URLComponents(string: ws)?.path else { return nil }
        let last = path.split(separator: "/").last.map(String.init)
        return (last?.isEmpty == false) ? last : nil
    }

    /// iwdp and some adb builds emit a device-relative host; pin to the forwarded loopback port.
    private static func rewriteHost(_ ws: String, port: Int) -> String {
        guard var components = URLComponents(string: ws) else { return ws }
        components.host = "127.0.0.1"
        components.port = port
        return components.string ?? ws
    }
}
