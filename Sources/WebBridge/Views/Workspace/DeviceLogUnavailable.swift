import SwiftUI

/// Shown in the device-log pane when the stream can't start (missing tool or untrusted
/// device), with a path back to the Setup Assistant.
struct DeviceLogUnavailable: View {
    @Environment(AppStore.self) private var store
    let state: DeviceLogState

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(message)
        } actions: {
            Button("Open Setup Assistant") { store.setupVisible = true }
                .buttonStyle(.borderedProminent)
            Button("Retry") { store.session?.retryDeviceLog() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var title: String {
        switch state {
        case .missingTool: return "Device Logs Need idevicesyslog"
        default: return "Can't Read Device Logs"
        }
    }

    private var icon: String {
        switch state {
        case .missingTool: return "wrench.and.screwdriver"
        default: return "exclamationmark.triangle"
        }
    }

    private var message: String {
        switch state {
        case .missingTool:
            return "Install libimobiledevice to stream native iOS logs:\n\nbrew install libimobiledevice\n\nThen re-detect tools in the Setup Assistant."
        case .failed(let text):
            return text
        case .ready:
            return ""
        }
    }
}
