import Foundation

struct ToolPaths: Sendable {
    var adb: String?
    var iwdp: String?
    var syslog: String?

    var hasAdb: Bool { adb != nil }
    var hasIWDP: Bool { iwdp != nil }
    var hasSyslog: Bool { syslog != nil }
}

/// Resolves external CLI dependencies. Because the app is often launched from Finder with a
/// minimal PATH, resolution walks explicit locations (Homebrew, Android SDK) and finally the
/// user's login shell, in addition to any manual override.
enum ToolLocator {
    private static let brewPrefixes = ["/opt/homebrew/bin", "/usr/local/bin"]

    static func resolve(adbOverride: String?, iwdpOverride: String?, syslogOverride: String?) async -> ToolPaths {
        async let adb = locate("adb", override: adbOverride)
        async let iwdp = locate("ios_webkit_debug_proxy", override: iwdpOverride)
        async let syslog = locate("idevicesyslog", override: syslogOverride)
        return await ToolPaths(adb: adb, iwdp: iwdp, syslog: syslog)
    }

    static func locate(_ name: String, override: String?) async -> String? {
        if let override, !override.isEmpty, isExecutable(override) { return override }

        for candidate in candidatePaths(for: name) where isExecutable(candidate) {
            return candidate
        }

        return await loginShellResolve(name)
    }

    private static func candidatePaths(for name: String) -> [String] {
        var paths = brewPrefixes.map { "\($0)/\(name)" }
        if name == "adb" {
            let environment = ProcessInfo.processInfo.environment
            for key in ["ANDROID_HOME", "ANDROID_SDK_ROOT"] {
                if let root = environment[key] { paths.append("\(root)/platform-tools/adb") }
            }
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            paths.append("\(home)/Library/Android/sdk/platform-tools/adb")
        }
        return paths
    }

    /// Falls back to the user's login shell so PATH entries from their profile are honored
    /// even when the app was launched from Finder.
    private static func loginShellResolve(_ name: String) async -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        guard let output = try? await ProcessRunner.output(
            shell, ["-lc", "command -v \(name)"], timeout: .seconds(6)) else { return nil }
        let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return isExecutable(path) ? path : nil
    }

    private static func isExecutable(_ path: String) -> Bool {
        !path.isEmpty && FileManager.default.isExecutableFile(atPath: path)
    }
}
