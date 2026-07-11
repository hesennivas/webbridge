import XCTest
@testable import WebBridge

@MainActor
final class ConsoleFeedTests: XCTestCase {

    private func makeTarget() -> Target {
        Target(id: "d#1", cdpId: "1", deviceID: "d", title: "Page", url: "https://x.test",
               type: "page", webSocketDebuggerURL: "ws://127.0.0.1:9410/devtools/page/1",
               devtoolsFrontendURL: nil, faviconURL: nil, appPackage: nil, appLabel: nil,
               engine: "Chrome", localPort: 9410, canOpenInSafari: false)
    }

    private func entry(_ id: UInt64, _ level: ConsoleLevel, _ text: String) -> ConsoleEntry {
        ConsoleEntry(id: id, level: level, text: text)
    }

    func testHighlightKeepsAllRowsAndCollectsMatches() {
        var ws = WorkspaceState(target: makeTarget())
        ws.entries = [entry(1, .log, "hello world"), entry(2, .error, "boom"), entry(3, .log, "hello again")]
        ws.searchText = "hello"

        let feed = ws.buildFeed(highlight: true)
        XCTAssertEqual(feed.rows.count, 3)
        XCTAssertEqual(feed.matchCount, 2)
        XCTAssertTrue(feed.isMatched(1))
        XCTAssertFalse(feed.isMatched(2))
        XCTAssertEqual(feed.currentMatchID, 1)
        XCTAssertEqual(feed.currentMatchNumber, 1)
    }

    func testFilterModeNarrowsRows() {
        var ws = WorkspaceState(target: makeTarget())
        ws.entries = [entry(1, .log, "hello"), entry(2, .error, "boom")]
        ws.searchText = "hello"

        let feed = ws.buildFeed(highlight: false)
        XCTAssertEqual(feed.rows.map(\.id), [1])
        XCTAssertEqual(feed.matchCount, 1)
    }

    func testCurrentMatchIndexClampsAndSelects() {
        var ws = WorkspaceState(target: makeTarget())
        ws.entries = [entry(1, .log, "x"), entry(2, .log, "x"), entry(3, .log, "x")]
        ws.searchText = "x"
        ws.currentMatchIndex = 99

        let feed = ws.buildFeed(highlight: true)
        XCTAssertEqual(feed.currentMatchID, 3)
        XCTAssertEqual(feed.currentMatchNumber, 3)
    }

    func testCategoryFilterRestrictsRows() {
        var ws = WorkspaceState(target: makeTarget())
        ws.entries = [entry(1, .log, "plain line"),
                      entry(2, .log, #"{"a":1}"#),
                      entry(3, .log, "GET https://api.test/x")]
        ws.categoryFilter = [.json]

        let feed = ws.buildFeed(highlight: false)
        XCTAssertEqual(feed.rows.map(\.id), [2])
        XCTAssertTrue(feed.availableCategories.contains(.json))
        XCTAssertTrue(feed.availableCategories.contains(.api))
    }

    func testRegexSearch() {
        var ws = WorkspaceState(target: makeTarget())
        ws.entries = [entry(1, .log, "error 404"), entry(2, .log, "error 500"), entry(3, .log, "ok")]
        ws.searchText = #"error \d{3}"#
        ws.useRegex = true

        let feed = ws.buildFeed(highlight: false)
        XCTAssertEqual(feed.rows.map(\.id), [1, 2])
    }

    func testSourceFilterAndAvailableSources() {
        var ws = WorkspaceState(target: makeTarget())
        ws.entries = [
            ConsoleEntry(id: 1, level: .log, text: "a", source: "app.js:1"),
            ConsoleEntry(id: 2, level: .log, text: "b", source: "vendor.js:2"),
            ConsoleEntry(id: 3, level: .log, text: "c", source: nil),
        ]
        XCTAssertEqual(ws.buildFeed(highlight: false).availableSources, ["app.js:1", "vendor.js:2"])
        ws.sourceFilter = ["app.js:1"]
        XCTAssertEqual(ws.buildFeed(highlight: false).rows.map(\.id), [1])
    }

    func testInvalidRegexFallsBackToLiteral() {
        var ws = WorkspaceState(target: makeTarget())
        ws.entries = [entry(1, .log, "a[b"), entry(2, .log, "cd")]
        ws.searchText = "a[b"   // invalid regex pattern
        ws.useRegex = true

        let feed = ws.buildFeed(highlight: false)
        XCTAssertEqual(feed.rows.map(\.id), [1])
    }
}
