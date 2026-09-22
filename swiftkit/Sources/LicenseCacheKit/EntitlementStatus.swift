import Foundation

/// 라이선스/자격 상태 판정 결과.
public enum EntitlementStatus: String, Sendable, Equatable, Codable {
    case available
    case notEntitled
    case notConnected
    case unavailable
    case authorityMissing
}
