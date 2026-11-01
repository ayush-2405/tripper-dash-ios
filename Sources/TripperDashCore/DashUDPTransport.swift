import Foundation
#if canImport(Darwin)
import Darwin

public protocol DashTransport: AnyObject {
    func sendControl(_ packet: Data) throws
    func sendRTP(_ packet: Data) throws
    func receive(on callbackQueue: DispatchQueue, handler: @escaping (Data) -> Void)
    func close()
}

public enum DashTransportError: Error {
    case socketCreation(String)
    case bind(String)
    case interfaceBind(String)
    case send(String)
    case closed
}

/// Minimal BSD UDP transport for the dash control and RTP planes.
/// Create this only after iOS has joined the dashboard's Wi-Fi network.
/// Closing a transport is terminal; create a new instance to reconnect.
public final class DashUDPTransport: DashTransport {
    public static let dashAddress = "192.168.1.1"
    public static let broadcastAddress = "192.168.1.255"
    public static let controlPort: UInt16 = 2000
    public static let receivePort: UInt16 = 2002
    public static let rtpPort: UInt16 = 5000

    private var txFD: Int32 = -1
    private var rxFD: Int32 = -1
    private var rtpFD: Int32 = -1
    private var sequence: UInt8 = 0
    private let socketLock = NSLock()
    private let queue = DispatchQueue(label: "tripperdash.udp.receive")
    private var receiveStarted = false
    public var onPacketReceived: ((Int) -> Void)?

    public init() throws {
        var tx: Int32 = -1
        var rx: Int32 = -1
        var rtp: Int32 = -1
        do {
            tx = try Self.makeSocket()
            rx = try Self.makeSocket()
            rtp = try Self.makeSocket()

            var yes: Int32 = 1
            guard setsockopt(tx, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
                throw DashTransportError.bind(String(cString: strerror(errno)))
            }
            try Self.bindSocket(tx, port: Self.controlPort)
            try Self.bindSocket(rx, port: Self.receivePort)

            txFD = tx
            rxFD = rx
            rtpFD = rtp
        } catch {
            for fd in [tx, rx, rtp] where fd >= 0 { Darwin.close(fd) }
            throw error
        }
    }

    deinit { close() }

    public func sendControl(_ packet: Data) throws {
        socketLock.lock()
        defer { socketLock.unlock() }
        guard txFD >= 0 else { throw DashTransportError.closed }
        let sequenced = K1GPacket.patchSequence(packet, sequence: sequence)
        try Self.send(sequenced, fd: txFD, host: Self.broadcastAddress, port: Self.controlPort)
        sequence &+= 1
    }

    public func sendRTP(_ packet: Data) throws {
        socketLock.lock()
        defer { socketLock.unlock() }
        guard rtpFD >= 0 else { throw DashTransportError.closed }
        try Self.send(packet, fd: rtpFD, host: Self.dashAddress, port: Self.rtpPort)
    }

    /// Receive on UDP/2002 until the transport is closed. Only one receive loop is allowed.
    public func receive(on callbackQueue: DispatchQueue = .main, handler: @escaping (Data) -> Void) {
        socketLock.lock()
        guard rxFD >= 0, !receiveStarted else {
            socketLock.unlock()
            return
        }
        receiveStarted = true
        let receiveFD = rxFD
        socketLock.unlock()

        queue.async {
            var buffer = [UInt8](repeating: 0, count: 65_535)
            while true {
                let count = buffer.withUnsafeMutableBytes { rawBuffer in
                    recv(receiveFD, rawBuffer.baseAddress, rawBuffer.count, 0)
                }
                if count > 0 {
                    let packet = Data(buffer[0..<count])
                    self.onPacketReceived?(count)
                    callbackQueue.async { handler(packet) }
                } else if count < 0 && errno == EINTR {
                    continue
                } else {
                    break
                }
            }
        }
    }

    public func close() {
        socketLock.lock()
        defer { socketLock.unlock() }
        // shutdown wakes a blocked recv before the descriptor is closed.
        if rxFD >= 0 { _ = Darwin.shutdown(rxFD, SHUT_RDWR) }
        for fd in [txFD, rxFD, rtpFD] where fd >= 0 { Darwin.close(fd) }
        txFD = -1
        rxFD = -1
        rtpFD = -1
    }

    private static func send(_ data: Data, fd: Int32, host: String, port: UInt16) throws {
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
}
#else
/// BSD sockets are implemented for Apple platforms only.
public final class DashUDPTransport {
    public init() {}
}
#endif
