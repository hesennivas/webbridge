import Foundation

/// outcome of asking `AppStore` to build a native device-log stream for this session's target.
/// `AppStore` owns the device/tool knowledge; the session only decides how to surface the result.
enum DeviceLogResult {
    case source(any DeviceLogSource)
    case missingTool
    case unavailable
}

extension DebugSession {

    // MARK: - Device logs (adb logcat / idevicesyslog)

    func startDeviceLog() {
        guard deviceLogService == nil, workspace.logSource == .device else { return }
        switch deviceLogFactory() {
        case .missingTool:
            workspace.deviceLogState = .missingTool
        case .unavailable:
            break
        case .source(let service):
            workspace.deviceLogState = .ready
            deviceLogBuffer = RingBuffer(capacity: consoleBufferCapacity)
            deviceLogService = service
            deviceLogTask = Task { [weak self] in
                await service.start()
                for await event in service.events {
                    switch event {
                    case .entry(let entry): self?.appendDeviceLog(entry)
                    case .failed(let message): self?.workspace.deviceLogState = .failed(message)
                    }
                }
            }
        }
    }

    /// re-attempt after the user installs the tool or trusts the device from setup.
    func retryDeviceLog() {
        stopDeviceLog()
        startDeviceLog()
    }

    func stopDeviceLog() {
        deviceLogTask?.cancel()
        deviceLogTask = nil
        let service = deviceLogService
        deviceLogService = nil
        if let service { Task { await service.stop() } }
        deviceLogBuffer.clear()
    }

    private func appendDeviceLog(_ entry: ConsoleEntry) {
        if let last = deviceLogBuffer.last, last.isDuplicate(of: entry) {
            var merged = last
            merged.repeatCount += 1
            deviceLogBuffer.replaceLast(merged)
        } else {
            deviceLogBuffer.append(entry)
        }
        scheduleDeviceLogFlush()
    }

    private func scheduleDeviceLogFlush() {
        guard !deviceLogFlushPending else { return }
        deviceLogFlushPending = true
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            guard let self else { return }
            self.deviceLogFlushPending = false
            self.workspace.deviceEntries = self.deviceLogBuffer.elements
        }
    }

    private var consoleBufferCapacity: Int { consoleBuffer.capacity }
}
