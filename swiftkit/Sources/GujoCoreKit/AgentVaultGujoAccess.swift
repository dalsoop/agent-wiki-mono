import AgentVaultClientKit
import Foundation

/// Gujo 자격 접근 실패. 비밀도, vault CLI 원문도 싣지 않는다.
public struct GujoVaultError: LocalizedError, Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// AgentVaultClientKit 경계.
/// - `check`: 권한 게이트 (비밀 없음)
/// - `resolveAPIKey`: in-process 소비 (#28 D8). 이 앱은 gujo.ai API 를 URLSession 으로
///   직접 치므로 `use(command:)` 서브프로세스 경로를 쓸 수 없다.
///
/// 반환된 API key 는 **저장하지 않는다** — 요청 수명 동안만 메모리에 둔다.
public enum AgentVaultGujoAccess {
    /// 실행 중인 바이너리로 **실제 등록된** agentID 를 찾는다.
    ///
    /// 상수로 박으면 안 되는 이유가 실측으로 둘이다:
    ///  - `@macbook` 은 hostname 이 아니라 사람이 정한 라벨이다. 다른 기계엔 없다.
    ///  - 등록된 이름이 슬러그와 다를 수 있다 — `/Applications/Gujo Cloud Apps.app`
    ///    은 `app:gujo-cloud-apps@…` 가 아니라 `app:gujo@macbook` 으로 등록돼 있다.
    ///
    /// 못 찾으면 nil 을 돌려 호출자가 "등록되지 않았다" 를 그대로 말하게 한다.
    /// 지어낸 ID 를 넘기면 vault 가 usage 오류로 돌려줘 진짜 원인이 가려진다.
    public static func resolveAgentID(
        executablePath: String = ProcessInfo.processInfo.arguments.first ?? "",
        client: any AgentVaultAccessClient = AgentVaultCLIClient()
    ) async -> String? {
        await client.registeredAgentID(executablePath: executablePath)
    }

    /// 카드가 실제로 속한 작업 공간. 상수(`tenant:gujo`)는 이 vault 에 존재하지 않았다.
    public static func resolveTenantID(
        credentialID: String,
        client: any AgentVaultAccessClient = AgentVaultCLIClient()
    ) async -> String? {
        await client.ownerTenantID(credentialID: credentialID)
    }

    public struct CheckResult: Equatable, Sendable {
        public let allowed: Bool
        public let reason: String?

        public init(allowed: Bool, reason: String?) {
            self.allowed = allowed
            self.reason = reason
        }
    }

    /// 선택된 vault 카드에 이 앱 에이전트의 사용 권한이 있는지 확인한다.
    public static func check(
        credentialID: String,
        tenantID: String? = nil,
        agentID: String? = nil,
        client: any AgentVaultAccessClient = AgentVaultCLIClient()
    ) async -> CheckResult {
        let pin = credentialID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pin.isEmpty else {
            return CheckResult(allowed: false, reason: LibraryAccessFailure.noCredential.localizedDescription)
        }
        guard let resolvedAgent = await resolved(agentID, client: client) else {
            return CheckResult(allowed: false, reason: LibraryAccessFailure.noCredential.localizedDescription)
        }
        let resolvedTenant = await resolved(tenantID, credentialID: pin, client: client)
        do {
            let gate = try await client.check(context(pin, resolvedTenant, resolvedAgent))
            if gate.allowed { return CheckResult(allowed: true, reason: nil) }
            let reason = gate.reason?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let reason, !reason.isEmpty {
                return CheckResult(allowed: false, reason: reason)
            }
            return CheckResult(allowed: false, reason: LibraryAccessFailure.noCredential.localizedDescription)
        } catch {
            return CheckResult(
                allowed: false,
                reason: LibraryAccessFailure.unknown(error.localizedDescription).localizedDescription)
        }
    }

    /// 선택된 카드에서 gujo API key 를 받는다. 앱은 이 값을 저장하지 않는다.
    /// 호출 스코프 안에서만 쓰고 버린다.
    public static func resolveAPIKey(
        credentialID: String,
        tenantID: String? = nil,
        agentID: String? = nil,
        client: any AgentVaultAccessClient = AgentVaultCLIClient()
    ) async throws -> String {
        let pin = credentialID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pin.isEmpty else { throw LibraryAccessFailure.noCredential }
        guard let resolvedAgent = await resolved(agentID, client: client) else {
            throw LibraryAccessFailure.noCredential
        }
        let resolvedTenant = await resolved(tenantID, credentialID: pin, client: client)
        let secret: AgentVaultSecret
        do {
            secret = try await client.fetch(context(pin, resolvedTenant, resolvedAgent))
        } catch let failure as LibraryAccessFailure {
            throw failure
        } catch {
            throw LibraryAccessFailure.unknown(error.localizedDescription)
        }
        let value = secret.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            throw LibraryAccessFailure.noCredential
        }
        return value
    }

    static let notRegisteredMessage = LibraryAccessFailure.noCredential.localizedDescription

    /// 명시값 > 레지스트리 조회 > 후보 상수. 조회가 비면 nil 로 남겨 원인을 드러낸다.
    private static func resolved(
        _ explicit: String?, client: any AgentVaultAccessClient
    ) async -> String? {
        if let explicit = explicit?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicit.isEmpty { return explicit }
        return await resolveAgentID(client: client)
    }

    /// 작업 공간은 카드가 안다. 못 찾으면 nil — vault 가 active 작업 공간으로 판단한다.
    private static func resolved(
        _ explicit: String?, credentialID: String, client: any AgentVaultAccessClient
    ) async -> String? {
        if let explicit = explicit?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicit.isEmpty { return explicit }
        return await resolveTenantID(credentialID: credentialID, client: client)
    }

    private static func context(
        _ credentialID: String, _ tenantID: String?, _ agentID: String
    ) -> AgentVaultCredentialContext {
        AgentVaultCredentialContext(
            tenantID: tenantID ?? "", credentialID: credentialID, agentID: agentID)
    }
}
