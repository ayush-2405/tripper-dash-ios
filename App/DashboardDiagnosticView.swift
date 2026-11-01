import SwiftUI

@MainActor
final class DashboardDiagnosticModel: ObservableObject {
    @Published var connectionStatus = "Not connected"
    @Published var sessionStatus = "Idle"
    @Published var packetsReceived = 0
    @Published var errorMessage: String?
    @Published var isConnecting = false

    let ssid = "RE_TGNO_260915"
    private let wifi = DashWiFiConnector()
    private var transport: DashUDPTransport?
    private var session: DashSession?

    func connect() {
        guard !isConnecting else { return }
        isConnecting = true
        errorMessage = nil
        connectionStatus = "Requesting Wi-Fi connection…"
        sessionStatus = "Waiting for Wi-Fi"

        wifi.connect(ssid: ssid) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .failure(let error):
                    self.isConnecting = false
                    self.connectionStatus = "Wi-Fi join failed"
                    self.errorMessage = error.localizedDescription
                case .success:
                    self.connectionStatus = "Wi-Fi join request accepted"
                    self.startSession()
                }
            }
        }
    }

    private func startSession() {
        do {
            let transport = try DashUDPTransport()
            self.transport = transport
            let session = DashSession(ssid: ssid, transport: transport)
            self.session = session
            session.onStateChange = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    self.sessionStatus = Self.describe(state)
                    switch state {
                    case .authenticated:
                        self.isConnecting = false
                    case .failed, .reconnectRequired, .rejected:
                        self.isConnecting = false
                    default:
                        break
                    }
                }
            }
            session.start()
        } catch {
            isConnecting = false
            connectionStatus = "UDP setup failed"
            errorMessage = error.localizedDescription
        }
    }

    func disconnect() {
        session?.stop()
        session = nil
        transport?.close()
        transport = nil
        isConnecting = false
        connectionStatus = "Disconnected"
        sessionStatus = "Idle"
        packetsReceived = 0
    }

    private static func describe(_ state: DashSessionState) -> String {
        switch state {
        case .idle: return "Idle"
        case .authenticating: return "Authenticating with dashboard…"
        case .authenticated: return "Authenticated"
        case .rejected: return "Dashboard rejected authentication"
        case .reconnectRequired: return "Connection lost — reconnect required"
        case .failed(let message): return message
        }
    }
}

struct DashboardDiagnosticView: View {
    @StateObject private var model = DashboardDiagnosticModel()

    var body: some View {
        NavigationStack {
            List {
                Section("Dashboard") {
                    LabeledContent("Target SSID", value: model.ssid)
                    LabeledContent("Wi-Fi", value: model.connectionStatus)
                    LabeledContent("Session", value: model.sessionStatus)
                    LabeledContent("Packets received", value: "\(model.packetsReceived)")
                }

                Section {
                    Button(model.isConnecting ? "Connecting…" : "Connect to Tripper Dash") {
                        model.connect()
                    }
                    .disabled(model.isConnecting)

                    Button("Disconnect", role: .destructive) {
                        model.disconnect()
                    }
                }

                if let error = model.errorMessage {
                    Section("Diagnostic error") {
                        Text(error).foregroundStyle(.red)
                    }
                }

                Section("Test notes") {
                    Text("Keep the motorcycle powered on with the Tripper Dash Wi-Fi available.")
                    Text("A successful Wi-Fi join request does not by itself prove dashboard communication. Authentication status is the next check.")
                    Text("This diagnostic build does not transmit navigation or video.")
                }
            }
            .navigationTitle("Tripper Dash Test")
        }
    }
}
