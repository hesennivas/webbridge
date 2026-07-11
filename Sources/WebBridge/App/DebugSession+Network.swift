import Foundation

extension DebugSession {

    // MARK: - Network capture

    func applyNetwork(_ signal: NetworkSignal) {
        switch signal {
        case .started(let start):
            if networkByID[start.id] == nil { networkOrder.append(start.id) }
            networkByID[start.id] = NetworkEntry(
                id: start.id, method: start.method, url: start.url, resourceType: start.resourceType,
                requestHeaders: start.headers, postData: start.postData,
                startedMonotonic: start.monotonic, startedAt: start.wallTime)
            trimNetwork()
        case .response(let info):
            guard var entry = networkByID[info.id] else { return }
            entry.status = info.status
            entry.statusText = info.statusText
            entry.mimeType = info.mimeType
            entry.responseHeaders = info.headers
            if entry.resourceType == nil { entry.resourceType = info.resourceType }
            networkByID[info.id] = entry
        case .finished(let id, let length, let monotonic):
            guard var entry = networkByID[id] else { return }
            entry.encodedDataLength = length
            entry.durationMS = max(0, (monotonic - entry.startedMonotonic) * 1000)
            networkByID[id] = entry
        case .failed(let id, let error, let monotonic):
            guard var entry = networkByID[id] else { return }
            entry.failed = true
            entry.errorText = error
            entry.durationMS = max(0, (monotonic - entry.startedMonotonic) * 1000)
            networkByID[id] = entry
        }
        scheduleNetworkFlush()
    }

    private func trimNetwork() {
        while networkOrder.count > 1000 {
            networkByID[networkOrder.removeFirst()] = nil
        }
    }

    private func scheduleNetworkFlush() {
        guard !networkFlushPending else { return }
        networkFlushPending = true
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard let self else { return }
            self.networkFlushPending = false
            self.workspace.networkEntries = self.networkOrder.compactMap { self.networkByID[$0] }
        }
    }

    func clearNetwork() {
        networkByID = [:]
        networkOrder = []
        workspace.networkEntries = []
    }
}
