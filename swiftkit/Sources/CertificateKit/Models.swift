import Foundation
import StateMirrorKit

// MARK: - Value Types

/// 공동인증서 참조 — 파일 경로 직접 노출 없이 소비자 앱에 전달되는 값 객체.
/// joint-certificate-manager 가 StateMirror 에 발행하고, CertificateClient 가 읽는다.
public struct CertificateRef: Codable, Sendable, Equatable {
    public let certURL: URL
    public let keyURL: URL?
    public let issuer: String
    public let subject: String
    public let policyOID: String?
    public let validUntil: Date
    public let sourceType: String   // "npkiMac" | "npkiUsb" | "pfx"

    public init(
        certURL: URL,
        keyURL: URL?,
        issuer: String,
        subject: String,
        policyOID: String?,
        validUntil: Date,
        sourceType: String
    ) {
        self.certURL = certURL
        self.keyURL = keyURL
        self.issuer = issuer
        self.subject = subject
        self.policyOID = policyOID
        self.validUntil = validUntil
        self.sourceType = sourceType
    }

    /// 만료 여부.
    public var isExpired: Bool { Date() > validUntil }

    /// 30일 이내 만료 임박.
    public var isExpiringSoon: Bool {
        !isExpired && validUntil.timeIntervalSinceNow < 30 * 86400
    }

    /// D-Day (음수면 이미 만료).
    public var daysRemaining: Int {
        Int(validUntil.timeIntervalSinceNow / 86400)
    }
}

/// 비밀번호는 vault 카드 ID 만 전달 — 실제 값은 절대 앱 간 이동하지 않는다.
public struct CertificatePasswordRef: Codable, Sendable {
    /// agent-vault 카드 식별자.
    public let vaultCardId: String

    public init(vaultCardId: String) {
        self.vaultCardId = vaultCardId
    }
}

// MARK: - StateMirror State

/// joint-certificate-manager 가 StateMirror 에 발행하는 상태 구조체.
/// CertificateKit 소비자는 이 타입으로 역직렬화한다.
public struct CertificateHubState: Codable, Sendable {
    public let activeCertId: String?
    public let activeCertPath: String?
    public let activeKeyPath: String?
    public let activeIssuer: String?
    public let activeSubject: String?
    public let activePolicyOID: String?
    public let activeValidUntil: Date?
    public let activeSourceType: String?
    public let vaultCardId: String?
    public let totalCount: Int
    public let lastScannedAt: Date?

    public init(
        activeCertId: String? = nil,
        activeCertPath: String? = nil,
        activeKeyPath: String? = nil,
        activeIssuer: String? = nil,
        activeSubject: String? = nil,
        activePolicyOID: String? = nil,
        activeValidUntil: Date? = nil,
        activeSourceType: String? = nil,
        vaultCardId: String? = nil,
        totalCount: Int = 0,
        lastScannedAt: Date? = nil
    ) {
        self.activeCertId = activeCertId
        self.activeCertPath = activeCertPath
        self.activeKeyPath = activeKeyPath
        self.activeIssuer = activeIssuer
        self.activeSubject = activeSubject
        self.activePolicyOID = activePolicyOID
        self.activeValidUntil = activeValidUntil
        self.activeSourceType = activeSourceType
        self.vaultCardId = vaultCardId
        self.totalCount = totalCount
        self.lastScannedAt = lastScannedAt
    }

    /// StateMirror 앱 식별자 — joint-certificate-manager 와 일치해야 한다.
    public static let mirrorAppId = "joint-certificate-manager"

    /// State → CertificateRef 변환. activeCertPath 가 없으면 nil.
    public func toCertificateRef() -> CertificateRef? {
        guard
            let path = activeCertPath,
            let issuer = activeIssuer,
            let subject = activeSubject,
            let validUntil = activeValidUntil,
            let sourceType = activeSourceType
        else { return nil }

        let certURL = URL(fileURLWithPath: path)
        let keyURL  = activeKeyPath.map { URL(fileURLWithPath: $0) }

        return CertificateRef(
            certURL: certURL,
            keyURL: keyURL,
            issuer: issuer,
            subject: subject,
            policyOID: activePolicyOID,
            validUntil: validUntil,
            sourceType: sourceType
        )
    }

    /// vaultCardId → CertificatePasswordRef.
    public func toPasswordRef() -> CertificatePasswordRef? {
        vaultCardId.map { CertificatePasswordRef(vaultCardId: $0) }
    }
}
