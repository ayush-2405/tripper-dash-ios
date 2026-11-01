import Foundation
#if canImport(NetworkExtension)
import NetworkExtension

public enum DashWiFiError: Error {
    case unsupportedPlatform
    case missingPassphrase
    case joinFailed(String)
}

/// Requests a user-authorized association with a known dashboard SSID.
/// iOS does not expose general-purpose Wi-Fi scanning to third-party apps,
/// so callers must obtain the exact SSID from the user or a trusted setup flow.
public final class DashWiFiConnector {
    public init() {}

    public func connect(
        ssid: String,
        passphrase: String? = nil,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard !ssid.isEmpty else {
            completion(.failure(DashWiFiError.joinFailed("SSID must not be empty")))
            return
        }

        let configuration: NEHotspotConfiguration
        if let passphrase, !passphrase.isEmpty {
            configuration = NEHotspotConfiguration(ssid: ssid, passphrase: passphrase, isWEP: false)
        } else {
            configuration = NEHotspotConfiguration(ssid: ssid)
        }
        configuration.joinOnce = false

        NEHotspotConfigurationManager.shared.apply(configuration) { error in
            if let nsError = error as NSError? {
                if nsError.domain == NEHotspotConfigurationErrorDomain,
                   nsError.code == NEHotspotConfigurationError.alreadyAssociated.rawValue {
                    completion(.success(()))
                } else {
                    completion(.failure(DashWiFiError.joinFailed(nsError.localizedDescription)))
                }
            } else {
                completion(.success(()))
            }
        }
    }

    public func disconnect(ssid: String) {
        NEHotspotConfigurationManager.shared.removeConfiguration(forSSID: ssid)
    }
}
#else
public final class DashWiFiConnector {
    public init() {}
}
#endif
