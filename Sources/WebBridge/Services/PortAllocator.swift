import Foundation

/// Owns adb port-forwards keyed on (serial, socket). Reuses existing forwards, probes
/// availability before binding, and reconciles against `adb forward --list` so a crash
/// or restart self-heals instead of leaking.
actor PortAllocator {
    struct Key: Hashable, Sendable {
        let serial: String
        let socket: String
    }

    private var adbPath: String
    private var lowerBound: Int
    private var upperBound: Int
    private var assignments: [Key: Int] = [:]
    private var usedPorts: Set<Int> = []
    private var missCounts: [Key: Int] = [:]
    private let missThreshold = 2

    init(adbPath: String, range: ClosedRange<Int>) {
        self.adbPath = adbPath
        self.lowerBound = range.lowerBound
        self.upperBound = range.upperBound
    }

    func update(adbPath: String, range: ClosedRange<Int>) {
        self.adbPath = adbPath
        self.lowerBound = range.lowerBound
        self.upperBound = range.upperBound
    }

    /// Adopt forwards already present in our range, drop stale ones.
    func reconcile(activeSerials: Set<String>) async {
        guard let listing = try? await ProcessRunner.output(adbPath, ["forward", "--list"]) else { return }
        for line in listing.split(separator: "\n") {
            // Format: "SERIAL tcp:PORT localabstract:SOCKET"
            let parts = line.split(separator: " ").map(String.init)
            guard parts.count >= 3,
                  let port = parsePort(parts[1]),
                  port >= lowerBound, port <= upperBound else { continue }
            let serial = parts[0]
            let socket = parts[2].replacingOccurrences(of: "localabstract:", with: "")
            if activeSerials.contains(serial) {
                assignments[Key(serial: serial, socket: socket)] = port
                usedPorts.insert(port)
                ForwardRegistry.shared.record(port)
            } else {
                await removeForward(port)
            }
        }
    }

    /// Returns a local port forwarding to the given device socket, creating it if needed.
    func port(serial: String, socket: String) async -> Int? {
        let key = Key(serial: serial, socket: socket)
        if let existing = assignments[key] { return existing }

        guard let port = nextFreePort() else { return nil }
        let result = try? await ProcessRunner.run(
            adbPath, ["-s", serial, "forward", "tcp:\(port)", "localabstract:\(socket)"])
        guard result?.ok == true else { return nil }

        assignments[key] = port
        usedPorts.insert(port)
        ForwardRegistry.shared.record(port)
        return port
    }

    /// Removes a forward only after its socket has been absent for `missThreshold`
    /// consecutive scans, so a transient adb hiccup doesn't kill a live DevTools session.
    func releaseSockets(serial: String, keeping liveSockets: Set<String>) async {
        let deviceKeys = assignments.keys.filter { $0.serial == serial }
        for key in deviceKeys {
            if liveSockets.contains(key.socket) {
                missCounts[key] = 0
                continue
            }
            let misses = (missCounts[key] ?? 0) + 1
            if misses >= missThreshold {
                missCounts[key] = nil
                if let port = assignments.removeValue(forKey: key) {
                    await removeForward(port)
                }
            } else {
                missCounts[key] = misses
            }
        }
    }

    func releaseDevice(serial: String) async {
        let deviceKeys = assignments.keys.filter { $0.serial == serial }
        for key in deviceKeys {
            missCounts[key] = nil
            if let port = assignments.removeValue(forKey: key) {
                await removeForward(port)
            }
        }
    }

    func releaseAll() async {
        let ports = Array(usedPorts)
        assignments.removeAll()
        for port in ports { await removeForward(port) }
    }

    private func removeForward(_ port: Int) async {
        _ = try? await ProcessRunner.run(adbPath, ["forward", "--remove", "tcp:\(port)"])
        usedPorts.remove(port)
        ForwardRegistry.shared.forget(port)
    }

    private func nextFreePort() -> Int? {
        for port in lowerBound...upperBound where !usedPorts.contains(port) && PortProbe.isFree(port) {
            return port
        }
        return nil
    }

    private func parsePort(_ token: String) -> Int? {
        Int(token.replacingOccurrences(of: "tcp:", with: ""))
    }
}
