import Foundation
import GujoAuthKit

/// `/store/releases/intake` · `/lecture/releases/intake` — 옛 `auth.intake` 토큰 경로(계약 §3).
public struct IntakeAPI: Sendable {
    let client: GujoStaffAPIClient

    public func storeReleasesIntake(_ release: ReleaseIntake) async throws -> ReleaseIntakeReceipt {
        try await client.call(
            "POST", GujoStaffRoutes.storeIntake, body: release, requires: StaffAbility.releaseIntake,
            as: Single<ReleaseIntakeReceipt>.self).data
    }

    public func lectureReleasesIntake(_ release: ReleaseIntake) async throws -> ReleaseIntakeReceipt {
        try await client.call(
            "POST", GujoStaffRoutes.lectureIntake, body: release, requires: StaffAbility.releaseIntake,
            as: Single<ReleaseIntakeReceipt>.self).data
    }
}

/// 스킬 발행 경로 — 옛 `skill.auth` 토큰 경로(계약 §3).
public struct SkillsAPI: Sendable {
    let client: GujoStaffAPIClient
    private var root: String { GujoStaffRoutes.skills }

    public func publish(_ skill: SkillPublish) async throws -> SkillRecord {
        try await client.call(
            "POST", root + "/publish", body: skill, requires: StaffAbility.skillPublish, as: Single<SkillRecord>.self).data
    }

    public func delete(slug: String) async throws {
        _ = try await client.call("DELETE", "\(root)/\(encode(slug))", requires: StaffAbility.skillPublish, as: Empty.self)
    }

    public func deprecate(slug: String, reason: String? = nil) async throws -> SkillRecord {
        struct Body: Encodable { let reason: String? }
        return try await client.call(
            "POST", "\(root)/\(encode(slug))/deprecate", body: Body(reason: reason), requires: StaffAbility.skillPublish,
            as: Single<SkillRecord>.self).data
    }

    private func encode(_ slug: String) -> String {
        slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? slug
    }
}
