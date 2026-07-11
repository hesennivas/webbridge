import Foundation

/// Talks to the adb server: streams device connect/disconnect, discovers devtools
/// sockets, and resolves owning packages. Holds no UI state.
actor AndroidDeviceService {
    private var adbPath: String

    init(adbPath: String) {
        self.adbPath = adbPath
    }

    func update(adbPath: String) { self.adbPath = adbPath }

    /// Emits the full device list on every adb-reported change. Uses a persistent
    /// `track-devices` stream as a change signal, then re-queries the authoritative list.
    func deviceStream() -> AsyncStream<[Device]> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    // Immediate snapshot so the UI populates on launch.
                    continuation.yield(await self.snapshot())
                    do {
                        for try await _ in ProcessRunner.lines(self.adbPath, ["track-devices"]) {
                            continuation.yield(await self.snapshot())
                        }
                    } catch {
                        // adb server unavailable, surface an empty list and retry.
                        continuation.yield([])
                    }
                    if Task.isCancelled { break }
                    try? await Task.sleep(for: .seconds(2))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func snapshot() async -> [Device] {
        guard let output = try? await ProcessRunner.output(adbPath, ["devices", "-l"]) else { return [] }
        return Parsing.androidDevices(output).map { line in
            Device(
                id: line.serial,
                platform: .android(serial: line.serial),
                name: line.model ?? line.serial,
                model: line.model,
                osVersion: nil,
                state: line.state,
                isWireless: line.isWireless)
        }
    }

    func androidVersion(serial: String) async -> String? {
        try? await ProcessRunner.output(adbPath, ["-s", serial, "shell", "getprop", "ro.build.version.release"])
    }

    /// Returns nil when the adb query itself failed (so callers keep existing forwards),
    /// or the parsed socket list (possibly empty) on success.
    func devtoolsSockets(serial: String) async -> [Parsing.DevtoolsSocket]? {
        guard let output = try? await ProcessRunner.output(
            adbPath, ["-s", serial, "shell", "cat", "/proc/net/unix"]) else { return nil }
        return Parsing.devtoolsSockets(output)
    }

    func packageName(serial: String, pid: Int32) async -> String? {
        guard let output = try? await ProcessRunner.output(
            adbPath, ["-s", serial, "shell", "cat", "/proc/\(pid)/cmdline"]) else { return nil }
        return Parsing.packageFromCmdline(output)
    }

    func appLabel(serial: String, package: String) async -> String? {
        // Best-effort friendly name; falls back to the package if unavailable.
        guard let output = try? await ProcessRunner.output(
            adbPath, ["-s", serial, "shell", "cmd", "package", "resolve-activity", "--brief", package]) else {
            return nil
        }
        return output.split(separator: "\n").last.map(String.init)
    }
}
