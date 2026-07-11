import SwiftUI

struct ConsoleFilterBar: View {
    @Environment(AppStore.self) private var store
    let feed: ConsoleFeed

    var body: some View {
        HStack(spacing: 8) {
            if let sources = store.session?.workspace.availableLogSources, sources.count > 1 {
                Picker("Source", selection: sourceBinding) {
                    ForEach(sources) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .help("Switch between WebView console and native device logs")
                Divider().frame(height: 14)
            }
            Toggle("All \(feed.total)", isOn: allBinding)
                .toggleStyle(.button)
            Divider().frame(height: 14)
            ForEach(ConsoleLevel.allCases, id: \.self) { level in
                Toggle("\(level.label) \(feed.levelCounts[level] ?? 0)", isOn: binding(for: level))
                    .toggleStyle(.button)
            }

            // category chips appear only for classes actually present in the buffer
            let categories = LogCategory.known.filter { feed.availableCategories.contains($0.category) }
            if !categories.isEmpty {
                Divider().frame(height: 14)
                ForEach(categories, id: \.category.rawValue) { item in
                    Toggle(isOn: categoryBinding(item.category)) {
                        Label(item.label, systemImage: item.symbol)
                    }
                    .toggleStyle(.button)
                    .help("Show only \(item.label) messages")
                }
            }

            Spacer()

            sourcesMenu
        }
        .monospacedDigit()
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .animation(.snappy(duration: 0.2), value: feed.availableCategories)
    }

    @ViewBuilder
    private var sourcesMenu: some View {
        let active = store.session?.workspace.sourceFilter ?? []
        Menu {
            if !active.isEmpty {
                Button("Show All Sources") { store.session?.clearConsoleSources() }
                Divider()
            }
            ForEach(feed.availableSources, id: \.self) { source in
                Button { store.session?.toggleConsoleSource(source) } label: {
                    if active.contains(source) { Label(source, systemImage: "checkmark") }
                    else { Text(source) }
                }
            }
        } label: {
            Image(systemName: active.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(feed.availableSources.isEmpty)
        .foregroundStyle(active.isEmpty ? Color.secondary : Color.accentColor)
        .help("Filter by source")
    }

    private var sourceBinding: Binding<LogSource> {
        Binding(
            get: { store.session?.workspace.logSource ?? .webView },
            set: { store.session?.setLogSource($0) })
    }

    private var allBinding: Binding<Bool> {
        Binding(
            get: { store.session?.workspace.levelFilter.count == ConsoleLevel.allCases.count },
            set: { on in
                store.session?.workspace.levelFilter = on ? Set(ConsoleLevel.allCases) : []
            })
    }

    private func binding(for level: ConsoleLevel) -> Binding<Bool> {
        Binding(
            get: { store.session?.workspace.levelFilter.contains(level) ?? false },
            set: { on in
                guard var filter = store.session?.workspace.levelFilter else { return }
                if on { filter.insert(level) } else { filter.remove(level) }
                store.session?.workspace.levelFilter = filter
            })
    }

    private func categoryBinding(_ category: LogCategory) -> Binding<Bool> {
        Binding(
            get: { store.session?.workspace.categoryFilter.contains(category) ?? false },
            set: { _ in store.session?.toggleConsoleCategory(category) })
    }
}
