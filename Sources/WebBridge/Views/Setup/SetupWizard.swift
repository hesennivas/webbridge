import SwiftUI

struct SetupWizard: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var forward = true
    @State private var refreshToken = 0

    private let steps = ["Tools", "Android", "iOS", "Safari", "Done"]

    var body: some View {
        VStack(spacing: 0) {
            progress
            Divider()
            ScrollView {
                current
                    .padding(24)
                    .transition(.asymmetric(
                        insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
                    .id(step)
            }
            .frame(minHeight: 300)
            .clipped()
            Divider()
            controls
        }
        .frame(width: 560, height: 480)
    }

    private func go(to newStep: Int) {
        forward = newStep > step
        withAnimation(.snappy(duration: 0.3)) { step = newStep }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: Double(step + 1), total: Double(steps.count))
                .progressViewStyle(.linear)
            Text("Step \(step + 1) of \(steps.count): \(steps[step])")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    @ViewBuilder
    private var current: some View {
        switch step {
        case 0: toolsStep
        case 1: androidStep
        case 2: iosStep
        case 3: safariStep
        default: doneStep
        }
    }

    private var toolsStep: some View {
        StepScaffold(title: "Command-Line Tools",
                     subtitle: "webbridge drives adb, ios_webkit_debug_proxy, and idevicesyslog under the hood.") {
            CheckRow(ok: store.tools.hasAdb, label: "adb",
                     detail: store.tools.adb ?? "brew install android-platform-tools")
            CheckRow(ok: store.tools.hasIWDP, label: "ios_webkit_debug_proxy",
                     detail: store.tools.iwdp ?? "brew install ios-webkit-debug-proxy")
            CheckRow(ok: store.tools.hasSyslog, label: "idevicesyslog",
                     detail: store.tools.syslog ?? "brew install libimobiledevice (optional, for iOS device logs)")
            Button("Re-detect Tools", systemImage: "arrow.clockwise") {
                Task { await store.resolveTools() }
            }
        }
    }

    private var androidStep: some View {
        StepScaffold(title: "Android Device",
                     subtitle: "Enable Developer Options → USB debugging, then accept the prompt on the phone.") {
            CheckRow(ok: !store.onlineAndroid.isEmpty,
                     label: store.onlineAndroid.isEmpty ? "Waiting for a device…" : "\(store.onlineAndroid.count) device(s) online",
                     detail: store.androidDevices.map(\.name).joined(separator: ", "))
            InfoText("If a device shows as “unauthorized”, unlock it and tap “Allow USB debugging”.")
        }
    }

    private var iosStep: some View {
        StepScaffold(title: "iOS Device",
                     subtitle: "Enable Settings → Safari → Advanced → Web Inspector. App webviews need isInspectable = true (iOS 16.4+).") {
            CheckRow(ok: !store.onlineIOS.isEmpty,
                     label: store.onlineIOS.isEmpty ? "Waiting for a device…" : "\(store.onlineIOS.count) device(s) via bridge",
                     detail: store.iosDevices.map(\.name).joined(separator: ", "))
        }
    }

    private var safariStep: some View {
        StepScaffold(title: "Safari Automation",
                     subtitle: "To open Web Inspector on the exact target automatically, macOS requires the Accessibility permission. webbridge only uses it to click Safari's Develop menu.") {
            CheckRow(ok: SafariAutomation.isTrusted,
                     label: SafariAutomation.isTrusted ? "Accessibility granted" : "Accessibility not granted",
                     detail: SafariAutomation.isTrusted ? "Safari inspection opens with one click." : "Optional; without it, webbridge shows the exact menu path instead.")
            HStack(spacing: 8) {
                Button("Open Accessibility Settings", systemImage: "gearshape") {
                    SafariAutomation.openAccessibilitySettings()
                }
                .buttonStyle(.borderedProminent)
                Button("Re-check") { refreshToken += 1 }
            }
        }
        .id(refreshToken)
    }

    private var doneStep: some View {
        StepScaffold(title: "You're Set",
                     subtitle: "Pick a device on the left to see its webviews. Click Console on any target for the live inspector.") {
            InfoText("Shortcuts: ⌘1/2 tabs · ⌘↵ open in Chrome DevTools · ⌘⇧R reload · ⌘K clear console · Esc back.")
        }
    }

    private var controls: some View {
        HStack {
            Button("Skip") { finish() }
                .buttonStyle(.borderless)
            Spacer()
            if step > 0 {
                Button("Back") { go(to: step - 1) }
            }
            Button(step == steps.count - 1 ? "Finish" : "Continue") {
                if step == steps.count - 1 { finish() } else { go(to: step + 1) }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private func finish() {
        store.settings.hasCompletedSetup = true
        store.setupVisible = false
        dismiss()
    }
}

private struct StepScaffold<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.title2.weight(.semibold))
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) { content }
                .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CheckRow: View {
    let ok: Bool
    let label: String
    let detail: String

    var body: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: ok ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(ok ? Color.green : Color.secondary)
                    .font(.system(size: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.callout.weight(.medium))
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.mono(11))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(4)
        }
    }
}

private struct InfoText: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.callout).foregroundStyle(.secondary)
    }
}
