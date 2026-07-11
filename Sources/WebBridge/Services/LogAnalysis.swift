import Foundation

/// content classes a console line can belong to, detected once at creation; drives filter chips
/// and context-menu actions.
struct LogCategory: OptionSet, Hashable, Sendable {
    let rawValue: Int

    static let json = LogCategory(rawValue: 1 << 0)
    static let api = LogCategory(rawValue: 1 << 1)
    static let email = LogCategory(rawValue: 1 << 2)

    var isEmpty: Bool { rawValue == 0 }

    /// chips are offered in this order, shown only when at least one visible entry carries them.
    static let known: [(category: LogCategory, label: String, symbol: String)] = [
        (.json, "JSON", "curlybraces"),
        (.api, "API", "network"),
        (.email, "Email", "envelope"),
    ]
}

/// cheap, allocation-light classification and extraction over raw console text.
enum LogAnalysis {

    // MARK: - Classification

    static func categories(for text: String) -> LogCategory {
        var result: LogCategory = []
        if firstURL(in: text) != nil { result.insert(.api) }
        if hasEmail(text) { result.insert(.email) }
        if prettyJSON(from: text) != nil { result.insert(.json) }
        return result
    }

    // MARK: - JSON

    /// first balanced `{…}`/`[…]` span in the text that parses as JSON, pretty-printed.
    static func prettyJSON(from text: String) -> String? { json(from: text, pretty: true) }

    /// compact single-line JSON, used for a curl `-d` body.
    static func compactJSON(from text: String) -> String? { json(from: text, pretty: false) }

    private static func json(from text: String, pretty: Bool) -> String? {
        guard let range = jsonRange(in: text),
              let data = String(text[range]).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object) else { return nil }
        let options: JSONSerialization.WritingOptions =
            pretty ? [.prettyPrinted, .withoutEscapingSlashes] : [.withoutEscapingSlashes]
        guard let out = try? JSONSerialization.data(withJSONObject: object, options: options) else { return nil }
        return String(decoding: out, as: UTF8.self)
    }

    /// scans for the first `{`/`[` and walks to its matching close, respecting string literals.
    private static func jsonRange(in text: String) -> Range<String.Index>? {
        guard let start = text.firstIndex(where: { $0 == "{" || $0 == "[" }) else { return nil }
        let open = text[start]
        let close: Character = open == "{" ? "}" : "]"
        var depth = 0, inString = false, escaped = false
        var index = start
        while index < text.endIndex {
            let character = text[index]
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                inString.toggle()
            } else if !inString {
                if character == open { depth += 1 }
                else if character == close {
                    depth -= 1
                    if depth == 0 { return start..<text.index(after: index) }
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    // MARK: - URLs & curl

    static func firstURL(in text: String) -> String? {
        guard let match = text.firstMatch(of: urlRegex) else { return nil }
        // trim trailing punctuation the regex may have swept up (e.g. a sentence-ending period)
        return String(match.output).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?"))
    }

    /// best-effort curl for a line with an HTTP URL, folding in a verb and JSON body when present.
    static func curl(for text: String) -> String? {
        guard let url = firstURL(in: text) else { return nil }
        var parts = ["curl"]
        if let method = httpMethod(in: text), method != "GET" { parts += ["-X", method] }
        parts.append("'\(url)'")
        if let body = compactJSON(from: text) {
            parts += ["-H 'Content-Type: application/json'", "-d '\(body)'"]
        }
        return parts.joined(separator: " ")
    }

    private static func httpMethod(in text: String) -> String? {
        text.firstMatch(of: methodRegex)?.1.uppercased()
    }

    static func hasEmail(_ text: String) -> Bool {
        text.firstMatch(of: emailRegex) != nil
    }

    // MARK: - Regexes
    // literals: a bad pattern fails the build instead of trapping at runtime.

    nonisolated(unsafe) private static let urlRegex = #/https?://[^\s'"\)\]}>]+/#.ignoresCase()
    nonisolated(unsafe) private static let emailRegex = #/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/#.ignoresCase()
    nonisolated(unsafe) private static let methodRegex = #/\b(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)\b/#.ignoresCase()
}
