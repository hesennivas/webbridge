import SwiftUI
import AppKit

struct NetworkList: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let entries = store.session?.workspace.filteredNetwork() ?? []
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if entries.isEmpty {
                    HStack(spacing: 8) {
                        if store.session?.workspace.connectionClosed != true {
                            ProgressView().controlSize(.small)
                        }
                        Text(emptyLabel)
                            .font(.mono(11))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(16)
                }
                ForEach(entries) { entry in
                    NetworkRow(entry: entry).equatable()
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var emptyLabel: String {
        let searching = !(store.session?.workspace.networkSearch.isEmpty ?? true)
        return searching ? "No matching requests" : "Waiting for network activity…"
    }
}

private struct NetworkRow: View, Equatable {
    let entry: NetworkEntry
    @State private var expanded = false

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.entry == rhs.entry }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(statusText)
                    .font(.mono(10, weight: .medium))
                    .foregroundStyle(statusTint)
                    .frame(width: 34, alignment: .leading)

                Text(entry.method)
                    .font(.mono(10))
                    .foregroundStyle(.secondary)
                    .frame(width: 46, alignment: .leading)

                Text(entry.path)
                    .font(.mono(11))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 8)

                if let type = entry.resourceType {
                    Text(type)
                        .font(.mono(9.5))
                        .foregroundStyle(.tertiary)
                }
                Text(sizeText)
                    .font(.mono(9.5))
                    .foregroundStyle(.tertiary)
                    .frame(width: 56, alignment: .trailing)
                Text(timeText)
                    .font(.mono(9.5))
                    .foregroundStyle(.tertiary)
                    .frame(width: 54, alignment: .trailing)
            }

            if expanded { detail }
        }
        .padding(.horizontal, 14).padding(.vertical, 3)
        .background(entry.failed ? Color.red.opacity(0.07) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.snappy(duration: 0.18)) { expanded.toggle() } }
        .contextMenu {
            Button("Copy URL", systemImage: "link") { Clipboard.copy(entry.url) }
            Button("Copy as cURL", systemImage: "terminal") { Clipboard.copy(entry.curlCommand) }
            if !entry.responseHeaders.isEmpty {
                Button("Copy Response Headers", systemImage: "list.bullet") {
                    Clipboard.copy(headerText(entry.responseHeaders))
                }
            }
            Button("Open URL", systemImage: "safari") {
                if let url = URL(string: entry.url) { NSWorkspace.shared.open(url) }
            }
        }
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.url)
                .font(.mono(9.5))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            if let error = entry.errorText {
                Text(error).font(.mono(9.5)).foregroundStyle(.red)
            }
            headerSection("Request", entry.requestHeaders)
            if let body = entry.postData, !body.isEmpty {
                Text("Payload").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Text(body).font(.mono(9.5)).foregroundStyle(.secondary).textSelection(.enabled)
            }
            headerSection("Response", entry.responseHeaders)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 42).padding(.top, 2)
    }

    @ViewBuilder
    private func headerSection(_ title: String, _ headers: [String: String]) -> some View {
        if !headers.isEmpty {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                ForEach(headers.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                    Text("\(key): \(value)")
                        .font(.mono(9.5))
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func headerText(_ headers: [String: String]) -> String {
        headers.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
    }

    private var statusText: String {
        if entry.failed { return "fail" }
        if let status = entry.status { return "\(status)" }
        return "…"
    }

    private var statusTint: Color {
        if entry.failed { return .red }
        switch entry.statusClass {
        case 2: return .green
        case 3: return .blue
        case 4: return .orange
        case 5: return .red
        default: return .secondary
        }
    }

    private var sizeText: String {
        guard let bytes = entry.encodedDataLength, bytes > 0 else { return "—" }
        if bytes < 1024 { return "\(bytes) B" }
        return String(format: "%.1f KB", Double(bytes) / 1024)
    }

    private var timeText: String {
        guard let ms = entry.durationMS else { return "—" }
        if ms < 1000 { return "\(Int(ms)) ms" }
        return String(format: "%.2f s", ms / 1000)
    }
}
