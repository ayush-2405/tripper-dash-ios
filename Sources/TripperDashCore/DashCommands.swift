import Foundation

public enum DashCommands {
    public static func authRequest() -> Data {
        Data(hex: "0016000200000000020100054b314720000804000101")
    }

    /// Captured K1G startup burst. The dash's RSA key offer is triggered by this
    /// sequence, not reliably by an isolated auth request.
    public static func initialBurst(hostname: String) -> [Data] {
        let name = Data(hostname.utf8.prefix(200))
        var announce = Data(hex: "0021000200000000020100054b314720")
        announce.append(contentsOf: [0x01, 0x06, 0x0B, 0x00, UInt8((name.count + 1) & 0xff)])
        announce.append(name)
        announce.append(0)
        announce[0] = UInt8((announce.count >> 8) & 0xff)
        announce[1] = UInt8(announce.count & 0xff)

        let calendar = Calendar.current.dateComponents([.hour, .minute, .second], from: Date())
        let time = K1GPacket.build([
            DashTLV(type: 0x06, sub: 0x06,
                    value: Data([UInt8(calendar.hour ?? 0), UInt8(calendar.minute ?? 0), UInt8(calendar.second ?? 0)]))
        ])

        return [
            authRequest(),
            announce,
            time,
            Data(hex: "0016000200000000020100054b314720030557000155"),
            Data(hex: "0016000200000000020100054b3147200405560001aa"),
            Data(hex: "0016000200000000020100054b3147200506050001aa"),
            Data(hex: "0016000200000000020100054b3147200605170001aa"),
            Data(hex: "001d000200000000020100054b314720080a020008aa55000000000000"),
            Data(hex: "0044000a00000000020100054b3147200906080001ff060300015506040001a2060f0001aa0601000101054c000113052d00020000051b0001190521000132054d000132")
        ]
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
