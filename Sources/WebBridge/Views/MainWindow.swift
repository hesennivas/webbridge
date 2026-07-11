import SwiftUI

struct MainWindow: View {
    @Environment(AppStore.self) private var store

    private enum Pane { case workspace, overview, noDevice }

    private var pane: Pane {
        if store.session != nil { return .workspace }
        return store.selectedDevice != nil ? .overview : .noDevice
    }

    var body: some View {
        NavigationSplitView {
            DeviceSidebar()
                .navigationSplitViewColumnWidth(min: 210, ideal: 234, max: 300)
        } detail: {
            ZStack {
                content
            }
            .animation(.snappy(duration: 0.22), value: pane)
            .overlay(alignment: .top) { BannerStack() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch pane {
        case .workspace:
            ConsoleWorkspace()
                // removal fades instead of sliding: workspace state clears before the
                // transition runs, so a slide would animate a blank pane.
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .opacity))
                .zIndex(1)
        case .overview:
            OverviewView()
                .transition(.opacity)
        case .noDevice:
            NoDeviceView()
                .transition(.opacity)
        }
    }
}
