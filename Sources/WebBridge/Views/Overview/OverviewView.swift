import SwiftUI

struct OverviewView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        content
            .navigationTitle(store.selectedDevice?.name ?? "webbridge")
            .toolbar {
                if showsTabPicker {
                    ToolbarItem(placement: .principal) {
                        Picker("View", selection: tabSelection) {
                            ForEach(OverviewTab.allCases) { tab in
                                Label(tab.title, systemImage: tab.symbol).tag(tab)
                            }
                        }
                        .pickerStyle(.segmented)
                        // pins the intrinsic width so the centered picker doesn't recompute
                        // its frame while the sidebar animates.
                        .fixedSize()
                    }
                }
            }
    }

    private var showsTabPicker: Bool {
        store.selectedDevice?.isAndroid == true
    }

    private var tabSelection: Binding<OverviewTab> {
        Binding(
            get: { store.overviewTab },
            set: { store.selectTab($0) }
        )
    }

    @ViewBuilder
    private var content: some View {
        ZStack {
            switch showsTabPicker ? store.overviewTab : .webviews {
            case .webviews: TargetListView().transition(.opacity)
            case .info: InfoPanel().transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: store.overviewTab)
    }
}
