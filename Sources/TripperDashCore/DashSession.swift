import Foundation

public enum DashSessionState: Equatable {
    case idle
    case authenticating
    case authenticated
    case rejected
    case reconnectRequired
    case failed(String)
}

/// Authentication/session coordinator.
/// A stopped or failed session is terminal; create a fresh transport and session to reconnect.
public final class DashSession {
    public struct Configuration {
        public var authenticationTimeout: TimeInterval
        public var maximumAuthenticationRetries: Int
        public var receiveWatchdogInterval: TimeInterval
        public var receiveTimeout: TimeInterval

        public init(
            authenticationTimeout: TimeInterval = 8,
            maximumAuthenticationRetries: Int = 3,
            receiveWatchdogInterval: TimeInterval = 1,
            receiveTimeout: TimeInterval = 6
        ) {
            self.authenticationTimeout = authenticationTimeout
            self.maximumAuthenticationRetries = max(0, maximumAuthenticationRetries)
            self.receiveWatchdogInterval = receiveWatchdogInterval
            self.receiveTimeout = receiveTimeout
        }
    }

    private let transport: DashUDPTransport
    private let auth: DashAuth
    private let configuration: Configuration
    private let callbackQueue = DispatchQueue(label: "tripperdash.session.state")
    private var started = false
    private var authenticated = false
    private var authenticationRetries = 0
    private var lastReceiveAt: DispatchTime?
    private var authTimeoutWork: DispatchWorkItem?
    private var watchdog: DispatchSourceTimer?

    public var onStateChange: ((DashSessionState) -> Void)?

    public init(ssid: String, transport: DashUDPTransport, configuration: Configuration = Configuration()) {
        self.transport = transport
        self.auth = DashAuth(ssid: ssid)
        self.configuration = configuration
    }

    /// Starts one session. After stop/failure, construct a new transport and session before retrying.
    public func start() {
        callbackQueue.async {
            guard !self.started else { return }
            self.started = true
            self.authenticated = false
            self.authenticationRetries = 0
            self.lastReceiveAt = .now()
            self.onStateChange?(.authenticating)

            self.transport.receive { [weak self] packet in
                self?.handleIncoming(packet)
            }
            self.sendInitialBurst()
            self.scheduleAuthenticationTimeout()
            self.startReceiveWatchdog()
        }
    }

    public func stop() {
        callbackQueue.async {
            guard self.started else { return }
            self.started = false
            self.cancelTimers()
            self.transport.close()
            self.onStateChange?(.idle)
        }
    }

    private func sendInitialBurst() {
        do {
            for (index, packet) in DashCommands.initialBurst(hostname: "iPhone").enumerated() {
                callbackQueue.asyncAfter(deadline: .now() + .milliseconds(index * 20)) { [weak self] in
                    guard let self, self.started, !self.authenticated else { return }
                    do {
                        try self.transport.sendControl(packet)
                    } catch {
                        self.fail("Initial handshake send failed: \\(error)")
                    }
                }
            }
        }
    }

    private func scheduleAuthenticationTimeout() {
        authTimeoutWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.started, !self.authenticated else { return }
            guard self.authenticationRetries < self.configuration.maximumAuthenticationRetries else {
                self.fail("Dashboard authentication timed out after \\(self.authenticationRetries + 1) attempts")
                return
            }
            self.authenticationRetries += 1
            self.auth.reset()
            self.onStateChange?(.authenticating)
            self.sendInitialBurst()
            self.scheduleAuthenticationTimeout()
        }
        authTimeoutWork = work
        callbackQueue.asyncAfter(deadline: .now() + configuration.authenticationTimeout, execute: work)
    }

    private func startReceiveWatchdog() {
        let timer = DispatchSource.makeTimerSource(queue: callbackQueue)
        timer.schedule(
            deadline: .now() + configuration.receiveWatchdogInterval,
            repeating: configuration.receiveWatchdogInterval
        )
        timer.setEventHandler { [weak self] in
            guard let self, self.started, self.authenticated, let last = self.lastReceiveAt else { return }
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - last.uptimeNanoseconds) / 1_000_000_000
            if elapsed >= self.configuration.receiveTimeout {
                self.started = false
                self.cancelTimers()
                self.transport.close()
                self.onStateChange?(.reconnectRequired)
            }
        }
        watchdog = timer
        timer.resume()
    }

    private func handleIncoming(_ packet: Data) {
        callbackQueue.async {
            guard self.started else { return }
            self.lastReceiveAt = .now()
            for tlv in K1GPacket.parseIncoming(packet) {
                do {
                    switch try self.auth.ingest(tlv) {
                    case .sendKey(let keyPacket):
                        try self.transport.sendControl(keyPacket)
                        // Restart the response window from the key transmission.
                        self.scheduleAuthenticationTimeout()
                    case .confirmed:
                        guard !self.authenticated else { continue }
                        self.authenticated = true
                        self.authTimeoutWork?.cancel()
                        self.authTimeoutWork = nil
                        self.lastReceiveAt = .now()
                        self.onStateChange?(.authenticated)
                    case .rejected:
                        self.onStateChange?(.rejected)
                        self.auth.reset()
                        self.authenticated = false
                        self.scheduleAuthenticationTimeout()
                        try self.transport.sendControl(K1GPacket.authRequest())
                    case .none:
                        break
                    }
                } catch {
                    self.fail("Authentication processing failed: \\(error)")
                    return
                }
            }
        }
    }

    private func fail(_ message: String) {
        guard started else { return }
        started = false
        cancelTimers()
        transport.close()
        onStateChange?(.failed(message))
    }

    private func cancelTimers() {
        authTimeoutWork?.cancel()
        authTimeoutWork = nil
        watchdog?.setEventHandler {}
        watchdog?.cancel()
        watchdog = nil
    }
}
