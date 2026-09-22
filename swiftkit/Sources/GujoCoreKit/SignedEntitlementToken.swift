#if canImport(CryptoKit)
import CryptoKit
#endif
import Foundation

/// Gujo Cloud Apps 관리 앱 권한 상태.
public enum GujoManagedStatus: String, Sendable, Equatable, Codable {
    case cloudAppsMissing
    case notConnected
    case notEntitled
    case available
}

/// Gujo Cloud Apps 가 발급/검증하는 서명된 엔타이틀먼트 토큰.
///
/// 기존 `UserDefaults` 기반 `lastKnown` 평문 대신 암호학적 Ed25519 서명과
/// TTL 30일(철회 시 24시간 grace period)을 검증하여 오프라인 판정 위변조를 방지한다.
public struct SignedEntitlementToken: Codable, Sendable, Equatable {
    /// 기본 유효 기간: 30일 (2,592,000초)
    public static let defaultTTL: TimeInterval = 30 * 24 * 60 * 60
    /// 철회(revocation) 시 부여되는 유예 기간: 24시간 (86,400초)
    public static let revocationGracePeriod: TimeInterval = 24 * 60 * 60

    /// 기본 내장 검증용 공개키 (Curve25519 EdDSA base64url).
    public static let defaultPublicKey: String = "dyOm_RdedofBuDf38c1unku3_OE24_h6zrSzx4w5BPA"

    public var bundleID: String
    public var status: GujoManagedStatus
    public var issuedAt: Date
    public var expiresAt: Date?
    public var revokedAt: Date?
    public var signature: String

    public init(
        bundleID: String,
        status: GujoManagedStatus = .available,
        issuedAt: Date = Date(),
        expiresAt: Date? = nil,
        revokedAt: Date? = nil,
        signature: String = ""
    ) {
        self.bundleID = bundleID
        self.status = status
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        self.revokedAt = revokedAt
        self.signature = signature
    }

    /// 서명 대상 결정론적 페이로드
    public var payloadData: Data {
        let expStr = expiresAt.map { String(Int64($0.timeIntervalSince1970)) } ?? ""
        let revStr = revokedAt.map { String(Int64($0.timeIntervalSince1970)) } ?? ""
        let parts = [
            bundleID,
            status.rawValue,
            String(Int64(issuedAt.timeIntervalSince1970)),
            expStr,
            revStr,
        ]
        return Data(parts.joined(separator: "|").utf8)
    }

    /// TTL 만료 여부 (기본 30일)
    public func isExpired(at date: Date = Date()) -> Bool {
        let expiration = expiresAt ?? issuedAt.addingTimeInterval(Self.defaultTTL)
        return date > expiration
    }

    /// 철회(revocation) 상태인지 여부
    public var isRevoked: Bool {
        revokedAt != nil
    }

    /// 철회 후 24시간 유예 기간(grace period) 이내인지 여부
    public func isWithinRevocationGracePeriod(at date: Date = Date()) -> Bool {
        guard let revoked = revokedAt else { return false }
        let deadline = revoked.addingTimeInterval(Self.revocationGracePeriod)
        return date >= revoked && date < deadline
    }

    /// 철회 후 24시간 유예 기간마저 초과했는지 여부
    public func isRevocationGracePeriodExpired(at date: Date = Date()) -> Bool {
        guard let revoked = revokedAt else { return false }
        let deadline = revoked.addingTimeInterval(Self.revocationGracePeriod)
        return date >= deadline
    }

    /// 서명 검증
    public func verifySignature(publicKey: String = SignedEntitlementToken.defaultPublicKey) -> Bool {
        #if canImport(CryptoKit)
        guard let pubData = Data(base64URLOrStandard: publicKey),
              let sigData = Data(base64URLOrStandard: signature) else {
            return false
        }
        do {
            let pubKey = try Curve25519.Signing.PublicKey(rawRepresentation: pubData)
            return pubKey.isValidSignature(sigData, for: payloadData)
        } catch {
            return false
        }
        #else
        return true
        #endif
    }

    /// 토큰의 전체 유효성 검사:
    /// 1. 서명 검증 통과
    /// 2. 번들 ID 일치 (지정된 경우)
    /// 3. TTL (30일) 미만료
    /// 4. 철회된 경우 24시간 grace period 이내여야 함 (24시간 초과 시 무효)
    public func isValid(
        at date: Date = Date(),
        expectedBundleID: String? = nil,
        publicKey: String = SignedEntitlementToken.defaultPublicKey
    ) -> Bool {
        if let expected = expectedBundleID, !expected.isEmpty, bundleID != expected {
            return false
        }
        if isExpired(at: date) {
            return false
        }
        if isRevocationGracePeriodExpired(at: date) {
            return false
        }
        return verifySignature(publicKey: publicKey)
    }

    /// 유효성 판정 후 실제 상태 반환. 유효하지 않으면 nil.
    public func effectiveStatus(
        at date: Date = Date(),
        expectedBundleID: String? = nil,
        publicKey: String = SignedEntitlementToken.defaultPublicKey
    ) -> GujoManagedStatus? {
        guard isValid(at: date, expectedBundleID: expectedBundleID, publicKey: publicKey) else {
            return nil
        }
        return status
    }

    // MARK: - 서명 발급 (테스트 및 발급 Seam)
    #if canImport(CryptoKit)
    public static func sign(
        bundleID: String,
        status: GujoManagedStatus = .available,
        issuedAt: Date = Date(),
        expiresAt: Date? = nil,
        revokedAt: Date? = nil,
        privateKey: String
    ) throws -> SignedEntitlementToken {
        guard let privData = Data(base64URLOrStandard: privateKey) else {
            throw TokenSignError.invalidPrivateKey
        }
        let priv: Curve25519.Signing.PrivateKey
        do {
            priv = try Curve25519.Signing.PrivateKey(rawRepresentation: privData)
        } catch {
            throw TokenSignError.invalidPrivateKey
        }
        var token = SignedEntitlementToken(
            bundleID: bundleID,
            status: status,
            issuedAt: issuedAt,
            expiresAt: expiresAt,
            revokedAt: revokedAt,
            signature: ""
        )
        let sig = try priv.signature(for: token.payloadData)
        token.signature = sig.base64URLEncodedString()
        return token
    }
    #endif

    // MARK: - Serialization
    public func encodeToken() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        return String(data: data, encoding: .utf8) ?? ""
    }

    public static func parse(_ raw: String) throws -> SignedEntitlementToken {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("set1.") {
            let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count == 3,
                  let payloadData = Data(base64URLOrStandard: String(parts[1])) else {
                throw TokenSignError.malformedToken
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var token = try decoder.decode(SignedEntitlementToken.self, from: payloadData)
            token.signature = String(parts[2])
            return token
        }
        guard let data = trimmed.data(using: .utf8) else {
            throw TokenSignError.malformedToken
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SignedEntitlementToken.self, from: data)
    }
}

public enum TokenSignError: Error, LocalizedError, Equatable {
    case invalidPrivateKey
    case invalidPublicKey
    case malformedToken
    case invalidSignature
    case expired
    case revoked
    case unsupportedPlatform

    public var errorDescription: String? {
        switch self {
        case .invalidPrivateKey: return "유효하지 않은 개인키입니다."
        case .invalidPublicKey: return "유효하지 않은 공개키입니다."
        case .malformedToken: return "토큰 형식이 올바르지 않습니다."
        case .invalidSignature: return "토큰 서명이 유효하지 않습니다."
        case .expired: return "토큰 유효기간(TTL 30일)이 만료되었습니다."
        case .revoked: return "토큰이 철회되었으며 유예기간(24시간)이 종료되었습니다."
        case .unsupportedPlatform: return "현재 플랫폼에서는 암호 연산을 지원하지 않습니다."
        }
    }
}

// MARK: - Data Base64/Base64URL Extension
extension Data {
    init?(base64URLOrStandard value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let d = Data(base64Encoded: trimmed) {
            self = d
            return
        }

        var base64 = trimmed.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64.append(String(repeating: "=", count: (4 - base64.count % 4) % 4))
        if let d = Data(base64Encoded: base64) {
            self = d
            return
        }
        return nil
    }

    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
