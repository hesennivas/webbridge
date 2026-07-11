import XCTest
@testable import WebBridge

final class WebSocketFrameTests: XCTestCase {

    // RFC 6455 §1.3 worked example.
    func testAcceptKeyMatchesRFCVector() {
        XCTAssertEqual(WebSocketFrame.acceptKey("dGhlIHNhbXBsZSBub25jZQ=="),
                       "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
    }

    func testEncodeSmallLengthHeader() {
        let frame = WebSocketFrame.encode(opcode: 0x1, payload: Data("hi".utf8))
        XCTAssertEqual([UInt8](frame), [0x81, 0x02, 0x68, 0x69])
    }

    func testEncodeMediumLengthUses16BitHeader() {
        let payload = Data(repeating: 0x41, count: 200)
        let frame = WebSocketFrame.encode(opcode: 0x2, payload: payload)
        let header = [UInt8](frame.prefix(4))
        XCTAssertEqual(header, [0x82, 126, 0x00, 0xC8]) // 200 = 0x00C8
        XCTAssertEqual(frame.count, 4 + 200)
    }

    func testEncodeLargeLengthUses64BitHeader() {
        let payload = Data(repeating: 0x41, count: 70_000)
        let frame = WebSocketFrame.encode(opcode: 0x2, payload: payload)
        XCTAssertEqual(frame[frame.startIndex], 0x82)
        XCTAssertEqual(frame[frame.startIndex + 1], 127)
        XCTAssertEqual(frame.count, 10 + 70_000)
    }

    func testDecodeMaskedClientFrameRoundTrips() {
        let text = "Runtime.enable"
        var buffer = maskedClientFrame(opcode: 0x1, payload: Data(text.utf8))
        let decoded = WebSocketFrame.decode(&buffer)
        XCTAssertEqual(decoded?.opcode, 0x1)
        XCTAssertTrue(decoded?.fin ?? false)
        XCTAssertEqual(decoded.map { String(decoding: $0.payload, as: UTF8.self) }, text)
        XCTAssertTrue(buffer.isEmpty)
    }

    func testDecodeReturnsNilForPartialFrame() {
        var buffer = maskedClientFrame(opcode: 0x1, payload: Data("hello".utf8))
        buffer.removeLast(3) // truncate payload
        XCTAssertNil(WebSocketFrame.decode(&buffer))
    }

    func testDecodeConsumesMultipleFrames() {
        var buffer = Data()
        buffer.append(maskedClientFrame(opcode: 0x1, payload: Data("a".utf8)))
        buffer.append(maskedClientFrame(opcode: 0x1, payload: Data("bb".utf8)))
        let first = WebSocketFrame.decode(&buffer)
        let second = WebSocketFrame.decode(&buffer)
        XCTAssertEqual(first.map { String(decoding: $0.payload, as: UTF8.self) }, "a")
        XCTAssertEqual(second.map { String(decoding: $0.payload, as: UTF8.self) }, "bb")
        XCTAssertNil(WebSocketFrame.decode(&buffer))
    }

    func testDecodeMediumMaskedFrame() {
        let payload = Data((0..<300).map { UInt8($0 % 256) })
        var buffer = maskedClientFrame(opcode: 0x2, payload: payload)
        let decoded = WebSocketFrame.decode(&buffer)
        XCTAssertEqual(decoded?.payload, payload)
    }

    // a top-bit-set 64-bit length wraps negative if read straight into Int; must be rejected
    // rather than fed into a Range, which traps on a negative upper bound.
    func testDecodeRejectsLengthWithSignBitSet() {
        var buffer = Data([0x82, 0xFF])
        buffer.append(contentsOf: [0x80, 0, 0, 0, 0, 0, 0, 0])
        buffer.append(contentsOf: [0x37, 0xFA, 0x21, 0x3D])
        buffer.append(Data("x".utf8))
        XCTAssertNil(WebSocketFrame.decode(&buffer))
    }

    /// Builds a masked client→server frame as a browser would send.
    private func maskedClientFrame(opcode: UInt8, payload: Data) -> Data {
        var frame = Data([0x80 | opcode])
        let length = payload.count
        if length < 126 {
            frame.append(0x80 | UInt8(length))
        } else if length <= 0xFFFF {
            frame.append(0x80 | 126)
            frame.append(UInt8((length >> 8) & 0xFF))
            frame.append(UInt8(length & 0xFF))
        } else {
            frame.append(0x80 | 127)
            for shift in stride(from: 56, through: 0, by: -8) {
                frame.append(UInt8((length >> shift) & 0xFF))
            }
        }
        let mask: [UInt8] = [0x37, 0xFA, 0x21, 0x3D]
        frame.append(contentsOf: mask)
        var masked = [UInt8](payload)
        for index in 0..<masked.count { masked[index] ^= mask[index % 4] }
        frame.append(contentsOf: masked)
        return frame
    }
}
