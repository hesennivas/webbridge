import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    var adbPathOverride: String { didSet { defaults.set(adbPathOverride, forKey: Keys.adb) } }
    var iwdpPathOverride: String { didSet { defaults.set(iwdpPathOverride, forKey: Keys.iwdp) } }
    var syslogPathOverride: String { didSet { defaults.set(syslogPathOverride, forKey: Keys.syslog) } }
    var portLower: Int { didSet { defaults.set(portLower, forKey: Keys.portLower) } }
    var portUpper: Int { didSet { defaults.set(portUpper, forKey: Keys.portUpper) } }
    var socketScanInterval: Double { didSet { defaults.set(socketScanInterval, forKey: Keys.scanInterval) } }
    var consoleBufferSize: Int { didSet { defaults.set(consoleBufferSize, forKey: Keys.consoleBuffer) } }
    var safariAutomationEnabled: Bool { didSet { defaults.set(safariAutomationEnabled, forKey: Keys.safari) } }
    var hasCompletedSetup: Bool { didSet { defaults.set(hasCompletedSetup, forKey: Keys.setupDone) } }

    // Pins and custom labels are both keyed by `Target.pinIdentity`, so they survive
    // reconnects and restarts. `pinnedTargets` keeps pin order.
    var pinnedTargets: [String] { didSet { defaults.set(pinnedTargets, forKey: Keys.pinned) } }
    var targetLabels: [String: String] { didSet { Self.encode(targetLabels, defaults, Keys.labels) } }

    // Console: reusable named searches and whether a search highlights (vs. filters) rows.
    var savedConsoleFilters: [String] { didSet { defaults.set(savedConsoleFilters, forKey: Keys.filters) } }
    var consoleHighlightMatches: Bool { didSet { defaults.set(consoleHighlightMatches, forKey: Keys.highlight) } }

    var portRange: ClosedRange<Int> { min(portLower, portUpper)...max(portLower, portUpper) }

    // matches the SettingsView Stepper bounds; a corrupted default must not crash the port scan.
    private static func clampedPort(_ value: Int) -> Int { min(max(value, 1024), 65000) }

    private let defaults = UserDefaults.standard

    init() {
        adbPathOverride = defaults.string(forKey: Keys.adb) ?? ""
        iwdpPathOverride = defaults.string(forKey: Keys.iwdp) ?? ""
        syslogPathOverride = defaults.string(forKey: Keys.syslog) ?? ""
        portLower = Self.clampedPort(defaults.object(forKey: Keys.portLower) as? Int ?? 9410)
        portUpper = Self.clampedPort(defaults.object(forKey: Keys.portUpper) as? Int ?? 9499)
        socketScanInterval = defaults.object(forKey: Keys.scanInterval) as? Double ?? 5
        consoleBufferSize = defaults.object(forKey: Keys.consoleBuffer) as? Int ?? 5000
        safariAutomationEnabled = defaults.object(forKey: Keys.safari) as? Bool ?? true
        hasCompletedSetup = defaults.bool(forKey: Keys.setupDone)
        pinnedTargets = defaults.stringArray(forKey: Keys.pinned) ?? []
        targetLabels = Self.decode(defaults, Keys.labels, [:])
        savedConsoleFilters = defaults.stringArray(forKey: Keys.filters) ?? []
        consoleHighlightMatches = defaults.bool(forKey: Keys.highlight)
    }

    // MARK: - Pins & labels

    func isPinned(_ identity: String) -> Bool { pinnedTargets.contains(identity) }

    func togglePin(_ identity: String) {
        if let index = pinnedTargets.firstIndex(of: identity) {
            pinnedTargets.remove(at: index)
        } else {
            pinnedTargets.append(identity)
        }
    }

    func setLabel(_ text: String, for identity: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        targetLabels[identity] = trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Console filters

    func saveConsoleFilter(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !savedConsoleFilters.contains(trimmed) else { return }
        savedConsoleFilters.append(trimmed)
    }

    func removeConsoleFilter(_ text: String) { savedConsoleFilters.removeAll { $0 == text } }

    // MARK: - Codable defaults

    private static func decode<T: Decodable>(_ defaults: UserDefaults, _ key: String, _ fallback: T) -> T {
        guard let data = defaults.data(forKey: key),
              let value = try? JSONDecoder().decode(T.self, from: data) else { return fallback }
        return value
    }

    private static func encode<T: Encodable>(_ value: T, _ defaults: UserDefaults, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private enum Keys {
        static let adb = "adbPathOverride"
        static let iwdp = "iwdpPathOverride"
        static let syslog = "syslogPathOverride"
        static let portLower = "portLower"
        static let portUpper = "portUpper"
        static let scanInterval = "socketScanInterval"
        static let consoleBuffer = "consoleBufferSize"
        static let safari = "safariAutomationEnabled"
        static let setupDone = "hasCompletedSetup"
        static let pinned = "pinnedTargets"
        static let labels = "targetLabels"
        static let filters = "savedConsoleFilters"
        static let highlight = "consoleHighlightMatches"
    }
}
