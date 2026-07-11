import Foundation

/// Pure parsers for external tool output. Kept free of I/O so they can be unit-tested
/// without hardware.
enum Parsing {

    struct AndroidDeviceLine: Equatable, Sendable {
        let serial: String
        let state: DeviceState
        let model: String?
        let isWireless: Bool
    }

    /// Parses `adb devices -l` output.
    static func androidDevices(_ output: String) -> [AndroidDeviceLine] {
        var result: [AndroidDeviceLine] = []
        for raw in output.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("List of devices") || line.hasPrefix("*") { continue }
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard fields.count >= 2 else { continue }
            let serial = fields[0]
            let state: DeviceState
            switch fields[1] {
            case "device": state = .online
            case "unauthorized": state = .unauthorized
            case "offline": state = .offline
            default: state = .offline
            }
            var model: String?
            for field in fields.dropFirst(2) where field.hasPrefix("model:") {
                model = String(field.dropFirst("model:".count)).replacingOccurrences(of: "_", with: " ")
            }
            let isWireless = serial.contains(":") || serial.contains(".")
            result.append(AndroidDeviceLine(serial: serial, state: state, model: model, isWireless: isWireless))
        }
        return result
    }

    struct DevtoolsSocket: Equatable, Sendable {
        let name: String
        let pid: Int32?
    }

    /// Extracts devtools sockets from `cat /proc/net/unix`.
    static func devtoolsSockets(_ output: String) -> [DevtoolsSocket] {
        var seen = Set<String>()
        var result: [DevtoolsSocket] = []
        for line in output.split(separator: "\n") {
            guard let atIndex = line.firstIndex(of: "@") else { continue }
            let token = line[line.index(after: atIndex)...]
                .prefix { !$0.isWhitespace }
            let name = String(token)
            guard name.contains("devtools_remote"), !seen.contains(name) else { continue }
            seen.insert(name)
            var pid: Int32?
            if let range = name.range(of: "webview_devtools_remote_") {
                pid = Int32(name[range.upperBound...])
            }
            result.append(DevtoolsSocket(name: name, pid: pid))
        }
        return result
    }

    /// Extracts the package name from `/proc/<pid>/cmdline` (NUL-separated argv).
    static func packageFromCmdline(_ output: String) -> String? {
        let cleaned = output.split(whereSeparator: { $0 == "\0" || $0 == "\n" }).first.map(String.init)
        guard let cleaned, !cleaned.isEmpty else { return nil }
        // cmdline is often "com.app:sandboxed_process0" style; keep the base package.
        return cleaned.split(separator: ":").first.map(String.init)
    }

    /// Parses `getprop` output of the form `[key]: [value]`.
    static func getprops(_ output: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in output.split(separator: "\n") {
            guard let separator = line.range(of: "]: [") else { continue }
            let key = line[line.startIndex..<separator.lowerBound].dropFirst() // strip leading [
            var value = line[separator.upperBound...]
            if value.hasSuffix("]") { value = value.dropLast() }
            result[String(key)] = String(value)
        }
        return result
    }

    /// Reads an integer field from `dumpsys` output like `  level: 87`.
    static func dumpsysInt(_ output: String, key: String) -> Int? {
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("\(key):") {
                let value = trimmed.dropFirst("\(key):".count).trimmingCharacters(in: .whitespaces)
                return Int(value)
            }
        }
        return nil
    }

    /// Returns the remainder after a known prefix, e.g. `Physical size: 1080x2400`.
    static func firstMatch(_ output: String, prefix: String) -> String? {
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(prefix) {
                return trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// Extracts the top resumed activity from `dumpsys activity activities`.
    static func foregroundActivity(_ output: String) -> String? {
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.contains("ResumedActivity") || trimmed.contains("topResumedActivity") else { continue }
            if let range = trimmed.range(of: #"[\w.]+/[\w.$]+"#, options: .regularExpression) {
                return String(trimmed[range])
            }
        }
        return nil
    }

    /// Extracts the current WebView provider package/version from `dumpsys webviewupdate`.
    static func webviewProvider(_ output: String) -> String? {
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Current WebView package") {
                if let range = trimmed.range(of: "versionName=") {
                    let tail = trimmed[range.upperBound...].prefix { !$0.isWhitespace && $0 != ")" }
                    let name = trimmed.range(of: "packageName=").map {
                        String(trimmed[$0.upperBound...].prefix { $0 != "," })
                    } ?? "WebView"
                    return "\(name) \(tail)"
                }
                return trimmed
            }
        }
        return nil
    }

    struct LogcatEntry: Equatable, Sendable {
        let time: Double
        let pid: Int
        let level: Character
        let tag: String
        let message: String
    }

    /// parses one `adb logcat -v epoch` line; nil for separators and continuation lines.
    static func logcatLine(_ line: String) -> LogcatEntry? {
        guard let match = line.firstMatch(of: logcatRegex),
              let time = Double(match.1), let pid = Int(match.2),
              let level = match.3.first else { return nil }
        return LogcatEntry(time: time, pid: pid, level: level,
                           tag: String(match.4).trimmingCharacters(in: .whitespaces),
                           message: String(match.5))
    }

    // a literal: a bad pattern fails the build instead of trapping at runtime.
    nonisolated(unsafe) private static let logcatRegex = #/^\s*(\d+\.\d+)\s+(\d+)\s+\d+\s+([VDIWEFS])\s+(.*?):\s?(.*)$/#

    struct IOSSyslogEntry: Equatable, Sendable {
        let process: String
        let level: String
        let message: String
    }

    /// parses one `idevicesyslog` line. a timestamp-prefixed line always yields an entry
    /// (best-effort); anything else (idevicesyslog's own diagnostics) returns nil.
    static func iosSyslogLine(_ line: String) -> IOSSyslogEntry? {
        guard line.range(of: #"^\w{3}\s+\d+\s+\d+:\d+:\d+\s"#, options: .regularExpression) != nil else {
            return nil
        }
        if let match = line.firstMatch(of: iosSyslogRegex) {
            return IOSSyslogEntry(process: String(match.1), level: String(match.2), message: String(match.3))
        }
        // timestamped but an unexpected shape, drop the timestamp/device prefix and keep the rest
        let message = line.replacingOccurrences(
            of: #"^\w{3}\s+\d+\s+\d+:\d+:\d+\s+\S+\s+"#, with: "", options: .regularExpression)
        return IOSSyslogEntry(process: "", level: "", message: message)
    }

    nonisolated(unsafe) private static let iosSyslogRegex = #/^\w{3}\s+\d+\s+[\d:]+\s+.*?\s(\S+)\[\d+\]\s+<(\w+)>:\s?(.*)$/#

    /// Parses `pm list packages -3` into installed third-party apps.
    static func packageList(_ output: String) -> [InstalledApp] {
        output.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("package:") else { return nil }
            let name = String(trimmed.dropFirst("package:".count))
            return name.isEmpty ? nil : InstalledApp(id: name)
        }
        .sorted { $0.package < $1.package }
    }

}
