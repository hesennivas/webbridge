import SwiftUI
import AppKit

@main
struct WebBridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = AppStore()

    var body: some Scene {
        Window("webbridge", id: "main") {
            RootView()
                .environment(store)
                .frame(minWidth: 940, minHeight: 580)
                .task { await store.start() }
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands { AppCommands(store: store) }

        Settings {
            SettingsView()
                .environment(store)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        ForwardRegistry.shared.removeAllSynchronously()
        return .terminateNow
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}

private struct RootView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        MainWindow()
            .sheet(isPresented: Binding(
                get: { store.setupVisible },
                set: { store.setupVisible = $0 })) {
                SetupWizard()
                    .environment(store)
            }
    }
}
