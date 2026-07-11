import XCTest
@testable import WebBridge

final class TargetTests: XCTestCase {

    /// A URL-bearing page pins by its URL so the pin survives the CDP id churning on
    /// every reload/reconnect.
    func testPinIdentityUsesURLWhenPresent() {
        let target = makeTarget(cdpId: "3", title: "Home", url: "https://example.com/home")
        XCTAssertEqual(target.pinIdentity, "https://example.com/home")

        // Same page, fresh CDP id after a reconnect. Identity must stay stable.
        let reconnected = makeTarget(cdpId: "91", title: "Home", url: "https://example.com/home")
        XCTAssertEqual(reconnected.pinIdentity, target.pinIdentity)
    }

    /// Pages without a URL (some app WebViews) fall back to the display title.
    func testPinIdentityFallsBackToTitleWhenURLEmpty() {
        let target = makeTarget(cdpId: "1", title: "Checkout", url: "")
        XCTAssertEqual(target.pinIdentity, "Checkout")
    }

    private func makeTarget(cdpId: String, title: String, url: String) -> Target {
        Target(
            id: "device#\(cdpId)",
            cdpId: cdpId,
            deviceID: "device",
            title: title,
            url: url,
            type: "page",
            webSocketDebuggerURL: "ws://127.0.0.1:9410/devtools/page/\(cdpId)",
            devtoolsFrontendURL: nil,
            faviconURL: nil,
            appPackage: nil,
            appLabel: nil,
            engine: "Chrome",
            localPort: 9410,
            canOpenInSafari: false)
    }
}
