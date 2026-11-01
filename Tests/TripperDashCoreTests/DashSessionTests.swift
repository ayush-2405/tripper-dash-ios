import XCTest
@testable import TripperDashCore

private final class MockDashTransport: DashTransport {
    private let lock = NSLock()
    private var storedHandler: ((Data) -> Void)?
    private(set) var sentControlPackets: [Data] = []
    private(set) var didClose = false

    func sendControl(_ packet: Data) throws {
        lock.lock()
        sentControlPackets.append(packet)
        lock.unlock()
    }

    func sendRTP(_ packet: Data) throws {}

    func receive(on callbackQueue: DispatchQueue, handler: @escaping (Data) -> Void) {
        lock.lock()
        storedHandler = { packet in callbackQueue.async { handler(packet) } }
        lock.unlock()
    }

    func close() {
        lock.lock()
        didClose = true
        lock.unlock()
    }
}

final class DashSessionTests: XCTestCase {
    func testAuthenticationTimeoutFailsAndClosesTransport() {
        let transport = MockDashTransport()
        let session = DashSession(
            ssid: "RE_TGNO_260915",
            transport: transport,
            configuration: .init(
                authenticationTimeout: 0.05,
                maximumAuthenticationRetries: 0,
                receiveWatchdogInterval: 0.02,
                receiveTimeout: 0.1
            )
        )
        let failed = expectation(description: "session reports authentication timeout")
        session.onStateChange = { state in
            if case .failed(let message) = state {
                XCTAssertTrue(message.contains("authentication timed out"))
                failed.fulfill()
            }
        }

        session.start()
        wait(for: [failed], timeout: 2)
        XCTAssertTrue(transport.didClose)
    }
}
