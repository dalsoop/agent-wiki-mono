import AgentVaultClientKit
import Foundation

/// 사람 로그인이 없는 러너·CI 전용 토큰 출처(계약 §4). 앱 GUI 는 항상 device-code 로그인이 먼저고,
/// 이 폴백은 Keychain 이 비었을 때만 물어본다.
public protocol StaffTokenFallback: Sendable {
    /// `gst_` 토큰. 없으면 nil(오류가 아니다 — 폴백은 선택 사항).
    func staffToken() async -> String?
}

/// agent-vault 카드 `tenant:gujo` / 필드 `staff-token`.
///
/// 카드는 이름 또는 계정 칸이 `staff-token` 인 것을 고르고, 작업 공간은 카드가 스스로 아는
/// `ownerTenantID`(없으면 `tenant:gujo`)를 쓴다. agentID 는 실행 바이너리로 등록된 것을 찾는다 —
/// 지어낸 ID 를 넘기면 vault 가 usage 오류(64)로 원인을 가린다.
public struct AgentVaultStaffTokenFallback: StaffTokenFallback {
    public static let tenantID = "tenant:gujo"
    public static let fieldName = "staff-token"

    private let client: any AgentVaultAccessClient
    private let executablePath: String

    public init(
        client: any AgentVaultAccessClient = AgentVaultCLIClient(),
        executablePath: String = ProcessInfo.processInfo.arguments.first ?? ""
    ) {
        self.client = client
        self.executablePath = executablePath
    }

    public func staffToken() async -> String? {
        guard let agentID = await client.registeredAgentID(executablePath: executablePath) else {
            return nil
        }
        do {
            guard let card = try await client.credentials().first(where: Self.matches) else {
                return nil
            }
            let context = AgentVaultCredentialContext(
                tenantID: card.ownerTenantID ?? Self.tenantID,
                credentialID: card.id,
                agentID: agentID)
            let value = try await client.fetch(context).value.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        } catch {
            return nil
        }
    }

    static func matches(_ card: AgentVaultCard) -> Bool {
        guard card.archivedAt == nil else { return false }
        let tenantOK = card.ownerTenantID == nil || card.ownerTenantID == tenantID
        let fieldOK = card.name == fieldName || card.account == fieldName
        return tenantOK && fieldOK
    }
}

/// 폴백 없음 — 테스트와 "Keychain 만" 정책 앱용.
public struct NoStaffTokenFallback: StaffTokenFallback {
    public init() {}
    public func staffToken() async -> String? { nil }
}

/// 고정 토큰 폴백 — 테스트용. 실제 앱에서 토큰 리터럴을 이 타입에 박지 말 것.
public struct StaticStaffTokenFallback: StaffTokenFallback {
    private let token: String?
    public init(_ token: String?) { self.token = token }
    public func staffToken() async -> String? { token }
}

public enum StaffTokenFallbacks {
    public static func `default`() -> any StaffTokenFallback {
        AgentVaultStaffTokenFallback()
    }
}
