import SwiftUI

struct BannerStack: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ZStack(alignment: .top) {
            if !store.banners.isEmpty {
                GlassEffectContainer(spacing: 8) {
                    VStack(spacing: 8) {
                        ForEach(store.banners) { banner in
                            BannerRow(banner: banner)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .frame(maxWidth: 560)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.3), value: store.banners.map(\.id))
    }
}

private struct BannerRow: View {
    @Environment(AppStore.self) private var store
    let banner: Banner

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .font(.system(size: 14))
            VStack(alignment: .leading, spacing: 1) {
                Text(banner.title)
                    .font(.callout.weight(.semibold))
                Text(banner.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 8)
            if let actionTitle = banner.actionTitle, let action = banner.action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            Button {
                store.dismissBanner(banner.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    private var tint: Color {
        switch banner.kind {
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }

    private var symbol: String {
        switch banner.kind {
        case .error: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }
}
