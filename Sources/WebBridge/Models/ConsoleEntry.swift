import Foundation

enum ConsoleLevel: String, Sendable, CaseIterable {
    case error, warning, info, log, debug

    var glyph: String {
        switch self {
        case .error: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        case .log: return "text.alignleft"
        case .debug: return "ant.fill"
        }
    }

    var label: String { rawValue.capitalized }
}

enum ConsoleKind: Sendable {
    case message
    case exception
    case navigation
    case system
}

struct ConsoleEntry: Identifiable, Sendable, Equatable {
    let id: UInt64
    let level: ConsoleLevel
    let kind: ConsoleKind
    let text: String
    let source: String?
    let timestamp: Date
    let timeLabel: String
    /// content classes (JSON/API/email) detected once, so filter and menu logic never re-scans.
    let categories: LogCategory
    var stack: [String]
    var repeatCount: Int

    init(id: UInt64,
         level: ConsoleLevel,
         kind: ConsoleKind = .message,
         text: String,
         source: String? = nil,
         timestamp: Date = Date(),
         stack: [String] = [],
         repeatCount: Int = 1) {
        self.id = id
        self.level = level
        self.kind = kind
        self.text = text
        self.source = source
        self.timestamp = timestamp
        self.timeLabel = Self.timeStyle.format(timestamp)
        self.categories = LogAnalysis.categories(for: text)
        self.stack = stack
        self.repeatCount = repeatCount
    }

    /// Two adjacent entries are collapsible when they carry identical content.
    func isDuplicate(of other: ConsoleEntry) -> Bool {
        level == other.level && kind == other.kind && text == other.text && source == other.source
    }

    /// ids are unique and repeatCount is the only field mutated after creation, so this
    /// comparison is complete without touching text/stack.
    static func == (lhs: ConsoleEntry, rhs: ConsoleEntry) -> Bool {
        lhs.id == rhs.id && lhs.repeatCount == rhs.repeatCount
    }

    // created on both the main actor and the CDP actor; VerbatimFormatStyle is Sendable, unlike DateFormatter.
    private static let timeStyle = Date.VerbatimFormatStyle(
        format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits).\(secondFraction: .fractional(3))",
        timeZone: .current,
        calendar: Calendar(identifier: .gregorian))
}
