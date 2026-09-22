#if canImport(CryptoKit)
import CryptoKit
#endif
import Foundation

/// 판매처와 무관하게 발급자가 서명하는 라이선스의 공개 클레임.
/// 고객 이메일이나 실명은 넣지 않고 불투명 식별자만 포함한다.
public struct SignedLicenseClaims: Codable, Sendable, Equatable {
    public let issuerIdentifier: String
    public let productIdentifier: String
    public let entitlementIdentifier: String
    public let customerIdentifier: String
    public let planIdentifier: String
    public let issuedAt: Date
    public let expiresAt: Date?
    public let featureIdentifiers: [String]
    public let deviceLimit: Int

    public struct Validity: Sendable, Equatable {
        public var issuedAt: Date
        public var expiresAt: Date?

        public init(issuedAt: Date, expiresAt: Date?) {
            self.issuedAt = issuedAt
            self.expiresAt = expiresAt
        }
    }

    public init(
        issuerIdentifier: String, productIdentifier: String, entitlementIdentifier: String,
        customerIdentifier: String, planIdentifier: String, validity: Validity,
        featureIdentifiers: [String], deviceLimit: Int
    ) {
        self.issuerIdentifier = issuerIdentifier
        self.productIdentifier = productIdentifier
        self.entitlementIdentifier = entitlementIdentifier
        self.customerIdentifier = customerIdentifier
        self.planIdentifier = planIdentifier
        self.issuedAt = validity.issuedAt
        self.expiresAt = validity.expiresAt
        self.featureIdentifiers = featureIdentifiers
        self.deviceLimit = deviceLimit
    }
}

public enum SignedLicenseError: Error, LocalizedError, Equatable {
    case invalidPrivateKey
    case invalidPublicKey
    case malformedToken
    case invalidSignature
    case wrongProduct
    case expired
    /// CryptoKit 이 없는 플랫폼(Linux CI 등)에서 서명 연산을 요청한 경우.
    case unsupportedPlatform

    public var errorDescription: String? {
        switch self {
        case .invalidPrivateKey: "라이선스 서명 개인 키가 올바르지 않습니다."
        case .invalidPublicKey: "앱에 설정된 라이선스 공개 키가 올바르지 않습니다."
        case .malformedToken: "라이선스 키 형식이 올바르지 않습니다."
        case .invalidSignature: "라이선스 서명을 확인할 수 없습니다."
        case .wrongProduct: "다른 제품용 라이선스입니다."
        case .expired: "라이선스가 만료되었습니다."
        case .unsupportedPlatform: "이 플랫폼에서는 라이선스 서명 연산을 지원하지 않습니다."
        }
    }
}

public enum SignedLicenseCodec {
    public static func generatePrivateKey() -> String {
        #if canImport(CryptoKit)
        Curve25519.Signing.PrivateKey().rawRepresentation.base64URLEncodedString()
        #else
        ""
        #endif
    }

    public static func publicKey(privateKey: String) throws -> String {
        #if canImport(CryptoKit)
        guard let raw = Data(base64URLOrStandard: privateKey),
              let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else {
            throw SignedLicenseError.invalidPrivateKey
        }
        return key.publicKey.rawRepresentation.base64URLEncodedString()
        #else
        throw SignedLicenseError.unsupportedPlatform
        #endif
    }

    public static func issue(_ claims: SignedLicenseClaims, privateKey: String) throws -> String {
        #if canImport(CryptoKit)
        guard let raw = Data(base64URLOrStandard: privateKey),
              let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else {
            throw SignedLicenseError.invalidPrivateKey
        }
        let payload = try encoder.encode(claims)
        let signature = try key.signature(for: payload)
        return "sl1.\(payload.base64URLEncodedString()).\(signature.base64URLEncodedString())"
        #else
        throw SignedLicenseError.unsupportedPlatform
        #endif
    }

    public static func verify(
        _ token: String, publicKey: String, expectedProductIdentifier: String,
        now: Date = Date()
    ) throws -> SignedLicenseClaims {
        #if canImport(CryptoKit)
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "sl1",
              let payload = Data(base64URLOrStandard: String(parts[1])),
              let signature = Data(base64URLOrStandard: String(parts[2])) else {
            throw SignedLicenseError.malformedToken
        }
        guard let publicData = Data(base64URLOrStandard: publicKey),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicData) else {
            throw SignedLicenseError.invalidPublicKey
        }
        guard key.isValidSignature(signature, for: payload) else { throw SignedLicenseError.invalidSignature }
        guard let claims = try? decoder.decode(SignedLicenseClaims.self, from: payload) else {
            throw SignedLicenseError.malformedToken
        }
        guard claims.productIdentifier == expectedProductIdentifier else { throw SignedLicenseError.wrongProduct }
        if let expiresAt = claims.expiresAt, expiresAt <= now { throw SignedLicenseError.expired }
        return claims
        #else
        throw SignedLicenseError.unsupportedPlatform
        #endif
    }

    private static var encoder: JSONEncoder {
        let value = JSONEncoder()
        value.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        value.dateEncodingStrategy = .millisecondsSince1970
        return value
    }

    private static var decoder: JSONDecoder {
        let value = JSONDecoder()
        value.dateDecodingStrategy = .millisecondsSince1970
        return value
    }
}

