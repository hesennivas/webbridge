import SwiftUI

struct NetworkFilterBar: View {
    @Environment(AppStore.self) private var store

    private let classes = [2, 3, 4, 5]

    var body: some View {
        let counts = store.session?.workspace.networkClassCounts() ?? [:]
        let total = store.session?.workspace.networkEntries.count ?? 0
        HStack(spacing: 8) {
            Toggle("All \(total)", isOn: allBinding)
                .toggleStyle(.button)
            Divider().frame(height: 14)
            ForEach(classes, id: \.self) { statusClass in
                Toggle(isOn: binding(for: statusClass)) {
                    Text("\(statusClass)xx \(counts[statusClass] ?? 0)")
                        .foregroundStyle(tint(statusClass))
                }
                .toggleStyle(.button)
            }
            Spacer()

            typesMenu
        }
        .monospacedDigit()
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var typesMenu: some View {
        let types = store.session?.workspace.networkTypes() ?? []
        let active = store.session?.workspace.networkTypeFilter ?? []
        Menu {
            if !active.isEmpty {
                Button("Show All Types") { store.session?.workspace.networkTypeFilter = [] }
                Divider()
            }
            ForEach(types, id: \.self) { type in
                Button { store.session?.toggleNetworkType(type) } label: {
                    if active.contains(type) { Label(type, systemImage: "checkmark") }
                    else { Text(type) }
                }
            }
        } label: {
            Image(systemName: active.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(types.isEmpty)
        .foregroundStyle(active.isEmpty ? Color.secondary : Color.accentColor)
        .help("Filter by type")
    }

    private func tint(_ statusClass: Int) -> Color {
        switch statusClass {
        case 2: return .green
        case 3: return .blue
        case 4: return .orange
        default: return .red
        }
    }

    private var allBinding: Binding<Bool> {
        Binding(
            get: { store.session?.workspace.networkStatusFilter.isEmpty ?? true },
            set: { on in if on { store.session?.workspace.networkStatusFilter = [] } })
    }

    private func binding(for statusClass: Int) -> Binding<Bool> {
        Binding(
            get: { store.session?.workspace.networkStatusFilter.contains(statusClass) ?? false },
            set: { on in
                guard var filter = store.session?.workspace.networkStatusFilter else { return }
                if on { filter.insert(statusClass) } else { filter.remove(statusClass) }
                store.session?.workspace.networkStatusFilter = filter
            })
    }
}
