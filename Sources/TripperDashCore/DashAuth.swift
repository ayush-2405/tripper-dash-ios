import Foundation
#if canImport(Security)
import Security
#endif

public enum DashAuthError: Error, Equatable {
    case missingPublicKeyComponent
    case invalidPublicKey
    case encryptionFailed(String)
    case invalidCiphertextLength(Int)
    case securityFrameworkUnavailable
}

public enum DashAuthEvent {
    case sendKey(Data)
    case confirmed
    case rejected
    case none
}

/// RSA-1024 / AES-256 authentication state machine used by the Console Dash.
/// The exact Wi-Fi SSID is part of the encrypted payload and must be known before authenticating.
public final class DashAuth {
    private let ssid: String
    private var modulus: Data?
    private var exponent: Data?
    private var keySent = false

    public private(set) var sessionKey: Data?

    public init(ssid: String) {
        self.ssid = ssid
    }

    public func ingest(_ tlv: DashTLV) throws -> DashAuthEvent {
        guard tlv.type == 0x07 else { return .none }
        switch tlv.sub {
        case 0x00:
            modulus = tlv.value
        case 0x03:
            exponent = tlv.value
        case 0x01:
            return tlv.value.first == 0x01 ? .confirmed : .rejected
        default:
            return .none
        }

        guard !keySent, let modulus, let exponent else { return .none }
        let packet = try makeKeyPacket(modulus: modulus, exponent: exponent)
        keySent = true
        return .sendKey(packet)
    }

    public func reset() {
        modulus = nil
        exponent = nil
        keySent = false
        sessionKey = nil
    }

    private func makeKeyPacket(modulus: Data, exponent: Data) throws -> Data {
        #if canImport(Security)
        guard modulus.count == 128, !exponent.isEmpty else { throw DashAuthError.invalidPublicKey }
        var aesKey = Data(count: 32)
        let randomStatus = aesKey.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!)
        }
        guard randomStatus == errSecSuccess else {
            throw DashAuthError.encryptionFailed("Secure random generation failed: \(randomStatus)")
        }

        let payload = Data(ssid.utf8) + aesKey
        let der = Self.rsaPublicKeyDER(modulus: modulus, exponent: exponent)
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: 1024
        ]
        var keyError: Unmanaged<CFError>?
        guard let publicKey = SecKeyCreateWithData(der as CFData, attributes as CFDictionary, &keyError) else {
            throw DashAuthError.invalidPublicKey
        }
        guard SecKeyIsAlgorithmSupported(publicKey, .encrypt, .rsaEncryptionPKCS1) else {
            throw DashAuthError.invalidPublicKey
        }
        var encryptionError: Unmanaged<CFError>?
        guard let encrypted = SecKeyCreateEncryptedData(publicKey, .rsaEncryptionPKCS1, payload as CFData, &encryptionError) as Data? else {
            throw DashAuthError.encryptionFailed(encryptionError?.takeRetainedValue().localizedDescription ?? "RSA encryption failed")
        }
        sessionKey = aesKey
        return try K1GPacket.authKeyPacket(ciphertext: encrypted)
        #else
        throw DashAuthError.securityFrameworkUnavailable
        #endif
    }

    #if canImport(Security)
    private static func rsaPublicKeyDER(modulus: Data, exponent: Data) -> Data {
        func integer(_ input: Data) -> Data {
            var bytes = Array(input.drop(while: { $0 == 0 }))
            if bytes.isEmpty { bytes = [0] }
            if bytes[0] & 0x80 != 0 { bytes.insert(0, at: 0) }
            return Data([0x02]) + derLength(bytes.count) + Data(bytes)
        }
        let body = integer(modulus) + integer(exponent)
        return Data([0x30]) + derLength(body.count) + body
    }

    private static func derLength(_ length: Int) -> Data {
        if length < 128 { return Data([UInt8(length)]) }
        var value = length
        var bytes: [UInt8] = []
        while value > 0 {
            bytes.insert(UInt8(value & 0xff), at: 0)
            value >>= 8
        }
        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }
    #endif
}
