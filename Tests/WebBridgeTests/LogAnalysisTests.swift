import XCTest
@testable import WebBridge

final class LogAnalysisTests: XCTestCase {

    func testDetectsJSONAndPrettyPrints() {
        let text = #"response {"b":2,"a":1}"#
        XCTAssertTrue(LogAnalysis.categories(for: text).contains(.json))
        let pretty = LogAnalysis.prettyJSON(from: text)
        XCTAssertNotNil(pretty)
        XCTAssertTrue(pretty?.contains("\n") ?? false, "pretty JSON should span multiple lines")
    }

    func testIgnoresNonJSONBraces() {
        let text = "Object { not json here }"
        XCTAssertNil(LogAnalysis.prettyJSON(from: text))
        XCTAssertFalse(LogAnalysis.categories(for: text).contains(.json))
    }

    func testExtractsURLWithoutTrailingPunctuation() {
        let url = LogAnalysis.firstURL(in: "GET https://api.example.com/users?id=5.")
        XCTAssertEqual(url, "https://api.example.com/users?id=5")
    }

    func testDetectsEmail() {
        XCTAssertTrue(LogAnalysis.categories(for: "user a@b.co logged in").contains(.email))
        XCTAssertFalse(LogAnalysis.categories(for: "no address here").contains(.email))
    }

    func testCurlWithMethodAndBody() {
        let text = #"POST https://api.example.com/login {"user":"x"}"#
        let curl = LogAnalysis.curl(for: text)
        XCTAssertNotNil(curl)
        XCTAssertTrue(curl?.contains("-X POST") ?? false)
        XCTAssertTrue(curl?.contains("https://api.example.com/login") ?? false)
        XCTAssertTrue(curl?.contains("-d '") ?? false)
    }

    func testCurlNilWithoutURL() {
        XCTAssertNil(LogAnalysis.curl(for: "just a log line"))
    }
}
