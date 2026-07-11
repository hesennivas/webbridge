import Foundation

/// Thread-safe mutable box used to share non-Sendable references (Process, sockets)
/// across concurrency domains where the framework type predates Sendable.
final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) { storage = value }

    var value: Value {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    @discardableResult
    func withLock<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.lock(); defer { lock.unlock() }
        return body(&storage)
    }
}

/// Monotonic id source for buffered log/console entries.
final class Sequence64: @unchecked Sendable {
    private let lock = NSLock()
    private var counter: UInt64 = 0

    func next() -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        counter &+= 1
        return counter
    }
}
