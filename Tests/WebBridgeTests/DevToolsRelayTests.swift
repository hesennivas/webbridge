import XCTest
import Network
@testable import WebBridge

final class DevToolsRelayTests: XCTestCase {

    /// The relay must bind a loopback port and complete the WebSocket upgrade even when the
    /// client sends the appspot Origin header (which the device would otherwise reject), as
    /// long as the request carries the relay's own token.
    func testRelayBindsAndUpgrades() async throws {
        let relay = DevToolsRelay(devicePort: 1) // no device listening; handshake still completes
        guard let port = await relay.start() else {
            return XCTFail("relay failed to bind a port")
        }
        XCTAssertGreaterThan(port, 0)
        defer { relay.stop() }

        let response = try await performUpgrade(port: port, key: "dGhlIHNhbXBsZSBub25jZQ==",
                                                 path: "/devtools/page/test?t=\(relay.token)")
        XCTAssertTrue(response.contains("101 Switching Protocols"), response)
        XCTAssertTrue(response.contains("Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo="), response)
    }

    /// A request with no token, or the wrong one, must not be able to attach to the relay.
    func testRelayRejectsMismatchedToken() async throws {
        let relay = DevToolsRelay(devicePort: 1)
        guard let port = await relay.start() else {
            return XCTFail("relay failed to bind a port")
        }
        defer { relay.stop() }

        let response = try await performUpgrade(port: port, key: "dGhlIHNhbXBsZSBub25jZQ==",
                                                 path: "/devtools/page/test")
        XCTAssertFalse(response.contains("101 Switching Protocols"), response)
    }

    private func performUpgrade(port: Int, key: String, path: String) async throws -> String {
        let connection = NWConnection(host: "127.0.0.1",
                                      port: NWEndpoint.Port(rawValue: UInt16(port))!,
                                      using: .tcp)
        let done = LockedBox(false)

        return try await withCheckedThrowingContinuation { continuation in
            let finish: @Sendable (String?, Error?) -> Void = { text, error in
                let already = done.withLock { flag -> Bool in
                    if flag { return true }
                    flag = true
                    return false
                }
                guard !already else { return }
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: text ?? "") }
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let request = "GET \(path) HTTP/1.1\r\n" +
                        "Host: 127.0.0.1:\(port)\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n" +
                        "Sec-WebSocket-Key: \(key)\r\nSec-WebSocket-Version: 13\r\n" +
                        "Origin: https://chrome-devtools-frontend.appspot.com\r\n\r\n"
                    connection.send(content: Data(request.utf8), completion: .contentProcessed { _ in
                        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, error in
                            finish(data.map { String(decoding: $0, as: UTF8.self) }, error)
                        }
                    })
                case .failed(let error):
                    finish(nil, error)
                default:
                    break
                }
            }
            connection.start(queue: .global())
        }
    }
}
