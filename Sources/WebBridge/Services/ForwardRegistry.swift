import Foundation

/// Process-wide record of adb forwards we created, used for synchronous best-effort
/// cleanup on quit so we never leak forwards belonging to us (and only us).
final class ForwardRegistry: @unchecked Sendable {
    static let shared = ForwardRegistry()

    private let lock = NSLock()
    private var ports: Set<Int> = []
    private var adbPath: String?

    func setADB(_ path: String?) {
        lock.lock(); defer { lock.unlock() }
        adbPath = path
    }

    func record(_ port: Int) {
        lock.lock(); defer { lock.unlock() }
        ports.insert(port)
    }

    func forget(_ port: Int) {
        lock.lock(); defer { lock.unlock() }
        ports.remove(port)
    }

    /// Synchronous teardown invoked from applicationShouldTerminate.
    func removeAllSynchronously() {
        lock.lock()
        let snapshot = ports
        let adb = adbPath
        ports.removeAll()
        lock.unlock()

        guard let adb, !snapshot.isEmpty else { return }
        for port in snapshot {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: adb)
            process.arguments = ["forward", "--remove", "tcp:\(port)"]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try? process.run()
            process.waitUntilExit()
        }
    }
}
