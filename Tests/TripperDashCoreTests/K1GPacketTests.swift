import XCTest
@testable import TripperDashCore

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

    func testSequencePatchChangesK1GSequenceByte() {
        let packet = K1GPacket.build([DashTLV(type: 0x07, sub: 0x01, value: Data([1]))])
        let patched = K1GPacket.patchSequence(packet, sequence: 0xA5)
        XCTAssertEqual(patched[16], 0xA5)
        XCTAssertEqual(Int(patched[0]) << 8 | Int(patched[1]), patched.count)
    }
}
