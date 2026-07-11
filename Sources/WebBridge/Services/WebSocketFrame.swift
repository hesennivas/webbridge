import Foundation
import CryptoKit

/// Minimal RFC 6455 framing used by the DevTools relay. Pure and unit-testable.
enum WebSocketFrame {
    static let handshakeMagic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

    /// Computes the `Sec-WebSocket-Accept` response value for a client key.
    static func acceptKey(_ key: String) -> String {
        Data(Insecure.SHA1.hash(data: Data((key + handshakeMagic).utf8))).base64EncodedString()
    }

    /// Encodes a server→client (unmasked) frame.
    static func encode(opcode: UInt8, payload: Data) -> Data {
        var frame = Data([0x80 | opcode])
        let length = payload.count
        if length < 126 {
            frame.append(UInt8(length))
        } else if length <= 0xFFFF {
            frame.append(126)
            frame.append(UInt8((length >> 8) & 0xFF))
            frame.append(UInt8(length & 0xFF))
        } else {
            frame.append(127)
            for shift in stride(from: 56, through: 0, by: -8) {
                frame.append(UInt8((length >> shift) & 0xFF))
            }
        }
        frame.append(payload)
        return frame
    }

    /// Decodes one frame from the front of `buffer`, consuming its bytes. Returns nil when the
    /// buffer doesn't yet hold a complete frame. Handles client masking and 16/64-bit lengths.
    static func decode(_ buffer: inout Data) -> (fin: Bool, opcode: UInt8, payload: Data)? {
        let start = buffer.startIndex
        let count = buffer.count
        guard count >= 2 else { return nil }

        let byte0 = buffer[start]
        let byte1 = buffer[start + 1]
        let fin = (byte0 & 0x80) != 0
        let opcode = byte0 & 0x0F
        let masked = (byte1 & 0x80) != 0
        var length = Int(byte1 & 0x7F)
        var offset = 2

        if length == 126 {
            guard count >= offset + 2 else { return nil }
            length = Int(buffer[start + offset]) << 8 | Int(buffer[start + offset + 1])
            offset += 2
        } else if length == 127 {
            guard count >= offset + 8 else { return nil }
            var extended = 0
            for index in 0..<8 { extended = (extended << 8) | Int(buffer[start + offset + index]) }
            // reject a top-bit-set length that would wrap negative and trap the range below.
            guard extended >= 0 else { return nil }
            length = extended
            offset += 8
        }

        var maskKey = [UInt8](repeating: 0, count: 4)
        if masked {
            guard count >= offset + 4 else { return nil }
            for index in 0..<4 { maskKey[index] = buffer[start + offset + index] }
            offset += 4
        }

        guard count >= offset + length else { return nil }
        var payload = buffer.subdata(in: (start + offset)..<(start + offset + length))
        if masked {
            for index in 0..<length { payload[index] ^= maskKey[index % 4] }
        }
        buffer.removeSubrange(start..<(start + offset + length))
        return (fin, opcode, payload)
    }
}
