import XCTest
@testable import WebBridge

@MainActor
final class WorkspaceStateTests: XCTestCase {

    private func makeTarget() -> Target {
        Target(id: "d#1", cdpId: "1", deviceID: "d", title: "Page", url: "https://x.test",
               type: "page", webSocketDebuggerURL: "ws://127.0.0.1:9410/devtools/page/1",
               devtoolsFrontendURL: nil, faviconURL: nil, appPackage: nil, appLabel: nil,
               engine: "Chrome", localPort: 9410, canOpenInSafari: false)
    }

    private func entry(_ id: UInt64, _ level: ConsoleLevel, _ text: String, source: String? = nil) -> ConsoleEntry {
        ConsoleEntry(id: id, level: level, text: text, source: source)
    }

    func testFilterHidesNonMatchingWhileHighlightKeepsAll() {
        var ws = WorkspaceState(target: makeTarget())
        ws.entries = [entry(1, .log, "hello world"), entry(2, .error, "boom"), entry(3, .log, "hello again")]
        ws.searchText = "hello"

        // filter mode: only matches survive
        XCTAssertEqual(ws.buildFeed(highlight: false).rows.map(\.id), [1, 3])
        // highlight mode keeps all rows and marks the matches
        let highlighted = ws.buildFeed(highlight: true)
        XCTAssertEqual(highlighted.rows.count, 3)
        XCTAssertTrue(highlighted.isMatched(1))
        XCTAssertFalse(highlighted.isMatched(2))
    }

    func testSearchMatchesSource() {
        var ws = WorkspaceState(target: makeTarget())
        ws.entries = [entry(1, .log, "no match here", source: "app.js:42")]
        ws.searchText = "app.js"
        XCTAssertEqual(ws.buildFeed(highlight: false).rows.map(\.id), [1])
    }

    func testLevelFilterAppliesBeforeSearch() {
        var ws = WorkspaceState(target: makeTarget())
        ws.entries = [entry(1, .log, "keep"), entry(2, .error, "keep")]
        ws.levelFilter = [.log]
        XCTAssertEqual(ws.buildFeed(highlight: true).rows.map(\.id), [1])
        ws.searchText = "keep"
        XCTAssertEqual(ws.buildFeed(highlight: false).rows.map(\.id), [1])
    }
}
