import SwiftUI

struct ConsoleWorkspace: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if let session = store.session {
            let workspace = session.workspace
            let feed = session.consoleFeed
            ZStack {
                switch workspace.tab {
                case .console: consolePane(feed).transition(.opacity)
                case .network: networkPane.transition(.opacity)
                case .storage: StorageList().transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: workspace.tab)
            .navigationTitle(store.label(for: workspace.target))
            .navigationSubtitle(subtitle(workspace))
            .searchable(text: tabSearch, prompt: tabPrompt)
            .toolbar { toolbar(workspace, feed: feed) }
        }
    }

    private func consolePane(_ feed: ConsoleFeed) -> some View {
        let source = store.session?.workspace.logSource ?? .webView
        let deviceState = store.session?.workspace.deviceLogState ?? .ready
        let guidance = source == .device && deviceState != .ready
        return VStack(spacing: 0) {
            ConsoleFilterBar(feed: feed)
            Divider()
            if feed.isSearching {
                ConsoleFindBar(feed: feed)
                    .transition(.move(edge: .top).combined(with: .opacity))
                Divider()
            }
            ZStack {
                if guidance {
                    DeviceLogUnavailable(state: deviceState)
                        .id("device-guidance")
                        .transition(.opacity)
                } else {
                    ConsoleLogList(feed: feed)
                        .id(source)
                        .transition(.opacity)
                }
            }
            // native device logs have no JS context, so the eval REPL is WebView-only
            if source == .webView {
                Divider()
                EvalField()
            }
        }
        .animation(.snappy(duration: 0.2), value: feed.isSearching)
        .animation(.easeInOut(duration: 0.18), value: source)
        .animation(.easeInOut(duration: 0.18), value: deviceState)
    }

    private var networkPane: some View {
        VStack(spacing: 0) {
            NetworkFilterBar()
            Divider()
            NetworkList()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func toolbar(_ workspace: WorkspaceState, feed: ConsoleFeed) -> some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button("Back", systemImage: "chevron.backward") { store.backToOverview() }
                .help("Back to Overview")
        }
        if workspace.availableTabs.count > 1 {
            ToolbarItem(placement: .principal) {
                Picker("Pane", selection: tabBinding) {
                    ForEach(workspace.availableTabs) { tab in
                        Label(tab.title, systemImage: tab.symbol).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
        ToolbarItemGroup {
            if workspace.tab == .console {
                Toggle("Highlight", systemImage: "highlighter", isOn: highlightBinding)
                    .help("Highlight matches instead of hiding non-matching rows")
                savedFiltersMenu(workspace)
            }
            Button("Reload", systemImage: "arrow.clockwise") { store.session?.reloadTarget() }
                .help("Reload Target")
            if workspace.tab == .storage {
                Button("Refresh", systemImage: "arrow.clockwise.circle") { store.session?.loadStorage(force: true) }
                    .help("Refresh Storage")
            } else {
                Button("Clear", systemImage: "trash") { store.session?.clearActiveTab() }
                    .help("Clear")
            }
            exportMenu(workspace, feed: feed)
            Button("Chrome DevTools", systemImage: "arrow.up.forward.app") {
                store.openInChrome(workspace.target)
            }
            .help("Open in Chrome DevTools")
            if workspace.target.canOpenInSafari {
                Button("Safari", systemImage: "safari") { store.openInSafari(workspace.target) }
                    .help("Open in Safari Web Inspector")
            }
        }
    }

    private func exportMenu(_ workspace: WorkspaceState, feed: ConsoleFeed) -> some View {
        Menu("Export", systemImage: "square.and.arrow.up") {
            switch workspace.tab {
            case .console:
                Button("Save Console…", systemImage: "doc.text") { store.session?.exportConsole(feed.rows) }
                Button("Copy All", systemImage: "doc.on.doc") { Clipboard.copy(consoleText(feed.rows)) }
            case .network:
                Button("Save as HAR…", systemImage: "doc.badge.arrow.up") { store.session?.exportHAR() }
                Button("Copy All URLs", systemImage: "doc.on.doc") {
                    Clipboard.copy(workspace.filteredNetwork().map(\.url).joined(separator: "\n"))
                }
            case .storage:
                Button("Copy All", systemImage: "doc.on.doc") { Clipboard.copy(storageText(workspace.storage)) }
            }
        }
        .help("Export the current pane")
    }

    private func savedFiltersMenu(_ workspace: WorkspaceState) -> some View {
        Menu("Saved Filters", systemImage: "bookmark") {
            Button("Save Current Search", systemImage: "plus") { store.session?.saveCurrentConsoleFilter() }
                .disabled(workspace.searchText.isEmpty)
            let saved = store.settings.savedConsoleFilters
            if !saved.isEmpty {
                Section("Apply") {
                    ForEach(saved, id: \.self) { filter in
                        Button(filter) { store.session?.applyConsoleFilter(filter) }
                    }
                }
                Menu("Remove", systemImage: "trash") {
                    ForEach(saved, id: \.self) { filter in
                        Button(filter) { store.settings.removeConsoleFilter(filter) }
                    }
                }
            }
        }
        .help("Save the current search and re-apply it later")
    }

    // MARK: - Bindings & text

    private var tabBinding: Binding<WorkspaceTab> {
        Binding(get: { store.session?.workspace.tab ?? .console }, set: { store.session?.selectWorkspaceTab($0) })
    }

    private var highlightBinding: Binding<Bool> {
        Binding(
            get: { store.settings.consoleHighlightMatches },
            set: { store.settings.consoleHighlightMatches = $0 })
    }

    private var tabSearch: Binding<String> {
        Binding(
            get: {
                switch store.session?.workspace.tab {
                case .network: return store.session?.workspace.networkSearch ?? ""
                case .storage: return store.session?.workspace.storageSearch ?? ""
                default: return store.session?.workspace.searchText ?? ""
                }
            },
            set: { value in
                switch store.session?.workspace.tab {
                case .network: store.session?.workspace.networkSearch = value
                case .storage: store.session?.workspace.storageSearch = value
                default: store.session?.setConsoleSearch(value)
                }
            })
    }

    private var tabPrompt: String {
        switch store.session?.workspace.tab {
        case .network: return "Filter Requests"
        case .storage: return "Filter Keys"
        default: return "Filter Messages"
        }
    }

    private func consoleText(_ rows: [ConsoleEntry]) -> String {
        rows.map { "\($0.timeLabel)  [\($0.level.label)] \($0.text)" }.joined(separator: "\n")
    }

    private func storageText(_ snapshot: StorageSnapshot?) -> String {
        guard let snapshot else { return "" }
        var lines: [String] = []
        if !snapshot.cookies.isEmpty {
            lines.append("# Cookies")
            lines += snapshot.cookies.map { "\($0.name)=\($0.value)" }
        }
        if !snapshot.local.isEmpty {
            lines.append("# Local Storage")
            lines += snapshot.local.map { "\($0.key)=\($0.value)" }
        }
        if !snapshot.session.isEmpty {
            lines.append("# Session Storage")
            lines += snapshot.session.map { "\($0.key)=\($0.value)" }
        }
        return lines.joined(separator: "\n")
    }

    private func subtitle(_ workspace: WorkspaceState) -> String {
        var parts = [workspace.target.url.isEmpty ? workspace.target.engine : workspace.target.url]
        if let package = workspace.target.appPackage { parts.append(package) }
        if let framework = workspace.detectedFramework { parts.append(framework) }
        if workspace.connectionClosed { parts.append("Disconnected") }
        return parts.joined(separator: " · ")
    }
}
