import Foundation
#if canImport(Darwin)
import Darwin

public enum DashTransportError: Error {
    case socketCreation(String)
    case bind(String)
    case interfaceBind(String)
    case send(String)
}

/// Minimal BSD UDP transport for the dash control and RTP planes.
/// Create this only after iOS has joined the dashboard's Wi-Fi network.
public final class DashUDPTransport {
    public static let dashAddress = "192.168.1.1"
    public static let broadcastAddress = "192.168.1.255"
    public static let controlPort: UInt16 = 2000
    public static let receivePort: UInt16 = 2002
    public static let rtpPort: UInt16 = 5000

    private var txFD: Int32 = -1
    private var rxFD: Int32 = -1
    private var rtpFD: Int32 = -1
    private var sequence: UInt8 = 0
    private let queue = DispatchQueue(label: "tripperdash.udp.receive")

    public init() throws {
        txFD = try Self.makeSocket()
        rxFD = try Self.makeSocket()
        rtpFD = try Self.makeSocket()
        do {
            var yes: Int32 = 1
            _ = setsockopt(txFD, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))
            try Self.bindSocket(txFD, port: Self.controlPort)
            try Self.bindSocket(rxFD, port: Self.receivePort)
        } catch {
            closeSockets()
            throw error
        }
    }

    deinit { closeSockets() }

    public func sendControl(_ packet: Data) throws {
        let sequenced = K1GPacket.patchSequence(packet, sequence: sequence)
        sequence &+= 1
        try send(sequenced, fd: txFD, host: Self.broadcastAddress, port: Self.controlPort)
    }

    public func sendRTP(_ packet: Data) throws {
        try send(packet, fd: rtpFD, host: Self.dashAddress, port: Self.rtpPort)
    }

    /// Receive on UDP/2002 until cancelled; packets are delivered on the supplied queue.
    public func receive(on callbackQueue: DispatchQueue = .main, handler: @escaping (Data) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            var buffer = [UInt8](repeating: 0, count: 65_535)
            while self.rxFD >= 0 {
                let count = buffer.withUnsafeMutableBytes { rawBuffer in
                    recv(self.rxFD, rawBuffer.baseAddress, rawBuffer.count, 0)
                }
                if count > 0 {
                    let packet = Data(buffer[0..<count])
                    callbackQueue.async { handler(packet) }
                } else if count < 0 && errno != EINTR {
                    break
                }
            }
        }
    }

    public func close() { closeSockets() }

    private func send(_ data: Data, fd: Int32, host: String, port: UInt16) throws {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        guard host.withCString({ inet_pton(AF_INET, $0, &address.sin_addr) }) == 1 else {
            throw DashTransportError.send("Invalid IPv4 address: \(host)")
        }
        let sent = data.withUnsafeBytes { raw in
            withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.sendto(fd, raw.baseAddress, data.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent == data.count else { throw DashTransportError.send(String(cString: strerror(errno))) }
    }

    private static func makeSocket() throws -> Int32 {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw DashTransportError.socketCreation(String(cString: strerror(errno))) }
        #if os(iOS)
        // en0 is the Wi-Fi interface on iOS. Binding each socket keeps dashboard
        // traffic off cellular while leaving the process's default route untouched.
        let interfaceIndex = if_nametoindex("en0")
        guard interfaceIndex != 0 else {
            Darwin.close(fd)
            throw DashTransportError.interfaceBind("Could not resolve the Wi-Fi interface (en0)")
        }
        var index = interfaceIndex
        let result = setsockopt(
            fd,
            IPPROTO_IP,
            IP_BOUND_IF,
            &index,
            socklen_t(MemoryLayout<UInt32>.size)
        )
        guard result == 0 else {
            let message = String(cString: strerror(errno))
            Darwin.close(fd)
            throw DashTransportError.interfaceBind(message)
        }
        #endif
        return fd
    }

    private static func bindSocket(_ fd: Int32, port: UInt16) throws {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: INADDR_ANY.bigEndian)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else { throw DashTransportError.bind(String(cString: strerror(errno))) }
    }

    private func closeSockets() {
        for fd in [txFD, rxFD, rtpFD] where fd >= 0 { Darwin.close(fd) }
        txFD = -1; rxFD = -1; rtpFD = -1
    }
}
#else
/// BSD sockets are implemented for Apple platforms only.
public final class DashUDPTransport {
    public init() {}
}
#endif
