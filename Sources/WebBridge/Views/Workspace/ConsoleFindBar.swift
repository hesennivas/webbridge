import SwiftUI

/// find bar shown while a console search is active: match count, an editable "current of
/// total", prev/next navigation, and the regex toggle.
struct ConsoleFindBar: View {
    @Environment(AppStore.self) private var store
    let feed: ConsoleFeed

    @State private var indexText = ""
    @FocusState private var indexFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.magnifyingglass")
                .foregroundStyle(.secondary)

            if feed.matchCount == 0 {
                Text("No matches")
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 4) {
                    TextField("", text: $indexText)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 34)
                        .focused($indexFocused)
                        .onSubmit(submitIndex)
                    Text("of \(feed.matchCount)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                HStack(spacing: 2) {
                    Button {
                        store.session?.consoleFindPrev()
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .help("Previous Match (⌘⇧G)")

                    Button {
                        store.session?.consoleFindNext()
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .help("Next Match (⌘G)")
                }
                .buttonStyle(.borderless)
            }

            Spacer()

            Toggle(isOn: regexBinding) {
                Text(".*")
                    .font(.mono(11, weight: .semibold))
            }
            .toggleStyle(.button)
            .help("Treat the search as a regular expression")
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .onChange(of: feed.currentMatchNumber, initial: true) { _, number in
            if !indexFocused { indexText = number == 0 ? "" : "\(number)" }
        }
    }

    private func submitIndex() {
        if let value = Int(indexText.trimmingCharacters(in: .whitespaces)) {
            store.session?.consoleGotoMatch(value)
        }
        indexText = feed.currentMatchNumber == 0 ? "" : "\(feed.currentMatchNumber)"
        indexFocused = false
    }

    private var regexBinding: Binding<Bool> {
        Binding(
            get: { store.session?.workspace.useRegex ?? false },
            set: { store.session?.setConsoleRegex($0) })
    }
}
