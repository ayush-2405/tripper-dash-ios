import Foundation

public enum DashSessionState {
    case idle
    case authenticating
    case authenticated
    case rejected
    case failed(String)
}

/// Small authentication coordinator. Higher-level projection, heartbeat and navigation
/// traffic will be added after the handshake has been verified on physical hardware.
public final class DashSession {
    private let ssid: String
    private let transport: DashUDPTransport
    private let auth: DashAuth
    private let callbackQueue = DispatchQueue(label: "tripperdash.session.state")
    private var started = false

    public var onStateChange: ((DashSessionState) -> Void)?

    public init(ssid: String, transport: DashUDPTransport) {
        self.ssid = ssid
        self.transport = transport
        self.auth = DashAuth(ssid: ssid)
    }

    public func start() {
        callbackQueue.async {
            guard !self.started else { return }
            self.started = true
            self.onStateChange?(.authenticating)
            self.transport.receive { [weak self] packet in
                self?.handleIncoming(packet)
            }
            do {
                try self.transport.sendControl(K1GPacket.authRequest())
            } catch {
                self.onStateChange?(.failed(String(describing: error)))
            }
        }
    }

    public func stop() {
        callbackQueue.async {
            self.started = false
            self.transport.close()
            self.onStateChange?(.idle)
        }
    }

    private func handleIncoming(_ packet: Data) {
        callbackQueue.async {
            guard self.started else { return }
            for tlv in K1GPacket.parseIncoming(packet) {
                do {
                    switch try self.auth.ingest(tlv) {
                    case .sendKey(let keyPacket):
                        try self.transport.sendControl(keyPacket)
                    case .confirmed:
                        self.onStateChange?(.authenticated)
                    case .rejected:
                        self.onStateChange?(.rejected)
                        self.auth.reset()
                        try self.transport.sendControl(K1GPacket.authRequest())
                    case .none:
                        break
                    }
                } catch {
                    self.onStateChange?(.failed(String(describing: error)))
                }
            }
        }
    }
}
