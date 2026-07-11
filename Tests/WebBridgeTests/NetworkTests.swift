import XCTest
@testable import WebBridge

@MainActor
final class NetworkTests: XCTestCase {

    private func target(webkit: Bool = false) -> Target {
        Target(id: "d#1", cdpId: "1", deviceID: "d", title: "Page", url: "https://x.test",
               type: "page", webSocketDebuggerURL: "ws://127.0.0.1:9410/devtools/page/1",
               devtoolsFrontendURL: nil, faviconURL: nil, appPackage: nil, appLabel: nil,
               engine: "Chrome", localPort: 9410, canOpenInSafari: webkit)
    }

    private func entry(_ id: String, method: String = "GET", url: String, status: Int?) -> NetworkEntry {
        NetworkEntry(id: id, method: method, url: url, status: status,
                     startedMonotonic: 0, startedAt: Date())
    }

    func testStatusClassAndPath() {
        let e = entry("1", url: "https://api.test/v1/users?id=5", status: 404)
        XCTAssertEqual(e.statusClass, 4)
        XCTAssertEqual(e.path, "/v1/users?id=5")
        XCTAssertEqual(e.host, "api.test")
        XCTAssertFalse(e.isPending)
    }

    func testPendingEntry() {
        let e = entry("1", url: "https://api.test/x", status: nil)
        XCTAssertTrue(e.isPending)
        XCTAssertEqual(e.statusClass, 0)
    }

    func testCurlCommandIncludesMethodHeadersBody() {
        var e = entry("1", method: "POST", url: "https://api.test/login", status: 200)
        e.requestHeaders = ["Authorization": "Bearer x"]
        e.postData = #"{"u":"a"}"#
        let curl = e.curlCommand
        XCTAssertTrue(curl.contains("-X POST"))
        XCTAssertTrue(curl.contains("'https://api.test/login'"))
        XCTAssertTrue(curl.contains("-H 'Authorization: Bearer x'"))
        XCTAssertTrue(curl.contains("--data-raw '{\"u\":\"a\"}'"))
    }

    func testStatusAndSearchFilter() {
        var ws = WorkspaceState(target: target())
        ws.networkEntries = [
            entry("1", url: "https://a.test/ok", status: 200),
            entry("2", url: "https://a.test/missing", status: 404),
            entry("3", url: "https://b.test/ok", status: 201),
        ]
        ws.networkStatusFilter = [2]
        XCTAssertEqual(ws.filteredNetwork().map(\.id), ["1", "3"])
        ws.networkStatusFilter = []
        ws.networkSearch = "b.test"
        XCTAssertEqual(ws.filteredNetwork().map(\.id), ["3"])
    }

    func testTypeFilter() {
        var ws = WorkspaceState(target: target())
        var xhr = entry("1", url: "https://a.test/x", status: 200); xhr.resourceType = "XHR"
        var script = entry("2", url: "https://a.test/y", status: 200); script.resourceType = "Script"
        ws.networkEntries = [xhr, script]
        XCTAssertEqual(ws.networkTypes(), ["Script", "XHR"])
        ws.networkTypeFilter = ["XHR"]
        XCTAssertEqual(ws.filteredNetwork().map(\.id), ["1"])
    }

    func testAvailableTabsHideNetworkForWebKit() {
        var ws = WorkspaceState(target: target())
        ws.isWebKit = true
        XCTAssertEqual(ws.availableTabs, [.console, .storage])
        ws.isWebKit = false
        XCTAssertEqual(ws.availableTabs, [.console, .network, .storage])
    }

    func testHARIsValidJSONWithEntries() {
        let e = entry("1", method: "GET", url: "https://api.test/x", status: 200)
        let har = HARExport.string(from: [e], pageURL: "https://x.test")
        let data = Data(har.utf8)
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let log = object?["log"] as? [String: Any]
        let entries = log?["entries"] as? [[String: Any]]
        XCTAssertEqual(entries?.count, 1)
        XCTAssertEqual((entries?.first?["request"] as? [String: Any])?["url"] as? String, "https://api.test/x")
    }
}
