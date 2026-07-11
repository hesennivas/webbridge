import Foundation

/// serializes captured network entries into a HAR 1.2 document for sharing or replay.
enum HARExport {

    static func string(from entries: [NetworkEntry], pageURL: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let httpEntries: [[String: Any]] = entries.map { entry in
            var request: [String: Any] = [
                "method": entry.method,
                "url": entry.url,
                "httpVersion": "HTTP/1.1",
                "headers": headers(entry.requestHeaders),
                "queryString": [],
                "cookies": [],
                "headersSize": -1,
                "bodySize": entry.postData?.utf8.count ?? 0,
            ]
            if let body = entry.postData {
                request["postData"] = [
                    "mimeType": entry.requestHeaders["Content-Type"] ?? "text/plain",
                    "text": body,
                ]
            }
            return [
                "startedDateTime": iso.string(from: entry.startedAt),
                "time": entry.durationMS ?? 0.0,
                "request": request,
                "response": [
                    "status": entry.status ?? 0,
                    "statusText": entry.statusText,
                    "httpVersion": "HTTP/1.1",
                    "headers": headers(entry.responseHeaders),
                    "cookies": [],
                    "content": ["size": entry.encodedDataLength ?? 0, "mimeType": entry.mimeType ?? ""],
                    "redirectURL": "",
                    "headersSize": -1,
                    "bodySize": entry.encodedDataLength ?? 0,
                ],
                "cache": [:],
                "timings": ["send": 0.0, "wait": entry.durationMS ?? 0.0, "receive": 0.0],
            ]
        }

        let document: [String: Any] = [
            "log": [
                "version": "1.2",
                "creator": ["name": "webbridge", "version": "1.0"],
                "pages": pageURL.isEmpty ? [] : [[
                    "startedDateTime": iso.string(from: Date()),
                    "id": "page_1",
                    "title": pageURL,
                    "pageTimings": [:],
                ]],
                "entries": httpEntries,
            ]
        ]

        guard let data = try? JSONSerialization.data(
            withJSONObject: document, options: [.prettyPrinted, .withoutEscapingSlashes]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func headers(_ map: [String: String]) -> [[String: String]] {
        map.sorted { $0.key < $1.key }.map { ["name": $0.key, "value": $0.value] }
    }
}
