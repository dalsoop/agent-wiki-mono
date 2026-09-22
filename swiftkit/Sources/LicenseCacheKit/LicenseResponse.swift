import Foundation

/// 서버 `/api/license/check` 응답 모델.
public struct LicenseResponse: Codable, Sendable, Equatable {
    public let valid: Bool
    public let accessLevel: AccessLevel
    public let plan: String?
    public let expiresAt: Date?
    public let checkIntervalSeconds: Int
    public let offlineGraceHours: Int
    public let features: [String]
    public let lineage: String?

    enum CodingKeys: String, CodingKey {
        case valid
        case accessLevel = "access_level"
        case plan
        case expiresAt = "expires_at"
        case checkIntervalSeconds = "check_interval_seconds"
        case offlineGraceHours = "offline_grace_hours"
        case features
        case lineage
    }

    public var effectiveAccessLevel: AccessLevel {
        valid ? accessLevel : .blocked
    }
}
