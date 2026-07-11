import Foundation
import Observation

@MainActor
@Observable
final class AppStore {
    // Observed UI state.
    var androidDevices: [Device] = []
    var iosDevices: [Device] = []
    var targetsByDevice: [String: [Target]] = [:]
    var selectedDeviceID: String?
    var overviewTab: OverviewTab = .webviews
    /// Free-text filter for the WebViews list, matched against target title and URL.
    /// Transient: narrows the current view, not a saved preference.
    var overviewSearch = ""
    /// the live debugging session for the open target, or nil on the overview. creating it opens
    /// a target; setting it to nil (via `backToOverview`) tears the whole session down.
    var session: DebugSession?
    var deviceInfoByDevice: [String: DeviceInfo] = [:]
    var infoLoading: Set<String> = []
    var tools = ToolPaths()
    var banners: [Banner] = []
    var setupVisible = false
    /// detected hybrid framework per target identity; drives the overview badge.
    var frameworksByIdentity: [String: String] = [:]
    let settings = AppSettings()

    // Orchestration state, not part of the observed view surface.
    @ObservationIgnored let ids = Sequence64()
    @ObservationIgnored var androidService: AndroidDeviceService?
    @ObservationIgnored var iosService: IOSDeviceService?
    @ObservationIgnored var allocator: PortAllocator?
    @ObservationIgnored var deviceInfoService: DeviceInfoService?
    @ObservationIgnored var relays: [Int: DevToolsRelay] = [:]

    // console scrollback kept per target identity so reopening a target restores its history.
    @ObservationIgnored var consoleHistory: [String: [ConsoleEntry]] = [:]
    @ObservationIgnored var consoleHistoryOrder: [String] = []

    @ObservationIgnored var androidStreamTask: Task<Void, Never>?
    @ObservationIgnored var iosStreamTask: Task<Void, Never>?
    @ObservationIgnored var socketScanTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored var iosScanTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored var didStart = false

    // MARK: - Derived

    var devices: [Device] { androidDevices + iosDevices }

    var onlineAndroid: [Device] { androidDevices.filter { $0.isOnline } }
    var onlineIOS: [Device] { iosDevices.filter { $0.isOnline } }
    var offlineDevices: [Device] { devices.filter { !$0.isOnline } }

    var selectedDevice: Device? {
        guard let selectedDeviceID else { return nil }
        return devices.first { $0.id == selectedDeviceID }
    }

    var selectedTargets: [Target] {
        guard let selectedDeviceID else { return [] }
        return targetsByDevice[selectedDeviceID] ?? []
    }

    /// Pinned targets (live or absent) in pin order, filtered by the search text. Shown as
    /// the "Pinned" section above the per-app groups.
    var pinnedItems: [PinnedItem] {
        let present = Dictionary(selectedTargets.filter(\.isPage).map { ($0.pinIdentity, $0) },
                                 uniquingKeysWith: { first, _ in first })
        return settings.pinnedTargets.compactMap { identity in
            let target = present[identity]
            let label = settings.targetLabels[identity] ?? target?.displayTitle ?? identity
            guard searchMatches(label, identity) else { return nil }
            return PinnedItem(identity: identity, target: target, label: label)
        }
    }

    /// The unpinned page targets for the selected device, grouped by owning app / engine.
    var selectedTargetGroups: [TargetGroup] {
        let pinned = Set(settings.pinnedTargets)
        let pages = selectedTargets.filter(\.isPage).filter { !pinned.contains($0.pinIdentity) }
            .filter { searchMatches(label(for: $0), $0.url) }
        let grouped = Dictionary(grouping: pages, by: \.groupKey)
        return grouped.map { key, targets in
            TargetGroup(id: key, label: targets.first?.groupLabel ?? key,
                        targets: targets.sorted { $0.displayTitle < $1.displayTitle })
        }
        .sorted { $0.label < $1.label }
    }

    /// Distinguishes "no webviews at all" from "no search matches" for the empty state.
    var selectedHasPages: Bool { selectedTargets.contains(where: \.isPage) }

    /// true once the device is online but the first target scan hasn't reported yet; drives the scanning loader.
    var selectedScanPending: Bool {
        guard let device = selectedDevice, device.isOnline,
              targetsByDevice[device.id] == nil else { return false }
        return device.isAndroid ? tools.hasAdb : (device.iosPort ?? 0) > 0
    }

    private func searchMatches(_ fields: String...) -> Bool {
        let query = overviewSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return fields.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    // MARK: - Pins & labels

    func isPinned(_ target: Target) -> Bool { settings.isPinned(target.pinIdentity) }
    func togglePin(_ target: Target) { settings.togglePin(target.pinIdentity) }
    func unpin(_ identity: String) { settings.pinnedTargets.removeAll { $0 == identity } }

    /// Single source of truth for a target's display name: the user's custom label, else its title.
    func label(for target: Target) -> String { settings.targetLabels[target.pinIdentity] ?? target.displayTitle }
    func labelText(for identity: String) -> String { settings.targetLabels[identity] ?? "" }
    func setLabel(_ text: String, for identity: String) { settings.setLabel(text, for: identity) }

    // MARK: - Lifecycle

    func start() async {
        await resolveTools()
        guard !didStart else { return }
        didStart = true
        startDeviceStreams()
        if !settings.hasCompletedSetup { setupVisible = true }
    }

    func resolveTools() async {
        let adbOverride = settings.adbPathOverride.isEmpty ? nil : settings.adbPathOverride
        let iwdpOverride = settings.iwdpPathOverride.isEmpty ? nil : settings.iwdpPathOverride
        let syslogOverride = settings.syslogPathOverride.isEmpty ? nil : settings.syslogPathOverride
        tools = await ToolLocator.resolve(
            adbOverride: adbOverride, iwdpOverride: iwdpOverride, syslogOverride: syslogOverride)
        ForwardRegistry.shared.setADB(tools.adb)

        if let adb = tools.adb {
            androidService = AndroidDeviceService(adbPath: adb)
            allocator = PortAllocator(adbPath: adb, range: settings.portRange)
            deviceInfoService = DeviceInfoService(adbPath: adb)
        } else {
            androidService = nil
        }
        iosService = tools.iwdp.map { IOSDeviceService(iwdpPath: $0) }
        refreshToolBanners()
    }

    private func startDeviceStreams() {
        if let androidService {
            androidStreamTask = Task { [weak self] in
                for await list in await androidService.deviceStream() {
                    self?.applyAndroidDevices(list)
                }
            }
        }
        if let iosService {
            iosStreamTask = Task { [weak self] in
                for await list in await iosService.deviceStream() {
                    self?.applyIOSDevices(list)
                }
            }
        }
    }

    // MARK: - Device application

    private func applyAndroidDevices(_ list: [Device]) {
        let previous = Set(androidDevices.map(\.id))
        // skip the write when unchanged so an idle app doesn't invalidate the view tree every poll
        if androidDevices != list { androidDevices = list }

        let onlineSerials = Set(list.filter(\.isOnline).compactMap(\.serial))
        for serial in onlineSerials where socketScanTasks[serial] == nil {
            startSocketScan(serial: serial)
        }
        for serial in Array(socketScanTasks.keys) where !onlineSerials.contains(serial) {
            teardownAndroidDevice(serial: serial)
        }
        let current = Set(list.map(\.id))
        for gone in previous.subtracting(current) {
            targetsByDevice[gone] = nil
        }
        reconcileSelection()
    }

    private func applyIOSDevices(_ list: [Device]) {
        if iosDevices != list { iosDevices = list }
        let inspectable = list.filter { $0.isOnline && ($0.iosPort ?? 0) > 0 }
        let inspectableIDs = Set(inspectable.map(\.id))
        for device in inspectable where iosScanTasks[device.id] == nil {
            startIOSScan(device: device)
        }
        for udid in Array(iosScanTasks.keys) where !inspectableIDs.contains(udid) {
            iosScanTasks[udid]?.cancel()
            iosScanTasks[udid] = nil
            targetsByDevice[udid] = nil
        }
        reconcileSelection()
    }

    private func teardownAndroidDevice(serial: String) {
        socketScanTasks[serial]?.cancel()
        socketScanTasks[serial] = nil
        targetsByDevice[serial] = nil
        if let allocator {
            Task { await allocator.releaseDevice(serial: serial) }
        }
    }

    private func reconcileSelection() {
        if selectedDeviceID == nil {
            selectedDeviceID = devices.first { $0.isOnline }?.id
        } else if let id = selectedDeviceID, !devices.contains(where: { $0.id == id }) {
            selectedDeviceID = devices.first { $0.isOnline }?.id
        }
    }

    // MARK: - Selection intents

    func selectDevice(_ id: String) {
        guard id != selectedDeviceID else { return }
        if session != nil { backToOverview() }
        selectedDeviceID = id
        overviewSearch = ""
        onDeviceContextChanged()
    }

    func selectTab(_ tab: OverviewTab) {
        overviewTab = tab
        onDeviceContextChanged()
    }

    private func onDeviceContextChanged() {
        guard let device = selectedDevice, device.isAndroid, let serial = device.serial else { return }
        if overviewTab == .info { loadDeviceInfo(serial: serial) }
    }

    // MARK: - Teardown

    func teardownSync() {
        ForwardRegistry.shared.removeAllSynchronously()
    }
}

struct TargetGroup: Identifiable {
    let id: String
    let label: String
    let targets: [Target]
}

/// A pinned entry: `target` is nil when the pin isn't currently present (a "ghost" row).
struct PinnedItem: Identifiable {
    let identity: String
    let target: Target?
    let label: String
    var id: String { identity }
    var isGhost: Bool { target == nil }
}
