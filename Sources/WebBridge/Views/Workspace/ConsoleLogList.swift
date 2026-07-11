import SwiftUI
import AppKit

struct ConsoleLogList: View {
    @Environment(AppStore.self) private var store
    let feed: ConsoleFeed
    @State private var awayFromBottom = false
    // pinning is explicit: only a double-click follows new output, so it never re-pins on its own
    @State private var pinned = false
    @State private var flashing = false

    var body: some View {
        let entries = feed.rows
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if entries.isEmpty {
                        HStack(spacing: 8) {
                            if showsSpinner {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(emptyLabel)
                                .font(.mono(11))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(16)
                    }
                    ForEach(entries) { entry in
                        ConsoleRow(entry: entry,
                                   highlighted: feed.isMatched(entry.id),
                                   isCurrentMatch: feed.currentMatchID == entry.id)
                            .equatable()
                            .id(entry.id)
                    }
                    if store.session?.workspace.connectionClosed == true {
                        closedDivider
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
            // land on the newest entry when the pane appears (open, tab, or source switch)
            .onAppear {
                DispatchQueue.main.async { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            // pinned locks the view to the bottom: scrolling is frozen and new output stays in view
            .scrollDisabled(pinned)
            .onChange(of: pinned) { _, isPinned in
                if isPinned { withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
            .onChange(of: entries.count) {
                if pinned { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: feed.currentMatchID) { _, id in
                if let id { withAnimation(.easeInOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) } }
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y < geometry.contentSize.height - geometry.containerSize.height - 40
            } action: { _, away in awayFromBottom = away }
            .overlay(alignment: .bottomTrailing) {
                if awayFromBottom || pinned || flashing {
                    scrollToBottomButton(proxy)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.2), value: awayFromBottom)
            .animation(.snappy(duration: 0.2), value: pinned)
        }
    }

    private func scrollToBottomButton(_ proxy: ScrollViewProxy) -> some View {
        let highlighted = pinned || flashing
        return Image(systemName: pinned ? "arrow.down.to.line" : "arrow.down")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(highlighted ? Color.white : Color.primary)
            .padding(10)
            .glassEffect(highlighted ? .regular.tint(.accentColor).interactive() : .regular.interactive(),
                         in: .circle)
            .padding(16)
            .contentShape(Circle())
            .onTapGesture(count: 2) {
                pinned = true
            }
            .onTapGesture(count: 1) {
                if pinned {
                    pinned = false
                } else {
                    scrollToBottom(proxy)
                    flash()
                }
            }
            .help(pinned ? "Pinned to latest, click to unpin" : "Scroll to latest, double-click to pin")
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
    }

    private func flash() {
        flashing = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            flashing = false
        }
    }

    private var isDeviceSource: Bool { store.session?.workspace.logSource == .device }

    private var showsSpinner: Bool {
        guard !feed.isSearching else { return false }
        return isDeviceSource || store.session?.workspace.connectionClosed != true
    }

    private var emptyLabel: String {
        if feed.isSearching { return "No matching output" }
        return isDeviceSource ? "Waiting for device logs…" : "Waiting for console output…"
    }

    private var closedDivider: some View {
        HStack(spacing: 8) {
            VStack { Divider() }
            Text("Target Gone")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize()
            VStack { Divider() }
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
    }
}

// equatable so the periodic console flush skips re-evaluating unchanged visible rows
private struct ConsoleRow: View, Equatable {
    let entry: ConsoleEntry
    var highlighted = false
    var isCurrentMatch = false
    @State private var expanded = false

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.entry == rhs.entry && lhs.highlighted == rhs.highlighted && lhs.isCurrentMatch == rhs.isCurrentMatch
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 8) {
                Text(entry.timeLabel)
                    .font(.mono(9.5))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 1)

                Image(systemName: entry.level.glyph)
                    .font(.system(size: 9))
                    .foregroundStyle(entry.level.tint)
                    .frame(width: 12)
                    .padding(.top, 2)

                Text(entry.text)
                    .font(.mono(11))
                    .foregroundStyle(rowColor)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                if entry.repeatCount > 1 {
                    Text("\(entry.repeatCount)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(.quaternary))
                }

                Spacer(minLength: 8)

                if let source = entry.source {
                    Text(source)
                        .font(.mono(9.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            if expanded, !entry.stack.isEmpty {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(entry.stack.enumerated()), id: \.offset) { _, frame in
                        Text(frame)
                            .font(.mono(9.5))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, 20)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 2.5)
        .background(rowBackground)
        .overlay(alignment: .leading) {
            if isCurrentMatch {
                Rectangle().fill(Color.accentColor).frame(width: 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !entry.stack.isEmpty {
                withAnimation(.snappy(duration: 0.18)) { expanded.toggle() }
            }
        }
        .contextMenu { ConsoleRowMenu(entry: entry) }
    }

    private var rowColor: Color {
        switch entry.kind {
        case .navigation: return .secondary
        case .exception: return .red
        default: return entry.level == .error ? .red : .primary
        }
    }

    private var rowBackground: Color {
        if isCurrentMatch { return .orange.opacity(0.32) }
        if highlighted { return .yellow.opacity(0.22) }
        switch entry.level {
        case .error: return .red.opacity(0.07)
        case .warning: return .orange.opacity(0.07)
        default: return .clear
        }
    }
}

/// content-aware copy actions: plain text always, plus JSON / cURL when the line carries them.
private struct ConsoleRowMenu: View {
    let entry: ConsoleEntry

    var body: some View {
        Button("Copy Message") { Clipboard.copy(entry.text) }
        Button("Copy with Timestamp") { Clipboard.copy("\(entry.timeLabel)  \(entry.text)") }

        if entry.categories.contains(.json), let json = LogAnalysis.prettyJSON(from: entry.text) {
            Button("Copy JSON", systemImage: "curlybraces") { Clipboard.copy(json) }
        }

        if entry.categories.contains(.api) {
            Divider()
            if let url = LogAnalysis.firstURL(in: entry.text) {
                Button("Copy URL", systemImage: "link") { Clipboard.copy(url) }
                Button("Open URL", systemImage: "safari") {
                    if let parsed = URL(string: url) { NSWorkspace.shared.open(parsed) }
                }
            }
            if let curl = LogAnalysis.curl(for: entry.text) {
                Button("Copy as cURL", systemImage: "terminal") { Clipboard.copy(curl) }
            }
        }

        if !entry.stack.isEmpty {
            Divider()
            Button("Copy Stack Trace", systemImage: "list.bullet.indent") {
                Clipboard.copy(entry.stack.joined(separator: "\n"))
            }
        }
    }
}
