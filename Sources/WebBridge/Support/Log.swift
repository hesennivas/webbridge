import Foundation
import os

/// Lightweight diagnostics. Every message goes to the unified log *and* is mirrored to
/// stderr so it shows up immediately when WebBridge is launched from a terminal
/// (`.build/release/WebBridge`).
///
/// To follow just WebBridge in Console.app or the terminal:
///
///     log stream --predicate 'subsystem == "com.hesennivas.webbridge"' --level info
///
/// The `.ios` category is the one to watch when iOS webviews fail to appear; it carries
/// the raw `ios_webkit_debug_proxy` output plus the registry / page-list results.
enum Log {
    enum Category: String, CaseIterable {
        case ios, android, cdp, process
    }

    static func info(_ category: Category, _ message: @autoclosure () -> String) {
        emit(category, mark: "•", type: .info, message())
    }

    static func error(_ category: Category, _ message: @autoclosure () -> String) {
        emit(category, mark: "✗", type: .error, message())
    }

    private static let subsystem = "com.hesennivas.webbridge"

    private static let loggers: [Category: Logger] = Dictionary(
        uniqueKeysWithValues: Category.allCases.map { ($0, Logger(subsystem: subsystem, category: $0.rawValue)) })

    private static func emit(_ category: Category, mark: String, type: OSLogType, _ message: String) {
        loggers[category]?.log(level: type, "\(message, privacy: .public)")
        fputs("[webbridge/\(category.rawValue)] \(mark) \(message)\n", stderr)
    }
}
