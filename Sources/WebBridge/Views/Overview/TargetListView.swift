import SwiftUI

struct TargetListView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        content
            .searchable(text: searchText, placement: .toolbar, prompt: "Filter by Title or URL")
    }

    private enum Phase: Equatable { case scanning, empty, list }

    @ViewBuilder
    private var content: some View {
        let pinned = store.pinnedItems
        let groups = store.selectedTargetGroups
        let phase: Phase = (pinned.isEmpty && groups.isEmpty)
            ? (store.selectedScanPending ? .scanning : .empty)
            : .list
        ZStack {
            switch phase {
            case .scanning:
                scanningState.transition(.opacity)
            case .empty:
                emptyState.transition(.opacity)
            case .list:
                targetList(pinned: pinned, groups: groups).transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: phase)
    }

    private func targetList(pinned: [PinnedItem], groups: [TargetGroup]) -> some View {
        List {
            if !pinned.isEmpty {
                Section {
                    ForEach(pinned) { item in PinnedRow(item: item) }
                } header: {
                    Label("Pinned", systemImage: "pin.fill")
                }
            }
            ForEach(groups) { group in
                Section(group.label) {
                    ForEach(group.targets) { target in TargetRow(target: target) }
                }
            }
        }
        .listStyle(.inset)
        .animation(.default, value: store.selectedTargets)
        // Rebuild the list when the pin set changes: moving a row between the Pinned
        // and app sections otherwise leaves NSTableView with a stale, clipped row height.
        .id(store.settings.pinnedTargets)
    }

    private var scanningState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Scanning for WebViews…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var emptyState: some View {
        if store.selectedHasPages && !store.overviewSearch.isEmpty {
            ContentUnavailableView.search(text: store.overviewSearch)
        } else {
            ContentUnavailableView {
                Label("No Inspectable WebViews", systemImage: "globe.badge.chevron.backward")
            } description: {
                Text(emptyDescription)
            }
        }
    }

    private var searchText: Binding<String> {
        Binding(get: { store.overviewSearch }, set: { store.overviewSearch = $0 })
    }

    /// iOS requirements trip people up: unlike Android there is no automatic exposure.
    /// Every iOS WebView must opt in with `isInspectable = true`.
    private var emptyDescription: String {
        if store.selectedDevice?.isIOS == true {
            return "For Safari, unlock the device and keep a tab open with Settings → Safari → Advanced → Web Inspector enabled. App WebViews only appear when the app sets isInspectable = true (iOS 16.4+). This is required for debug builds too, not just release. If a device is connected but nothing shows, check the [webbridge/ios] log."
        }
        return "Debuggable builds expose a DevTools socket automatically. Release builds need WebView.setWebContentsDebuggingEnabled(true)."
    }
}

private struct TargetRow: View {
    @Environment(AppStore.self) private var store
    let target: Target
    @State private var editingLabel = false

    private var isPinned: Bool { store.isPinned(target) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: target.canOpenInSafari ? "safari" : "globe")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(store.label(for: target))
                        .lineLimit(1)
                    if let framework = store.frameworksByIdentity[target.pinIdentity] {
                        Text(framework)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(.quaternary))
                            .help(FrameworkDetection.guide(framework))
                    }
                }
                Text(target.url.isEmpty ? target.engine : target.url)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                PinButton(pinned: isPinned) { store.togglePin(target) }
                Button("Console") { store.openConsole(target) }
                    .buttonStyle(.borderedProminent)
                Menu("Open In") {
                    Button("Chrome DevTools") { store.openInChrome(target) }
                    if target.canOpenInSafari {
                        Button("Safari Web Inspector") { store.openInSafari(target) }
                    }
                }
                .fixedSize()
            }
            .controlSize(.small)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { store.openConsole(target) }
        .contextMenu {
            Button("Open Console") { store.openConsole(target) }
            Button("Open in Chrome DevTools") { store.openInChrome(target) }
            if target.canOpenInSafari {
                Button("Open in Safari Web Inspector") { store.openInSafari(target) }
            }
            Divider()
            Button(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash" : "pin") { store.togglePin(target) }
            Button("Rename…", systemImage: "pencil") { editingLabel = true }
        }
        .labelEditor(identity: target.pinIdentity, presented: $editingLabel)
    }
}

/// A pinned target that isn't currently present: greyed out, unpin/rename only.
private struct PinnedRow: View {
    @Environment(AppStore.self) private var store
    let item: PinnedItem
    @State private var editingLabel = false

    var body: some View {
        if let target = item.target {
            TargetRow(target: target)
        } else {
            HStack(spacing: 12) {
                Image(systemName: "globe")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.label).lineLimit(1)
                    Text("Waiting to appear…")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 8)
                PinButton(pinned: true) { store.unpin(item.identity) }
                    .controlSize(.small)
            }
            .padding(.vertical, 4)
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
            .contextMenu {
                Button("Unpin", systemImage: "pin.slash") { store.unpin(item.identity) }
                Button("Rename…", systemImage: "pencil") { editingLabel = true }
            }
            .labelEditor(identity: item.identity, presented: $editingLabel)
        }
    }
}

private struct PinButton: View {
    let pinned: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: pinned ? "pin.fill" : "pin")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(pinned ? Color.accentColor : Color.secondary)
        .help(pinned ? "Unpin" : "Pin")
    }
}

// MARK: - Label editing

private struct LabelEditor: ViewModifier {
    @Environment(AppStore.self) private var store
    let identity: String
    @Binding var presented: Bool
    @State private var draft = ""

    func body(content: Content) -> some View {
        content
            .alert("Rename Target", isPresented: $presented) {
                TextField("Label", text: $draft)
                Button("Save") { store.setLabel(draft, for: identity) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Give this target a custom name. Leave empty to clear.")
            }
            .onChange(of: presented) { _, now in if now { draft = store.labelText(for: identity) } }
    }
}

private extension View {
    func labelEditor(identity: String, presented: Binding<Bool>) -> some View {
        modifier(LabelEditor(identity: identity, presented: presented))
    }
}
