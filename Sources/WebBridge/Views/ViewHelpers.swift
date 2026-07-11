import SwiftUI
import AppKit

enum Clipboard {
    static func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

extension Font {
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension ConsoleLevel {
    var tint: Color {
        switch self {
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        case .log: return .primary
        case .debug: return .secondary
        }
    }
}

/// Small status indicator matching the system's online/offline dot idiom.
struct StatusDot: View {
    let online: Bool
    var body: some View {
        Circle()
            .fill(online ? Color.green : Color(nsColor: .tertiaryLabelColor))
            .frame(width: 8, height: 8)
    }
}
