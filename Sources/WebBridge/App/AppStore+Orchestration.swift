import AppKit

extension AppStore {

    // MARK: - Target scanning

    func startSocketScan(serial: String) {
        socketScanTasks[serial]?.cancel()
        socketScanTasks[serial] = Task { [weak self] in
            while !Task.isCancelled {
                await self?.scanAndroidTargets(serial: serial)
                let interval = self?.settings.socketScanInterval ?? 5
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func scanAndroidTargets(serial: String) async {
        guard let androidService, let allocator else { return }
        // nil = the adb query failed; keep existing forwards/targets untouched so a
        // transient hiccup never drops a live DevTools session.
        guard let sockets = await androidService.devtoolsSockets(serial: serial) else { return }
        var liveSockets: Set<String> = []
        var collected: [Target] = []

        for socket in sockets {
            liveSockets.insert(socket.name)
            guard let port = await allocator.port(serial: serial, socket: socket.name) else { continue }
            let engine = await TargetService.engine(port: port)

            var package: String?
            if let pid = socket.pid {
                package = await androidService.packageName(serial: serial, pid: pid)
            } else if let derived = packageFromSocketName(socket.name) {
                package = derived
            }

            let targets = await TargetService.targets(
                port: port,
                deviceID: serial,
                engine: engine,
                appPackage: package,
                appLabel: package,
                canOpenInSafari: false)
            collected.append(contentsOf: targets)
        }

        await allocator.releaseSockets(serial: serial, keeping: liveSockets)
        setTargets(collected, for: serial)
    }

    func startIOSScan(device: Device) {
        guard let port = device.iosPort, port > 0 else { return }
        let udid = device.id
        iosScanTasks[udid]?.cancel()
        iosScanTasks[udid] = Task { [weak self] in
            var lastCount = -1
            while !Task.isCancelled {
                let engine = await TargetService.engine(port: port)
                let targets = await TargetService.targets(
                    port: port, deviceID: udid, engine: engine.isEmpty ? "Safari" : engine,
                    appPackage: nil, appLabel: nil, canOpenInSafari: true)
                if targets.count != lastCount {
                    lastCount = targets.count
                    if targets.isEmpty {
                        Log.info(.ios, "device \(udid): 0 inspectable pages on :\(port). Safari tabs need the device unlocked with Web Inspector enabled; app WebViews need isInspectable = true (iOS 16.4+). There is no automatic exposure for debug builds on iOS.")
                    } else {
                        Log.info(.ios, "device \(udid): \(targets.count) inspectable page(s) on :\(port) [\(targets.map(\.displayTitle).joined(separator: ", "))]")
                    }
                }
                self?.setTargets(targets, for: udid)
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func setTargets(_ targets: [Target], for deviceID: String) {
        if targetsByDevice[deviceID] != targets { targetsByDevice[deviceID] = targets }
        if let session, session.workspace.target.deviceID == deviceID,
           !targets.contains(where: { $0.id == session.workspace.target.id }) {
            session.workspace.connectionClosed = true
        }
    }

    private func packageFromSocketName(_ name: String) -> String? {
        guard name.hasSuffix("_devtools_remote"),
              !name.hasPrefix("chrome"),
              !name.hasPrefix("webview") else { return nil }
        return String(name.dropLast("_devtools_remote".count))
    }

    // MARK: - Session lifecycle

    func openConsole(_ target: Target) {
        backToOverview()   // stashes the outgoing target's scrollback

        // iOS targets speak WebKit's Target-multiplexed protocol; Android/Chrome speak flat CDP.
        let device = devices.first { $0.id == target.deviceID }
        let webkit = device?.isIOS ?? target.canOpenInSafari
        // iOS always offers the toggle (setup guidance covers a missing tool); Android needs
        // adb, a serial, and a resolved owning package to scope the stream to the app.
        let deviceLogAvailable = webkit
            ? true
            : ((device?.isAndroid ?? false) && tools.hasAdb && device?.serial != nil && target.appPackage != nil)

        let identity = target.pinIdentity
        let session = DebugSession(
            target: target,
            url: URL(string: target.webSocketDebuggerURL),
            webkit: webkit,
            deviceLogAvailable: deviceLogAvailable,
            seed: consoleHistory[identity] ?? [],   // prior scrollback for reload/reconnect context
            detectedFramework: frameworksByIdentity[identity],
            ids: ids,
            settings: settings,
            deviceLogFactory: makeDeviceLogFactory(target: target, device: device),
            onFrameworkDetected: { [weak self] name in self?.frameworksByIdentity[identity] = name })
        self.session = session
        session.start()
    }

    func backToOverview() {
        stashConsoleHistory()
        session?.close()
        session = nil
    }

    /// saves the live console buffer under the target identity, capped to a handful of targets.
    private func stashConsoleHistory() {
        guard let session else { return }
        let identity = session.workspace.target.pinIdentity
        if consoleHistory[identity] == nil { consoleHistoryOrder.append(identity) }
        consoleHistory[identity] = session.consoleScrollback
        while consoleHistoryOrder.count > 12 {
            consoleHistory[consoleHistoryOrder.removeFirst()] = nil
        }
    }

    /// resolves the device/tool knowledge into a factory the session calls when the user switches
    /// to the native device-log pane, so the session never has to reach back into device state.
    private func makeDeviceLogFactory(target: Target, device: Device?) -> @MainActor () -> DeviceLogResult {
        let tools = self.tools
        let ids = self.ids
        return {
            guard let device else { return .unavailable }
            if device.isIOS {
                guard let tool = tools.syslog else { return .missingTool }
                return .source(IOSSyslogService(toolPath: tool, udid: device.id, ids: ids))
            }
            guard let serial = device.serial, let package = target.appPackage, let adb = tools.adb else {
                return .unavailable
            }
            return .source(LogcatService(adbPath: adb, serial: serial, package: package, ids: ids))
        }
    }

    // MARK: - Device info

    func loadDeviceInfo(serial: String, force: Bool = false) {
        guard let deviceInfoService else { return }
        if deviceInfoByDevice[serial] != nil && !force { return }
        guard !infoLoading.contains(serial) else { return }
        infoLoading.insert(serial)
        Task { [weak self] in
            let info = await deviceInfoService.load(serial: serial)
            guard let self else { return }
            self.deviceInfoByDevice[serial] = info
            self.infoLoading.remove(serial)
        }
    }

    func appAction(_ action: AppAction, package: String, serial: String) {
        guard let deviceInfoService else { return }
        Task {
            switch action {
            case .forceStop: await deviceInfoService.forceStop(serial: serial, package: package)
            case .clearData: await deviceInfoService.clearData(serial: serial, package: package)
            case .launch: await deviceInfoService.launch(serial: serial, package: package)
            }
        }
    }

    // MARK: - Open in browser

    func openInChrome(_ target: Target) {
        // A page accepts one debugger client; drop our own connection to it so DevTools
        // gets a clean WebSocket.
        if session?.workspace.target.id == target.id { backToOverview() }
        Task { [weak self] in
            guard let self else { return }
            let relay = await self.relayHandle(forDevicePort: target.localPort)
            BrowserLauncher.openChromeDevTools(target, relay: relay)
        }
    }

    /// Returns the running relay's port and auth token for the device debug port, starting one if needed.
    private func relayHandle(forDevicePort devicePort: Int) async -> (port: Int, token: String)? {
        if let existing = relays[devicePort] { return (existing.localPort, existing.token) }
        let relay = DevToolsRelay(devicePort: devicePort)
        guard let port = await relay.start() else { return nil }
        relays[devicePort] = relay
        return (port, relay.token)
    }

    func openInSafari(_ target: Target) {
        guard let device = devices.first(where: { $0.id == target.deviceID }) else { return }
        let outcome = SafariAutomation.openInspector(deviceName: device.name, pageTitle: target.displayTitle)
        switch outcome {
        case .automated:
            break
        case .guided(let path):
            pushBanner(Banner(kind: .info, title: "Open in Safari",
                              message: "Safari is active, choose \(path)"))
        case .needsPermission(let path):
            pushBanner(Banner(kind: .warning, title: "Safari inspection needs Accessibility",
                              message: "Choose \(path). Enable automation in Setup to skip this step.",
                              actionTitle: "Open Setup", action: { [weak self] in self?.setupVisible = true }))
        case .safariMissing:
            pushBanner(Banner(kind: .error, title: "Safari not found", message: "Could not locate Safari on this Mac."))
        }
    }

    // MARK: - Banners

    func pushBanner(_ banner: Banner) {
        banners.removeAll { $0.title == banner.title }
        banners.append(banner)
    }

    func dismissBanner(_ id: UUID) {
        banners.removeAll { $0.id == id }
    }

    func refreshToolBanners() {
        // adb is required for Android; the iOS proxy is optional and only surfaced in Setup.
        banners.removeAll { $0.title.hasPrefix("adb") }
        if !tools.hasAdb {
            pushBanner(Banner(kind: .warning, title: "adb not found",
                              message: "Install with: brew install android-platform-tools",
                              actionTitle: "Open Setup", action: { [weak self] in self?.setupVisible = true }))
        }
    }
}

enum AppAction { case forceStop, clearData, launch }
