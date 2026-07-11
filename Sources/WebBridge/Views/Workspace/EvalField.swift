import SwiftUI

struct EvalField: View {
    @Environment(AppStore.self) private var store
    @FocusState private var focused: Bool
    @State private var text = ""

    var body: some View {
        HStack(spacing: 8) {
            TextField("Evaluate JavaScript in this target", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.mono(12))
                .focused($focused)
                .onSubmit(run)
            if store.session?.workspace.connectionClosed == true {
                Text("Disconnected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .animation(.default, value: store.session?.workspace.connectionClosed)
    }

    private func run() {
        let expression = text
        text = ""
        store.session?.evaluate(expression)
    }
}
