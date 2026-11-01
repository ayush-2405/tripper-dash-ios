import Foundation

public struct DashTLV: Equatable, Sendable {
    public let type: UInt8
    public let sub: UInt8
    public let value: Data

    public init(type: UInt8, sub: UInt8, value: Data = Data()) {
        self.type = type
        self.sub = sub
        self.value = value
    }
}

public enum K1GPacket {
    private static let fixedHeader: [UInt8] = [
        0, 0, 0, 0, 0x02, 0x01, 0x00, 0x05,
        0x4B, 0x31, 0x47, 0x20
    ]
    private static let magic: [UInt8] = [0x4B, 0x31, 0x47, 0x20]

    /// Builds an app-to-dash packet. The rolling sequence byte is patched on send.
    public static func build(_ tlvs: [DashTLV]) -> Data {
        var bytes: [UInt8] = [0, 0, UInt8((1 + tlvs.count) >> 8), UInt8((1 + tlvs.count) & 0xff)]
        bytes += fixedHeader
        bytes.append(0)
        for tlv in tlvs {
            bytes += [tlv.type, tlv.sub, UInt8((tlv.value.count >> 8) & 0xff), UInt8(tlv.value.count & 0xff)]
            bytes += tlv.value
        }
        bytes[0] = UInt8((bytes.count >> 8) & 0xff)
        bytes[1] = UInt8(bytes.count & 0xff)
        return Data(bytes)
    }

    public static func patchSequence(_ packet: Data, sequence: UInt8) -> Data {
        var bytes = Array(packet)
        if let magicIndex = bytes.windows(ofCount: 4).firstIndex(where: { Array($0) == magic }),
           magicIndex + 4 < bytes.count {
            bytes[magicIndex + 4] = sequence
        }
        if bytes.count >= 2 {
            bytes[0] = UInt8((bytes.count >> 8) & 0xff)
            bytes[1] = UInt8(bytes.count & 0xff)
        }
        return Data(bytes)
    }

    /// Incoming dash packets have TLVs beginning at byte offset 8.
    public static func parseIncoming(_ data: Data) -> [DashTLV] {
        let bytes = Array(data)
        guard bytes.count >= 8 else { return [] }
        let segmentCount = (Int(bytes[2]) << 8) | Int(bytes[3])
        var offset = 8
        var result: [DashTLV] = []
        for _ in 0..<segmentCount {
            guard offset + 4 <= bytes.count else { break }
            let type = bytes[offset]
            let sub = bytes[offset + 1]
            let length = (Int(bytes[offset + 2]) << 8) | Int(bytes[offset + 3])
            offset += 4
            guard length <= bytes.count - offset else { break }
            result.append(DashTLV(type: type, sub: sub, value: Data(bytes[offset..<(offset + length)])))
            offset += length
        }
        return result
    }

    public static func authRequest() -> Data {
        Data(hex: "0016000200000000020100054b314720000804000101")
    }

    public static func authKeyPacket(ciphertext: Data) throws -> Data {
        guard ciphertext.count == 128 else { throw DashAuthError.invalidCiphertextLength(ciphertext.count) }
        return Data(hex: "0095000200000000020100054B3147200008000080") + ciphertext
    }
}

private extension Data {
    init(hex: String) {
        self.init(stride(from: 0, to: hex.count, by: 2).compactMap { index in
            let start = hex.index(hex.startIndex, offsetBy: index)
            let end = hex.index(start, offsetBy: 2)
            return UInt8(hex[start..<end], radix: 16)
        })
    }
}

private extension Array {
    func windows(ofCount count: Int) -> [[Element]] {
        guard count > 0, count <= self.count else { return [] }
        return (0...(self.count - count)).map { Array(self[$0..<($0 + count)]) }
    }
}
