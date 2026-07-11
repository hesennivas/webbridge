import SwiftUI

struct InfoPanel: View {
    @Environment(AppStore.self) private var store

    private var serial: String? { store.selectedDevice?.serial }

    var body: some View {
        ZStack {
            if let device = store.selectedDevice, device.isIOS {
                iosInfo(device)
            } else if let serial, let info = store.deviceInfoByDevice[serial] {
                androidInfo(info, serial: serial)
                    .transition(.opacity)
            } else {
                loadingState
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: infoLoaded)
        .overlay(alignment: .topTrailing) {
            if let serial, store.infoLoading.contains(serial), store.deviceInfoByDevice[serial] != nil {
                ProgressView()
                    .controlSize(.small)
                    .padding(12)
            }
        }
        .onAppear { if let serial { store.loadDeviceInfo(serial: serial) } }
    }

    private var infoLoaded: Bool {
        serial.map { store.deviceInfoByDevice[$0] != nil } ?? true
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Reading device properties over adb…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func androidInfo(_ info: DeviceInfo, serial: String) -> some View {
        Form {
            Section("Device") {
                row("Model", info.model)
                row("Android", [info.androidVersion, info.sdk.map { "SDK \($0)" }].compactMap { $0 }.joined(separator: " · "))
                row("ABI", info.abi)
                row("Build", info.buildNumber)
                row("Battery", batteryText(info))
                row("Screen", [info.screenResolution, info.screenDensity.map { "\($0) dpi" }].compactMap { $0 }.joined(separator: " · "))
                row("Foreground", info.foregroundApp)
                row("WebView", info.webViewProvider)
            }
            Section("Installed Apps (\(info.packages.count))") {
                ForEach(info.packages) { app in
                    PackageRow(app: app, serial: serial)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func iosInfo(_ device: Device) -> some View {
        Form {
            Section("Device") {
                row("Name", device.name)
                row("iOS", device.osVersion)
                row("UDID", device.id)
                row("Inspector", device.state == .degraded ? "Bridge unavailable" : "Connected")
            }
        }
        .formStyle(.grouped)
    }

    private func row(_ label: String, _ value: String?) -> some View {
        LabeledContent(label) {
            Text(value?.isEmpty == false ? value! : "—")
                .textSelection(.enabled)
        }
    }

    private func batteryText(_ info: DeviceInfo) -> String? {
        guard let level = info.batteryLevel else { return nil }
        var text = "\(level)%"
        if info.batteryCharging == true { text += " · charging" }
        if let temp = info.batteryTemperature { text += " · \(String(format: "%.1f", temp))°C" }
        return text
    }
}

private struct PackageRow: View {
    @Environment(AppStore.self) private var store
    let app: InstalledApp
    let serial: String

    var body: some View {
        LabeledContent {
            Menu {
                Button("Launch") { store.appAction(.launch, package: app.package, serial: serial) }
                Button("Force Stop") { store.appAction(.forceStop, package: app.package, serial: serial) }
                Button("Clear Data…", role: .destructive) {
                    store.appAction(.clearData, package: app.package, serial: serial)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        } label: {
            Text(app.package)
                .font(.mono(12))
                .textSelection(.enabled)
        }
    }
}
