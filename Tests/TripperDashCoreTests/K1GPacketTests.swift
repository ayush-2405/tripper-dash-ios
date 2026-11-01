import XCTest
@testable import TripperDashCore

private extension Data {
    init(hex: String) {
        self.init(stride(from: 0, to: hex.count, by: 2).compactMap { i in
            let a = hex.index(hex.startIndex, offsetBy: i)
            let b = hex.index(a, offsetBy: 2)
            return UInt8(hex[a..<b], radix: 16)
        })
    }
}

final class K1GPacketTests: XCTestCase {

    func testAuthRequestMatchesKnownWirePacket() {
        XCTAssertEqual(
            K1GPacket.authRequest(),
            Data([0x00,0x16,0x00,0x02,0x00,0x00,0x00,0x00,0x02,0x01,0x00,0x05,0x4B,0x31,0x47,0x20,0x00,0x08,0x04,0x00,0x01,0x01])
        )
    }

    func testParseIncomingTLVUsesShortHeader() {
        // Incoming dash packets place TLVs at offset 8, unlike outgoing K1G packets.
        let incoming = Data([0x00,0x0D,0x00,0x01,0,0,0,0,0x07,0x01,0x00,0x01,0x01])
        XCTAssertEqual(
            K1GPacket.parseIncoming(incoming),
            [DashTLV(type: 0x07, sub: 0x01, value: Data([0x01]))]
        )
    }

    func testAuthKeyPacketHasExpectedHeaderAndCiphertextLength() throws {
        let ciphertext = Data(repeating: 0xAB, count: 128)
        let packet = try K1GPacket.authKeyPacket(ciphertext: ciphertext)
        XCTAssertEqual(packet.count, 149)
        let actualHeader = Data(packet.prefix(20))
        let expectedHeader = Data(hex: "0095000200000000020100054B3147200008000080")
        XCTAssertEqual(actualHeader, expectedHeader)
        XCTAssertEqual(packet.suffix(128), ciphertext)
    }

    func testAuthKeyPacketRejectsWrongCiphertextLength() {
        XCTAssertThrowsError(try K1GPacket.authKeyPacket(ciphertext: Data(repeating: 0, count: 127)))
    }

    func testInitialBurstHasExpectedNinePackets() {
        let burst = DashCommands.initialBurst(hostname: "WayFindR")
        XCTAssertEqual(burst.count, 9)
        XCTAssertEqual(burst[0], K1GPacket.authRequest())
        XCTAssertEqual(Int(burst[1][0]) << 8 | Int(burst[1][1]), burst[1].count)
        XCTAssertEqual(burst[2].count, 24)
    }

    func testSequencePatchChangesK1GSequenceByte() {
        let packet = K1GPacket.build([DashTLV(type: 0x07, sub: 0x01, value: Data([1]))])
        let patched = K1GPacket.patchSequence(packet, sequence: 0xA5)
        XCTAssertEqual(patched[16], 0xA5)
        XCTAssertEqual(Int(patched[0]) << 8 | Int(patched[1]), patched.count)
    }
}
