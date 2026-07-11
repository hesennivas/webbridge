import XCTest
@testable import WebBridge

final class RelayHandshakeTests: XCTestCase {

    func testRequestPathExtractsTarget() {
        let header = "GET /devtools/page/3?t=abc HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
        XCTAssertEqual(RelayHandshake.requestPath(from: header), "/devtools/page/3?t=abc")
    }

    func testRequestPathDefaultsToRootOnMalformedLine() {
        XCTAssertEqual(RelayHandshake.requestPath(from: ""), "/")
    }

    func testWebSocketKeyIsCaseInsensitive() {
        let header = "GET / HTTP/1.1\r\nSEC-WEBSOCKET-KEY: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n"
        XCTAssertEqual(RelayHandshake.webSocketKey(from: header), "dGhlIHNhbXBsZSBub25jZQ==")
    }

    func testWebSocketKeyMissingReturnsNil() {
        XCTAssertNil(RelayHandshake.webSocketKey(from: "GET / HTTP/1.1\r\n\r\n"))
    }

    func testSplitTokenSeparatesPathFromToken() {
        let result = RelayHandshake.splitToken("/devtools/page/3?t=abc123")
        XCTAssertEqual(result.path, "/devtools/page/3")
        XCTAssertEqual(result.token, "abc123")
    }

    func testSplitTokenWithNoTokenReturnsNilToken() {
        let result = RelayHandshake.splitToken("/devtools/page/3")
        XCTAssertEqual(result.path, "/devtools/page/3")
        XCTAssertNil(result.token)
    }

    func testSplitTokenStopsAtTrailingAmpersand() {
        let result = RelayHandshake.splitToken("/devtools/page/3?t=abc123&extra=1")
        XCTAssertEqual(result.path, "/devtools/page/3")
        XCTAssertEqual(result.token, "abc123")
    }
}
