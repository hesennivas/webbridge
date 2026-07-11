import Foundation

/// pure parsing for the relay's HTTP upgrade request, split from socket I/O so the token
/// check is unit-testable.
enum RelayHandshake {

    /// request-target from the HTTP request line, e.g. "GET /page HTTP/1.1" -> "/page".
    static func requestPath(from header: String) -> String {
        let requestLine = header.components(separatedBy: "\r\n").first ?? ""
        return requestLine.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
    }

    /// "Sec-WebSocket-Key" header value, matched case-insensitively.
    static func webSocketKey(from header: String) -> String? {
        for line in header.components(separatedBy: "\r\n").dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].lowercased().trimmingCharacters(in: .whitespaces)
            if name == "sec-websocket-key" {
                return line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// splits "/devtools/page/3?t=abc" into ("/devtools/page/3", "abc"); the token is stripped
    /// before the path is forwarded to the device.
    static func splitToken(_ requestPath: String) -> (path: String, token: String?) {
        guard let marker = requestPath.range(of: "?t=") else { return (requestPath, nil) }
        let path = String(requestPath[requestPath.startIndex..<marker.lowerBound])
        let token = requestPath[marker.upperBound...].prefix { $0 != "&" }
        return (path, String(token))
    }
}
