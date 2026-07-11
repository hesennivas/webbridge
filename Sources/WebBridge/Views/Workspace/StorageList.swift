import SwiftUI

struct StorageList: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ZStack {
            if let snapshot = store.session?.workspace.storage {
                if filtered(snapshot).isEmpty {
                    emptyState.transition(.opacity)
                } else {
                    form(filtered(snapshot)).transition(.opacity)
                }
            } else {
                loadingState.transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.session?.workspace.storage)
        .onAppear { store.session?.loadStorage() }
    }

    private func form(_ snapshot: StorageSnapshot) -> some View {
        Form {
            if !snapshot.cookies.isEmpty {
                Section("Cookies (\(snapshot.cookies.count))") {
                    ForEach(snapshot.cookies) { cookie in
                        row(cookie.name, cookie.value, badge: cookie.httpOnly ? "httpOnly" : nil)
                    }
                }
            }
            if !snapshot.local.isEmpty {
                Section("Local Storage (\(snapshot.local.count))") {
                    ForEach(snapshot.local) { item in row(item.key, item.value, badge: nil) }
                }
            }
            if !snapshot.session.isEmpty {
                Section("Session Storage (\(snapshot.session.count))") {
                    ForEach(snapshot.session) { item in row(item.key, item.value, badge: nil) }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func row(_ key: String, _ value: String, badge: String?) -> some View {
        LabeledContent {
            Text(value)
                .font(.mono(11))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .textSelection(.enabled)
        } label: {
            HStack(spacing: 6) {
                Text(key).font(.mono(12))
                if let badge {
                    Text(badge)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Capsule().fill(.quaternary))
                }
            }
        }
        .contextMenu {
            Button("Copy Value") { Clipboard.copy(value) }
            Button("Copy \(key)=value") { Clipboard.copy("\(key)=\(value)") }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.large)
            Text("Reading cookies and storage…").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Stored Data", systemImage: "internaldrive")
        } description: {
            Text(searching ? "No keys match the filter." : "This target has no cookies or web storage.")
        }
    }

    private var searching: Bool { !(store.session?.workspace.storageSearch.isEmpty ?? true) }

    private func filtered(_ snapshot: StorageSnapshot) -> StorageSnapshot {
        let query = store.session?.workspace.storageSearch.trimmingCharacters(in: .whitespaces) ?? ""
        guard !query.isEmpty else { return snapshot }
        var result = snapshot
        result.cookies = snapshot.cookies.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.value.localizedCaseInsensitiveContains(query)
        }
        result.local = snapshot.local.filter {
            $0.key.localizedCaseInsensitiveContains(query) || $0.value.localizedCaseInsensitiveContains(query)
        }
        result.session = snapshot.session.filter {
            $0.key.localizedCaseInsensitiveContains(query) || $0.value.localizedCaseInsensitiveContains(query)
        }
        return result
    }
}
