import XCTest
@testable import WebBridge

@MainActor
final class DebugSessionTests: XCTestCase {

    private func makeTarget() -> Target {
        Target(id: "d#1", cdpId: "1", deviceID: "d", title: "Page", url: "https://x.test",
               type: "page", webSocketDebuggerURL: "ws://127.0.0.1:9410/devtools/page/1",
               devtoolsFrontendURL: nil, faviconURL: nil, appPackage: nil, appLabel: nil,
               engine: "Chrome", localPort: 9410, canOpenInSafari: false)
    }

    /// A session with no socket URL: the connection is nil so no live tasks start, which lets the
    /// buffer/feed/filter logic be exercised deterministically without a device.
    private func makeSession(settings: AppSettings = AppSettings()) -> DebugSession {
        DebugSession(
            target: makeTarget(), url: nil, webkit: false, deviceLogAvailable: false,
            seed: [], detectedFramework: nil, ids: Sequence64(), settings: settings,
            deviceLogFactory: { .unavailable }, onFrameworkDetected: { _ in })
    }

    private func entry(_ id: UInt64, _ level: ConsoleLevel, _ text: String) -> ConsoleEntry {
        ConsoleEntry(id: id, level: level, text: text)
    }

    func testAppendConsoleMergesConsecutiveDuplicates() {
        let session = makeSession()
        session.appendConsole(entry(1, .log, "tick"))
        session.appendConsole(entry(2, .log, "tick"))   // identical content collapses
        XCTAssertEqual(session.consoleScrollback.count, 1)
        XCTAssertEqual(session.consoleScrollback.first?.repeatCount, 2)
    }

    func testClearConsoleEmptiesTheBuffer() {
        let session = makeSession()
        session.appendConsole(entry(1, .log, "x"))
        session.clearConsole()
        XCTAssertTrue(session.consoleScrollback.isEmpty)
    }

    func testConsoleFeedHonorsHighlightSetting() {
        let settings = AppSettings()
        settings.consoleHighlightMatches = true
        let session = makeSession(settings: settings)
        session.workspace.entries = [entry(1, .log, "hello"), entry(2, .error, "boom")]
        session.setConsoleSearch("hello")

        let feed = session.consoleFeed
        XCTAssertEqual(feed.rows.count, 2)   // highlight keeps every row
        XCTAssertEqual(feed.matchCount, 1)
        XCTAssertTrue(feed.isMatched(1))
    }

    func testFindNavigationWrapsAroundMatches() {
        let session = makeSession()   // highlight off by default
        session.workspace.entries = [entry(1, .log, "a"), entry(2, .log, "a"), entry(3, .log, "b")]
        session.setConsoleSearch("a")
        XCTAssertEqual(session.workspace.currentMatchIndex, 0)
        session.consoleFindNext()
        XCTAssertEqual(session.workspace.currentMatchIndex, 1)
        session.consoleFindNext()   // two matches, wraps back to the first
        XCTAssertEqual(session.workspace.currentMatchIndex, 0)
    }

    func testApplyNetworkTracksRequestLifecycle() {
        let session = makeSession()
        session.applyNetwork(.started(NetworkRequestStart(
            id: "r1", method: "GET", url: "https://x.test/a", resourceType: "fetch",
            headers: [:], postData: nil, monotonic: 1, wallTime: Date())))
        session.applyNetwork(.response(NetworkResponseInfo(
            id: "r1", status: 200, statusText: "OK", mimeType: "application/json",
            resourceType: "fetch", headers: [:], monotonic: 2)))
        session.applyNetwork(.finished(id: "r1", encodedDataLength: 128, monotonic: 3))

        let recorded = session.networkByID["r1"]
        XCTAssertEqual(recorded?.status, 200)
        XCTAssertEqual(recorded?.encodedDataLength, 128)
        XCTAssertEqual(recorded?.durationMS, 2000)   // (3 - 1) seconds in ms
    }

    func testClearNetworkResetsCapture() {
        let session = makeSession()
        session.applyNetwork(.started(NetworkRequestStart(
            id: "r1", method: "GET", url: "https://x.test/a", resourceType: nil,
            headers: [:], postData: nil, monotonic: 1, wallTime: Date())))
        session.clearNetwork()
        XCTAssertTrue(session.networkByID.isEmpty)
        XCTAssertTrue(session.networkOrder.isEmpty)
    }
}
