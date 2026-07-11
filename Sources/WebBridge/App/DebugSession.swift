import AppKit
import Foundation
import Observation

/// one live debugging session against a single target: the CDP connection, the console and
/// network capture buffers, the native device-log stream, and everything derived from them.
///
/// the session owns the whole lifetime from "open a target" to "back to overview". constructing
/// it starts the connection; `close()` tears down every task and socket. because that state lives
/// here rather than as flat fields on `AppStore`, opening and closing a target can't leak a task
/// or forget to reset a buffer - the session is simply created and released.
@MainActor
@Observable
final class DebugSession {
    /// the view-facing state for this session. a value type so its derivations (`buildFeed`,
    /// `filteredNetwork`) stay pure and unit-testable; the session wraps it with the orchestration.
    var workspace: WorkspaceState

    @ObservationIgnored private let ids: Sequence64
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let connection: CDPConnection?
    @ObservationIgnored let deviceLogFactory: @MainActor () -> DeviceLogResult
    @ObservationIgnored private let onFrameworkDetected: @MainActor (String) -> Void

    @ObservationIgnored var consoleBuffer: RingBuffer<ConsoleEntry>
    @ObservationIgnored var consoleFlushPending = false

    // network capture, keyed by requestId and flushed to the workspace on a throttle.
    @ObservationIgnored var networkByID: [String: NetworkEntry] = [:]
    @ObservationIgnored var networkOrder: [String] = []
    @ObservationIgnored var networkFlushPending = false

    // native device logs (adb logcat / idevicesyslog), flushed like the console buffer.
    @ObservationIgnored var deviceLogService: (any DeviceLogSource)?
    @ObservationIgnored var deviceLogTask: Task<Void, Never>?
    @ObservationIgnored var deviceLogBuffer: RingBuffer<ConsoleEntry>
    @ObservationIgnored var deviceLogFlushPending = false

    @ObservationIgnored private var cdpTask: Task<Void, Never>?
    @ObservationIgnored private var detectTask: Task<Void, Never>?
    @ObservationIgnored var storageLoadTask: Task<Void, Never>?

    init(target: Target,
         url: URL?,
         webkit: Bool,
         deviceLogAvailable: Bool,
         seed: [ConsoleEntry],
         detectedFramework: String?,
         ids: Sequence64,
         settings: AppSettings,
         deviceLogFactory: @escaping @MainActor () -> DeviceLogResult,
         onFrameworkDetected: @escaping @MainActor (String) -> Void) {
        self.ids = ids
        self.settings = settings
        self.deviceLogFactory = deviceLogFactory
        self.onFrameworkDetected = onFrameworkDetected

        var buffer = RingBuffer<ConsoleEntry>(capacity: settings.consoleBufferSize)
        buffer.append(contentsOf: seed)   // prior scrollback so a reload/reconnect keeps context
        self.consoleBuffer = buffer
        self.deviceLogBuffer = RingBuffer(capacity: settings.consoleBufferSize)

        var state = WorkspaceState(target: target)
        state.isWebKit = webkit
        state.detectedFramework = detectedFramework
        state.deviceLogAvailable = deviceLogAvailable
        state.entries = buffer.elements
        self.workspace = state

        self.connection = url.map { CDPConnection(url: $0, ids: ids, webkit: webkit) }
        if connection == nil { workspace.connectionClosed = true }
    }

    /// the live console scrollback, for `AppStore` to stash under the target identity on close.
    var consoleScrollback: [ConsoleEntry] { consoleBuffer.elements }

    var activeConnection: CDPConnection? { connection }

    // MARK: - Lifecycle

    func start() {
        guard let connection else { return }
        cdpTask = Task { [weak self] in
            await connection.start()
            for await event in connection.events {
                self?.handleCDP(event)
            }
        }
        detectTask = Task { [weak self] in
            guard let name = await connection.detectFramework(), let self else { return }
            self.workspace.detectedFramework = name
            self.onFrameworkDetected(name)
        }
    }

    func close() {
        cdpTask?.cancel()
        cdpTask = nil
        detectTask?.cancel()
        detectTask = nil
        storageLoadTask?.cancel()
        storageLoadTask = nil
        stopDeviceLog()
        if let connection { Task { await connection.close() } }
    }

    // MARK: - CDP events

    private func handleCDP(_ event: CDPEvent) {
        switch event {
        case .console(let entry):
            appendConsole(entry)
        case .navigated(let url):
            appendConsole(ConsoleEntry(id: ids.next(), level: .info, kind: .navigation,
                                       text: "navigated → \(url)"))
            workspace.target.url = url
        case .network(let signal):
            applyNetwork(signal)
        case .closed:
            workspace.connectionClosed = true
        }
    }

    // MARK: - Console buffer

    func appendConsole(_ entry: ConsoleEntry) {
        if let last = consoleBuffer.last, last.isDuplicate(of: entry) {
            var merged = last
            merged.repeatCount += 1
            consoleBuffer.replaceLast(merged)
        } else {
            consoleBuffer.append(entry)
        }
        scheduleConsoleFlush()
    }

    private func scheduleConsoleFlush() {
        guard !consoleFlushPending else { return }
        consoleFlushPending = true
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            guard let self else { return }
            self.consoleFlushPending = false
            self.workspace.entries = self.consoleBuffer.elements
        }
    }

    func clearConsole() {
        if workspace.logSource == .device {
            deviceLogBuffer.clear()
            workspace.deviceEntries = []
        } else {
            consoleBuffer.clear()
            workspace.entries = []
        }
    }

    /// clears whichever pane is active; Storage refreshes instead of clearing.
    func clearActiveTab() {
        switch workspace.tab {
        case .network: clearNetwork()
        case .storage: loadStorage(force: true)
        default: clearConsole()
        }
    }

    // MARK: - Console feed

    /// fully-derived console view for the current render; built once so panes don't re-scan the buffer.
    var consoleFeed: ConsoleFeed {
        workspace.buildFeed(highlight: settings.consoleHighlightMatches)
    }

    /// resets the find cursor so navigation restarts from the first match.
    func setConsoleSearch(_ text: String) {
        workspace.searchText = text
        workspace.currentMatchIndex = 0
    }

    func setConsoleRegex(_ on: Bool) {
        workspace.useRegex = on
        workspace.currentMatchIndex = 0
    }

    func toggleConsoleCategory(_ category: LogCategory) {
        if workspace.categoryFilter.contains(category) {
            workspace.categoryFilter.remove(category)
        } else {
            workspace.categoryFilter.insert(category)
        }
        workspace.currentMatchIndex = 0
    }

    func toggleConsoleSource(_ source: String) {
        if workspace.sourceFilter.contains(source) {
            workspace.sourceFilter.remove(source)
        } else {
            workspace.sourceFilter.insert(source)
        }
        workspace.currentMatchIndex = 0
    }

    func clearConsoleSources() {
        workspace.sourceFilter = []
        workspace.currentMatchIndex = 0
    }

    func applyConsoleFilter(_ text: String) { setConsoleSearch(text) }
    func saveCurrentConsoleFilter() { settings.saveConsoleFilter(workspace.searchText) }

    // MARK: - Console find navigation

    func consoleFindNext() { moveConsoleMatch(by: 1) }
    func consoleFindPrev() { moveConsoleMatch(by: -1) }

    private func moveConsoleMatch(by delta: Int) {
        let count = workspace.matchIDs(highlight: settings.consoleHighlightMatches).count
        guard count > 0 else { return }
        // wrap past the last match back to the first
        workspace.currentMatchIndex = ((workspace.currentMatchIndex + delta) % count + count) % count
    }

    func consoleGotoMatch(_ oneBased: Int) {
        let count = workspace.matchIDs(highlight: settings.consoleHighlightMatches).count
        guard count > 0 else { return }
        workspace.currentMatchIndex = min(max(oneBased - 1, 0), count - 1)
    }

    var hasConsoleMatches: Bool {
        workspace.tab == .console && !workspace.searchText.isEmpty
    }

    // MARK: - Tabs & source

    func selectWorkspaceTab(_ tab: WorkspaceTab) {
        workspace.tab = tab
        if tab == .storage { loadStorage() }
    }

    /// swaps the console pane between WebView and native device logs; starts logcat lazily.
    func setLogSource(_ source: LogSource) {
        guard workspace.logSource != source else { return }
        workspace.logSource = source
        workspace.currentMatchIndex = 0
        workspace.sourceFilter = []   // sources differ between WebView and device
        if source == .device { startDeviceLog() }
    }

    func toggleNetworkType(_ type: String) {
        if workspace.networkTypeFilter.contains(type) {
            workspace.networkTypeFilter.remove(type)
        } else {
            workspace.networkTypeFilter.insert(type)
        }
    }

    // MARK: - Evaluate & reload

    func evaluate(_ expression: String) {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let connection else { return }
        appendConsole(ConsoleEntry(id: ids.next(), level: .log, kind: .system, text: "❯ \(trimmed)"))
        Task { [weak self] in
            let result = (try? await connection.evaluate(trimmed)) ?? "evaluation failed"
            guard let self else { return }
            self.appendConsole(ConsoleEntry(id: self.ids.next(), level: .log, kind: .system, text: "→ \(result)"))
        }
    }

    func reloadTarget() {
        Task { [connection] in await connection?.reload() }
    }

    // MARK: - Export

    func exportConsole(_ rows: [ConsoleEntry]) {
        let text = rows.map { "\($0.timeLabel)  [\($0.level.label)] \($0.text)" }.joined(separator: "\n")
        Self.savePanel(defaultName: "console.txt", content: text)
    }

    func exportHAR() {
        let har = HARExport.string(from: workspace.filteredNetwork(), pageURL: workspace.target.url)
        Self.savePanel(defaultName: "network.har", content: har)
    }

    static func savePanel(defaultName: String, content: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }
}
