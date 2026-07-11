import Foundation

/// streams a device's idevicesyslog. iOS gives no reliable app→process mapping from a webview
/// target, so this is device-wide; the Source filter narrows it by process.
actor IOSSyslogService: DeviceLogSource {
    nonisolated let events: AsyncStream<DeviceLogEvent>

    private let toolPath: String
    private let udid: String
    private let ids: Sequence64
    private let continuation: AsyncStream<DeviceLogEvent>.Continuation
    private var task: Task<Void, Never>?
    private var sawEntry = false

    init(toolPath: String, udid: String, ids: Sequence64) {
        self.toolPath = toolPath
        self.udid = udid
        self.ids = ids
        var handoff: AsyncStream<DeviceLogEvent>.Continuation!
        self.events = AsyncStream { handoff = $0 }
        self.continuation = handoff
    }

    func start() {
        guard task == nil else { return }
        task = Task { await run() }
    }

    func stop() {
        task?.cancel()
        task = nil
        continuation.finish()
    }

    private func run() async {
        // --no-colors keeps lines parseable; -q drops common noisy system processes.
        let args = ["-u", udid, "--no-colors", "-q"]
        do {
            for try await line in ProcessRunner.lines(toolPath, args, mergeStderr: true) {
                if Task.isCancelled { break }
                // a well-formed syslog line is always a log; only idevicesyslog's own diagnostics
                // (which don't parse) can be a failure, and only before any log has arrived.
                if let entry = Self.entry(from: line, ids: ids) {
                    sawEntry = true
                    continuation.yield(.entry(entry))
                } else if !sawEntry, let failure = Self.connectionError(line) {
                    continuation.yield(.failed(failure))
                }
            }
        } catch {
            if !sawEntry { continuation.yield(.failed("Could not start idevicesyslog.")) }
        }
    }

    // matches only idevicesyslog's own connection diagnostics, never words that appear in logs.
    private static func connectionError(_ line: String) -> String? {
        let lower = line.lowercased()
        guard lower.contains("could not connect to lockdownd")
            || lower.contains("no device found")
            || lower.contains("could not start service")
            || lower.contains("unable to connect")
            || lower.contains("please accept the") else { return nil }
        return "Can't reach the device. Unlock the iPhone, tap Trust This Computer, and reconnect."
    }

    private static func entry(from line: String, ids: Sequence64) -> ConsoleEntry? {
        guard let parsed = Parsing.iosSyslogLine(line) else { return nil }
        return ConsoleEntry(
            id: ids.next(),
            level: level(parsed.level),
            text: parsed.message,
            source: parsed.process.isEmpty ? nil : parsed.process)
    }

    private static func level(_ name: String) -> ConsoleLevel {
        switch name {
        case "Error", "Critical", "Fault": return .error
        case "Warning": return .warning
        case "Debug": return .debug
        case "Notice", "Info", "Default": return .info
        default: return .log
        }
    }
}
