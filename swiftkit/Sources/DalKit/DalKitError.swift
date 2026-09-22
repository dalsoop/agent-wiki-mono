import Foundation

public enum DalKitError: Error, Sendable, Equatable, LocalizedError {
    case tenantRequired
    case emptyTenant
    case invalidTenant(String)
    case viewpointRejected(String)
    case claimLie(String)

    public var errorDescription: String? {
        switch self {
        case .tenantRequired:
            return "TENANT_ID 또는 agent-tenant context 또는 --tenant 필요"
        case .emptyTenant:
            return "tenant 가 비어 있다"
        case .invalidTenant(let raw):
            return "invalid tenant: \(raw)"
        case .viewpointRejected(let v):
            return "viewpoint=\(v) 거부 — first 만 허용 (third/unknown 금지)"
        case .claimLie(let detail):
            return "claim mismatch: \(detail)"
        }
    }
}
