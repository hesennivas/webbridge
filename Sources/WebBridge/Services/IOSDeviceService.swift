import Foundation

/// Supervises `ios_webkit_debug_proxy` and polls its device registry. Bridges iOS
/// remote-debug targets onto the same CDP HTTP surface the Android path uses.
actor IOSDeviceService {
    private struct RegistryDevice: Decodable {
        let deviceId: String?
        let deviceName: String?
        let deviceOSVersion: String?
        let url: String?
    }

    private var iwdpPath: String
    private let registryPort = 9221
    private let deviceRange = "9222-9322"

    /// Last-logged registry state, so the poll loop only logs on change instead of every 2s.
    private var lastRegistrySignature: String?

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    init(iwdpPath: String) {
        self.iwdpPath = iwdpPath
    }

    func update(iwdpPath: String) { self.iwdpPath = iwdpPath }

    func deviceStream() -> AsyncStream<[Device]> {
        AsyncStream { continuation in
            let supervisor = Task { await self.superviseProxy() }
            let poller = Task {
                while !Task.isCancelled {
                    continuation.yield(await self.fetchDevices())
                    try? await Task.sleep(for: .seconds(2))
                }
            }
            continuation.onTermination = { _ in
                supervisor.cancel()
                poller.cancel()
            }
        }
    }

    private func superviseProxy() async {
        var attempt = 0
        while !Task.isCancelled {
            let arguments = ["-c", "null:\(registryPort),:\(deviceRange)", "--no-frontend"]
            Log.info(.ios, "launching ios_webkit_debug_proxy: \(iwdpPath) \(arguments.joined(separator: " "))")
            do {
                for try await line in ProcessRunner.lines(iwdpPath, arguments, mergeStderr: true) {
                    attempt = 0
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    // iwdp reports device attach and page-listing failures here; these lines are
                    // the single most useful signal when iOS webviews never show up.
                    if !trimmed.isEmpty { Log.info(.ios, "iwdp: \(trimmed)") }
                }
                Log.error(.ios, "ios_webkit_debug_proxy exited unexpectedly")
            } catch {
                Log.error(.ios, "ios_webkit_debug_proxy failed to launch: \(error.localizedDescription)")
            }
            if Task.isCancelled { break }
            attempt += 1
            let delay = min(30, attempt * 3)
            Log.info(.ios, "restarting ios_webkit_debug_proxy in \(delay)s (attempt \(attempt))")
            try? await Task.sleep(for: .seconds(delay))
        }
    }

    private func fetchDevices() async -> [Device] {
        guard let url = URL(string: "http://localhost:\(registryPort)/json") else { return [] }

        let raw: [RegistryDevice]
        do {
            let (data, _) = try await session.data(from: url)
            raw = try JSONDecoder().decode([RegistryDevice].self, from: data)
        } catch {
            logRegistry("unreachable") {
                Log.error(.ios, "registry :\(registryPort)/json unreachable, ios_webkit_debug_proxy isn't listening yet (\(error.localizedDescription))")
            }
            return []
        }

        let devices: [Device] = raw.compactMap { entry in
            guard let udid = entry.deviceId else { return nil }
            let port = entry.url.flatMap { portFromURL($0) }
            return Device(
                id: udid,
                platform: .ios(udid: udid, port: port ?? 0),
                name: entry.deviceName ?? "iOS device",
                model: entry.deviceName,
                osVersion: entry.deviceOSVersion,
                state: port == nil ? .degraded : .online,
                isWireless: false)
        }

        let signature = devices.map { "\($0.id):\($0.iosPort ?? 0)" }.joined(separator: ",")
        logRegistry(signature) {
            if devices.isEmpty {
                Log.info(.ios, "registry lists no iOS devices; connect via USB, unlock, and tap Trust on the phone")
            }
            for device in devices {
                if let port = device.iosPort, port > 0 {
                    Log.info(.ios, "device \(device.name) [\(device.id)] attached on inspector port \(port)")
                } else {
                    Log.error(.ios, "device \(device.name) [\(device.id)] has no inspector port. iwdp couldn't attach to webinspectord. Unlock the phone and enable Settings → Safari → Advanced → Web Inspector, then reconnect.")
                }
            }
        }
        return devices
    }

    /// Runs `body` only when the registry state differs from the last time we logged, so the
    /// 2-second poll doesn't flood the log while the situation is unchanged.
    private func logRegistry(_ signature: String, _ body: () -> Void) {
        guard signature != lastRegistrySignature else { return }
        lastRegistrySignature = signature
        body()
    }

    private func portFromURL(_ string: String) -> Int? {
        // Registry url is host:port, e.g. "localhost:9222".
        if let port = string.split(separator: ":").last.flatMap({ Int($0) }) { return port }
        return URLComponents(string: string)?.port
    }
}
