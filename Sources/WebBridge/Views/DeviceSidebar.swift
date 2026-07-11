import SwiftUI

struct DeviceSidebar: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        List(selection: selection) {
            section("Android", devices: store.onlineAndroid)
            section("iOS", devices: store.onlineIOS)
            section("Offline", devices: store.offlineDevices)
        }
        .listStyle(.sidebar)
        .overlay {
            if store.devices.isEmpty {
                Text("No Devices")
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .animation(.default, value: store.devices)
        .navigationTitle("Devices")
    }

    private var selection: Binding<String?> {
        Binding(
            get: { store.selectedDeviceID },
            set: { id in if let id { store.selectDevice(id) } }
        )
    }

    @ViewBuilder
    private func section(_ title: String, devices: [Device]) -> some View {
        if !devices.isEmpty {
            Section(title) {
                ForEach(devices) { device in
                    DeviceRow(device: device)
                        .tag(device.id)
                }
            }
        }
    }
}

private struct DeviceRow: View {
    let device: Device

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: device.isIOS ? "iphone" : "smartphone")
                .foregroundStyle(device.isOnline ? Color.accentColor : Color.secondary)
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if device.isIOS { parts.append("iOS") }
        if let os = device.osVersion { parts.append(os) }
        if device.isWireless { parts.append("Wi‑Fi") }
        if !device.isOnline { parts.append(device.state.label) }
        else if device.isAndroid, let model = device.model, model != device.name { parts.append(model) }
        return parts.isEmpty ? device.id.prefix(10).description : parts.joined(separator: " · ")
    }
}
