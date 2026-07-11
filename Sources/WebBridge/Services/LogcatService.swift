import Foundation

/// streams an app's adb logcat, scoped to the app's pid and restarted automatically when
/// that pid changes (app relaunch).
actor LogcatService: DeviceLogSource {
    nonisolated let events: AsyncStream<DeviceLogEvent>

    private let adbPath: String
    private let serial: String
    private let package: String
    private let ids: Sequence64
    private let continuation: AsyncStream<DeviceLogEvent>.Continuation
    private var loop: Task<Void, Never>?

    init(adbPath: String, serial: String, package: String, ids: Sequence64) {
        self.adbPath = adbPath
        self.serial = serial
        self.package = package
        self.ids = ids
        var handoff: AsyncStream<DeviceLogEvent>.Continuation!
        self.events = AsyncStream { handoff = $0 }
        self.continuation = handoff
    }

    func start() {
        guard loop == nil else { return }
        loop = Task { await run() }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        continuation.finish()
    }

    private func run() async {
        while !Task.isCancelled {
            guard let pid = await resolvePID() else {
                try? await Task.sleep(for: .seconds(2))
                continue
            }
            await stream(pid: pid)
        }
    }

    private func stream(pid: Int) async {
        let reader = Task {
            let args = ["-s", serial, "logcat", "--pid=\(pid)", "-v", "epoch", "-T", "200"]
            do {
                for try await line in ProcessRunner.lines(adbPath, args) {
                    if Task.isCancelled { break }
                    if let entry = Self.entry(from: line, ids: ids) { continuation.yield(.entry(entry)) }
                }
            } catch {}
        }
        // a changed pid means the app relaunched, tear this reader down and rebind
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3))
            if await resolvePID() != pid { break }
        }
        reader.cancel()
    }

    private func resolvePID() async -> Int? {
        guard let out = try? await ProcessRunner.output(
            adbPath, ["-s", serial, "shell", "pidof", "-s", package]) else { return nil }
        return out.split(whereSeparator: { $0 == " " || $0 == "\n" }).first.flatMap { Int($0) }
    }

    private static func entry(from line: String, ids: Sequence64) -> ConsoleEntry? {
        guard let parsed = Parsing.logcatLine(line) else { return nil }
        return ConsoleEntry(
            id: ids.next(),
            level: level(parsed.level),
            text: parsed.message,
            source: parsed.tag.isEmpty ? nil : parsed.tag,
            timestamp: Date(timeIntervalSince1970: parsed.time))
    }

    private static func level(_ char: Character) -> ConsoleLevel {
        switch char {
        case "E", "F": return .error
        case "W": return .warning
        case "I": return .info
        case "V", "D": return .debug
        default: return .log
        }
    }
}
