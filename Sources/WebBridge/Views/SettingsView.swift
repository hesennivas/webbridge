import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                generalTab
            }
            Tab("Tools", systemImage: "wrench.and.screwdriver") {
                toolsTab
            }
        }
        .frame(width: 540)
    }

    private var generalTab: some View {
        @Bindable var settings = store.settings
        return Form {
            Section {
                Stepper("WebView scan interval: \(Int(settings.socketScanInterval)) s",
                        value: $settings.socketScanInterval, in: 2...15, step: 1)
                Stepper("Console buffer: \(settings.consoleBufferSize.formatted()) entries",
                        value: $settings.consoleBufferSize, in: 1000...50000, step: 1000)
            }
            Section {
                Toggle("Open Safari Web Inspector automatically", isOn: $settings.safariAutomationEnabled)
                LabeledContent("Accessibility Permission") {
                    HStack {
                        Text(SafariAutomation.isTrusted ? "Granted" : "Not Granted")
                            .foregroundStyle(SafariAutomation.isTrusted ? Color.secondary : Color.orange)
                        Button("Setup Assistant…") { store.setupVisible = true }
                    }
                }
            } footer: {
                Text("Automation clicks Safari's Develop menu to open the exact target. It requires the Accessibility permission.")
            }
        }
        .formStyle(.grouped)
    }

    private var toolsTab: some View {
        @Bindable var settings = store.settings
        return Form {
            Section("Command-Line Tools") {
                TextField("adb path", text: $settings.adbPathOverride, prompt: Text("Auto-detected"))
                    .font(.mono(12))
                TextField("ios_webkit_debug_proxy path", text: $settings.iwdpPathOverride, prompt: Text("Auto-detected"))
                    .font(.mono(12))
                TextField("idevicesyslog path", text: $settings.syslogPathOverride, prompt: Text("Auto-detected"))
                    .font(.mono(12))
                LabeledContent("Status") {
                    HStack {
                        Text(statusText)
                            .foregroundStyle(.secondary)
                        Button("Re-detect") { Task { await store.resolveTools() } }
                    }
                }
            }
            Section("Port Forwarding") {
                Stepper("Range start: \(String(settings.portLower))",
                        value: $settings.portLower, in: 1024...65000)
                Stepper("Range end: \(String(settings.portUpper))",
                        value: $settings.portUpper, in: 1024...65000)
            }
        }
        .formStyle(.grouped)
    }

    private var statusText: String {
        [
            store.tools.hasAdb ? "adb found" : "adb missing",
            store.tools.hasIWDP ? "iwdp found" : "iwdp missing",
            store.tools.hasSyslog ? "idevicesyslog found" : "idevicesyslog missing"
        ].joined(separator: " · ")
    }
}
