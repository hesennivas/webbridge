import SwiftUI

struct NoDeviceView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ContentUnavailableView {
            Label("No Device Connected", systemImage: "cable.connector")
        } description: {
            Text("Connect an Android device with USB debugging enabled and accept the prompt on the phone. For iOS, enable Settings → Safari → Advanced → Web Inspector.")
        } actions: {
            Button("Setup Assistant…") { store.setupVisible = true }
                .buttonStyle(.borderedProminent)
        }
        .navigationTitle("webbridge")
    }
}
