import Foundation

/// events from a native device-log stream (adb logcat or idevicesyslog).
enum DeviceLogEvent: Sendable {
    case entry(ConsoleEntry)
    case failed(String)
}

/// a native device-log stream, so the store drives Android and iOS through one pipeline.
protocol DeviceLogSource: Actor {
    nonisolated var events: AsyncStream<DeviceLogEvent> { get }
    func start()
    func stop()
}
