import Foundation

/// one request/response row in the network panel, merged from the CDP `Network.*` events.
struct NetworkEntry: Identifiable, Sendable, Equatable {
    let id: String            // cdp requestId
    var method: String
    var url: String
    var resourceType: String?
    var status: Int?
    var statusText: String = ""
    var mimeType: String?
    var requestHeaders: [String: String] = [:]
    var responseHeaders: [String: String] = [:]
    var postData: String?
    var encodedDataLength: Int?
    var startedMonotonic: Double
    var startedAt: Date
    var durationMS: Double?
    var failed = false
    var errorText: String?

    var isPending: Bool { status == nil && !failed }

    /// 2/3/4/5 for a real response, 0 while pending or failed.
    var statusClass: Int { (status ?? 0) / 100 }

    var host: String { URL(string: url)?.host ?? url }

    var path: String {
        guard let parsed = URL(string: url) else { return url }
        let base = parsed.path.isEmpty ? "/" : parsed.path
        return parsed.query.map { "\(base)?\($0)" } ?? base
    }

    /// exact curl for the recorded request: real method, headers and body.
    var curlCommand: String {
        var parts = ["curl"]
        if method != "GET" { parts += ["-X", method] }
        parts.append("'\(url)'")
        for (key, value) in requestHeaders.sorted(by: { $0.key < $1.key }) {
            parts += ["-H", "'\(key): \(value)'"]
        }
        if let postData { parts += ["--data-raw", "'\(postData)'"] }
        return parts.joined(separator: " ")
    }
}

/// incremental signals emitted by `CDPConnection` as a request progresses.
enum NetworkSignal: Sendable {
    case started(NetworkRequestStart)
    case response(NetworkResponseInfo)
    case finished(id: String, encodedDataLength: Int?, monotonic: Double)
    case failed(id: String, error: String, monotonic: Double)
}

struct NetworkRequestStart: Sendable {
    let id: String
    let method: String
    let url: String
    let resourceType: String?
    let headers: [String: String]
    let postData: String?
    let monotonic: Double
    let wallTime: Date
}

struct NetworkResponseInfo: Sendable {
    let id: String
    let status: Int
    let statusText: String
    let mimeType: String
    let resourceType: String?
    let headers: [String: String]
    let monotonic: Double
}
