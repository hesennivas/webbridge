import Foundation

enum OverviewTab: String, CaseIterable, Identifiable {
    case webviews
    case info

    var id: String { rawValue }
    var title: String {
        switch self {
        case .webviews: return "WebViews"
        case .info: return "Device Info"
        }
    }
    var symbol: String {
        switch self {
        case .webviews: return "globe"
        case .info: return "info.circle"
        }
    }
}

enum LogSource: String, CaseIterable, Identifiable {
    case webView, device
    var id: String { rawValue }
    var title: String { self == .webView ? "WebView" : "Device" }
}

/// why the device-log pane can't stream, so it can guide the user to setup.
enum DeviceLogState: Equatable {
    case ready
    case missingTool
    case failed(String)
}

enum WorkspaceTab: String, CaseIterable, Identifiable {
    case console, network, storage

    var id: String { rawValue }
    var title: String {
        switch self {
        case .console: return "Console"
        case .network: return "Network"
        case .storage: return "Storage"
        }
    }
    var symbol: String {
        switch self {
        case .console: return "text.alignleft"
        case .network: return "network"
        case .storage: return "internaldrive"
        }
    }
}

struct WorkspaceState {
    var target: Target
    /// WebKit (iOS) targets speak a protocol dialect without the Network domain.
    var isWebKit = false
    var tab: WorkspaceTab = .console
    var detectedFramework: String?

    var entries: [ConsoleEntry] = []
    /// native adb logcat for the owning app; only populated for Android targets.
    var deviceEntries: [ConsoleEntry] = []
    var logSource: LogSource = .webView
    var deviceLogAvailable = false
    var deviceLogState: DeviceLogState = .ready
    var levelFilter: Set<ConsoleLevel> = Set(ConsoleLevel.allCases)
    /// empty = no constraint; otherwise a row must carry at least one selected category.
    var categoryFilter: LogCategory = []
    /// empty = no constraint; otherwise a row's source must be one of these.
    var sourceFilter: Set<String> = []
    var searchText = ""
    /// treat searchText as a regular expression instead of a literal substring.
    var useRegex = false
    /// 0-based cursor into the current match list, for find-bar navigation.
    var currentMatchIndex = 0
    var connectionClosed = false

    // network pane
    var networkEntries: [NetworkEntry] = []
    var networkSearch = ""
    /// selected status classes (2/3/4/5); empty = all.
    var networkStatusFilter: Set<Int> = []
    /// selected resource types; empty = all.
    var networkTypeFilter: Set<String> = []

    // storage pane
    var storage: StorageSnapshot?
    var storageLoading = false
    var storageSearch = ""

    /// Network is hidden for WebKit targets, which don't emit CDP network events here.
    var availableTabs: [WorkspaceTab] {
        isWebKit ? [.console, .storage] : [.console, .network, .storage]
    }

    func filteredNetwork() -> [NetworkEntry] {
        let query = networkSearch.trimmingCharacters(in: .whitespaces)
        return networkEntries.filter { entry in
            (networkStatusFilter.isEmpty || networkStatusFilter.contains(entry.statusClass))
                && (networkTypeFilter.isEmpty || (entry.resourceType.map(networkTypeFilter.contains) ?? false))
                && (query.isEmpty || entry.url.localizedCaseInsensitiveContains(query))
        }
    }

    func networkClassCounts() -> [Int: Int] {
        var counts: [Int: Int] = [:]
        for entry in networkEntries { counts[entry.statusClass, default: 0] += 1 }
        return counts
    }

    func networkTypes() -> [String] {
        Set(networkEntries.compactMap(\.resourceType)).sorted()
    }

    var availableLogSources: [LogSource] { deviceLogAvailable ? [.webView, .device] : [.webView] }

    /// the rows the console pane is currently showing (WebView console or native device logs).
    var activeEntries: [ConsoleEntry] { logSource == .device ? deviceEntries : entries }

    /// builds the console view (rows, match set, counts, categories) in one pass. `highlight`
    /// keeps all rows and marks matches; otherwise search narrows the rows.
    func buildFeed(highlight: Bool) -> ConsoleFeed {
        let source = activeEntries
        var levelCounts: [ConsoleLevel: Int] = [:]
        var total = 0
        var available: LogCategory = []
        var sources = Set<String>()
        for entry in source {
            levelCounts[entry.level, default: 0] += entry.repeatCount
            total += entry.repeatCount
            available.formUnion(entry.categories)
            if let source = entry.source { sources.insert(source) }
        }

        let base = source.filter {
            levelFilter.contains($0.level)
                && (categoryFilter.isEmpty || !categoryFilter.intersection($0.categories).isEmpty)
                && (sourceFilter.isEmpty || ($0.source.map(sourceFilter.contains) ?? false))
        }

        let searching = !searchText.trimmingCharacters(in: .whitespaces).isEmpty
        var rows = base
        var matchIDs: [UInt64] = []
        var matchedSet: Set<UInt64> = []

        if searching {
            let matches = makeMatcher()
            if highlight {
                for entry in base where matches(entry) {
                    matchIDs.append(entry.id)
                    matchedSet.insert(entry.id)
                }
            } else {
                rows = base.filter(matches)
                matchIDs = rows.map(\.id)
                matchedSet = Set(matchIDs)
            }
        }

        let clampedIndex = matchIDs.isEmpty ? 0 : min(max(currentMatchIndex, 0), matchIDs.count - 1)
        let currentID = matchIDs.isEmpty ? nil : matchIDs[clampedIndex]

        return ConsoleFeed(
            rows: rows,
            matchedSet: matchedSet,
            currentMatchID: currentID,
            matchCount: matchIDs.count,
            currentMatchNumber: matchIDs.isEmpty ? 0 : clampedIndex + 1,
            isSearching: searching,
            total: total,
            levelCounts: levelCounts,
            availableCategories: available,
            availableSources: sources.sorted())
    }

    /// ordered match ids only, for keyboard navigation without building a full feed.
    func matchIDs(highlight: Bool) -> [UInt64] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let matches = makeMatcher()
        return activeEntries.filter {
            levelFilter.contains($0.level)
                && (categoryFilter.isEmpty || !categoryFilter.intersection($0.categories).isEmpty)
                && (sourceFilter.isEmpty || ($0.source.map(sourceFilter.contains) ?? false))
                && matches($0)
        }.map(\.id)
    }

    /// compiled predicate for the current search; falls back to a literal substring test
    /// when regex is off or the pattern fails to compile.
    private func makeMatcher() -> (ConsoleEntry) -> Bool {
        let query = searchText
        if useRegex, let regex = try? NSRegularExpression(pattern: query, options: [.caseInsensitive]) {
            return { entry in
                Self.regexHit(regex, entry.text) || (entry.source.map { Self.regexHit(regex, $0) } ?? false)
            }
        }
        return { entry in
            entry.text.localizedCaseInsensitiveContains(query)
                || (entry.source?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private static func regexHit(_ regex: NSRegularExpression, _ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}

/// everything the console panes need for one render, derived from `WorkspaceState` in a single pass.
struct ConsoleFeed {
    var rows: [ConsoleEntry]
    var matchedSet: Set<UInt64>
    var currentMatchID: UInt64?
    var matchCount: Int
    var currentMatchNumber: Int
    var isSearching: Bool
    var total: Int
    var levelCounts: [ConsoleLevel: Int]
    var availableCategories: LogCategory
    var availableSources: [String]

    func isMatched(_ id: UInt64) -> Bool { matchedSet.contains(id) }
}

struct Banner: Identifiable {
    enum Kind { case error, warning, info }
    let id = UUID()
    var kind: Kind
    var title: String
    var message: String
    var actionTitle: String?
    var action: (@MainActor () -> Void)?
}
