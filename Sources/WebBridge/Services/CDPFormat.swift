import Foundation

/// Turns raw Chrome DevTools Protocol JSON fragments into display strings.
enum CDPFormat {

    static func consoleArgs(_ args: [[String: Any]]) -> String {
        args.map(remoteObject).joined(separator: " ")
    }

    static func remoteObject(_ object: [String: Any]) -> String {
        if let value = object["value"] { return jsonString(value) }
        if let description = object["description"] as? String { return description }
        if let type = object["type"] as? String {
            if type == "undefined" { return "undefined" }
            if let subtype = object["subtype"] as? String { return subtype }
            return type
        }
        return ""
    }

    static func exceptionText(_ details: [String: Any]) -> String {
        if let exception = details["exception"] as? [String: Any] {
            let described = remoteObject(exception)
            if !described.isEmpty { return described }
        }
        return details["text"] as? String ?? "Uncaught exception"
    }

    static func stack(_ stackTrace: [String: Any]?) -> [String] {
        guard let frames = stackTrace?["callFrames"] as? [[String: Any]] else { return [] }
        return frames.prefix(8).map { frame in
            let name = (frame["functionName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "(anonymous)"
            let source = shortSource(frame["url"] as? String ?? "", line: line(frame["lineNumber"]))
            return "at \(name) (\(source))"
        }
    }

    static func topSource(_ stackTrace: [String: Any]?) -> String? {
        guard let frame = (stackTrace?["callFrames"] as? [[String: Any]])?.first else { return nil }
        let source = shortSource(frame["url"] as? String ?? "", line: line(frame["lineNumber"]))
        return source.isEmpty ? nil : source
    }

    static func shortSource(_ url: String, line: Int?) -> String {
        var name = url
        if let parsed = URL(string: url), !parsed.lastPathComponent.isEmpty, parsed.lastPathComponent != "/" {
            name = parsed.lastPathComponent
        }
        if name.isEmpty { return line.map { "line \($0)" } ?? "" }
        if let line { return "\(name):\(line)" }
        return name
    }

    static func consoleLevel(_ type: String) -> ConsoleLevel {
        switch type {
        case "error", "assert": return .error
        case "warning": return .warning
        case "info": return .info
        case "debug", "count", "timeEnd": return .debug
        default: return .log
        }
    }

    static func logLevel(_ level: String) -> ConsoleLevel {
        switch level {
        case "error": return .error
        case "warning": return .warning
        case "verbose": return .debug
        default: return .info
        }
    }

    // CDP line numbers are 0-based.
    private static func line(_ value: Any?) -> Int? {
        (value as? Int).map { $0 + 1 }
    }

    private static func jsonString(_ value: Any) -> String {
        if let string = value as? String { return string }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
            return number.stringValue
        }
        if value is NSNull { return "null" }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return String(describing: value)
    }
}
