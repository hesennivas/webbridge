import SwiftUI

struct AppCommands: Commands {
    let store: AppStore

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}

        CommandMenu("Inspect") {
            Button("Back to Overview") { store.backToOverview() }
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(store.session == nil)

            Divider()

            Button("Open in Chrome DevTools") {
                if let target = store.session?.workspace.target { store.openInChrome(target) }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(store.session == nil)

            Button("Reload Target") { store.session?.reloadTarget() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(store.session == nil)

            Button("Clear Console") { store.session?.clearConsole() }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(store.session == nil)

            Divider()

            Button("Find Next") { store.session?.consoleFindNext() }
                .keyboardShortcut("g", modifiers: .command)
                .disabled(store.session?.hasConsoleMatches != true)

            Button("Find Previous") { store.session?.consoleFindPrev() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(store.session?.hasConsoleMatches != true)
        }

        CommandGroup(after: .toolbar) {
            Button("WebViews Tab") { store.selectTab(.webviews) }
                .keyboardShortcut("1", modifiers: .command)
            Button("Device Info Tab") { store.selectTab(.info) }
                .keyboardShortcut("2", modifiers: .command)
            Divider()
            Button("Refresh Device Info") {
                if let serial = store.selectedDevice?.serial { store.loadDeviceInfo(serial: serial, force: true) }
            }
            .keyboardShortcut("r", modifiers: .command)
        }

        CommandGroup(replacing: .help) {
            Button("Setup Assistant") { store.setupVisible = true }
        }
    }
}
