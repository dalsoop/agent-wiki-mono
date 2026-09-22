import Foundation
import MoneyLedgerStoreKit
import MoneyLedgerModels
import VaultwardenKit

/// Secure Note 저장 추상화 — 테스트는 가짜, 실전은 VaultSession.
/// vaultwarden-client 의 브로커 소켓은 agent-browser 전용 allowlist 라 못 쓴다.
/// env-vault 가 검증한 경로(VaultSession 직접 링크 + Secure Note) 를 그대로 따른다.
/// 주의: VaultSession.save() 는 카드형(cipher type 3) 필드를 쓰지 못한다 — Secure Note 가 정답.
public protocol SecureNoteStoring: Sendable {
    func saveNote(name: String, text: String) async throws
    func readNote(name: String) async throws -> String?
    func deleteNote(name: String) async throws -> Bool
}

/// Vault 연결 상태 — GUI 배지·CLI vault status 공용.
public enum LedgerVaultStatus: String, Codable, Sendable {
    /// 로그인·해제 완료 — 읽기/쓰기 가능.
    case available
    /// 계정은 있으나 잠김 — 마스터 비밀번호(env) 또는 Touch ID 필요.
    case locked
    /// 로그인한 적 없음 — vault link 전에 `vault login` 필요.
    case unconfigured
}

/// 민감정보(계좌·카드 전체번호) Vaultwarden 게이트웨이.
/// 원장에는 노트 이름(vaultNoteRef)만 남는다 — Vault 가 잠겨 있어도 원장 기능은 전부 동작한다.
public actor LedgerVault {
    private let context: LedgerContext
    private let session: VaultSession
    private let environment: [String: String]

    public init(
        context: LedgerContext,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.context = context
        self.session = VaultSession(keychain: KeychainStore(service: context.vaultKeychainService))
        self.environment = environment
    }

    public func status() async -> LedgerVaultStatus {
        guard await session.hasAccount else { return .unconfigured }
        if await session.isUnlocked { return .available }
        return .locked
    }

    public func accountEmail() async -> String? {
        await session.accountEmail
    }

    public func serverURL() async -> String? {
        await session.serverURL
    }

    /// 최초 1회 로그인(서버·이메일·마스터비밀번호). env-vault 의 login 관례.
    public func login(server: String, email: String, password: String) async throws {
        let endpoint: ServerEndpoint
        switch server.lowercased() {
        case "us": endpoint = .cloudUS
        case "eu": endpoint = .cloudEU
        default: endpoint = try ServerEndpoint.selfHosted(server)
        }
        try await session.login(endpoint: endpoint, email: email, password: password)
    }

    /// 무인 경로(env 마스터비밀번호) → 대화 경로(Touch ID) 순으로 해제.
    public func unlockIfNeeded() async throws {
        if await session.isUnlocked { return }
        guard await session.hasAccount else { throw LedgerVaultError.notConfigured }
        if let password = environment[context.masterPasswordEnvKey], !password.isEmpty {
            try await session.unlock(password: password)
            return
        }
        try await session.unlockWithBiometrics()
    }

    /// 민감값 저장 → 노트 이름 반환(entity 의 vaultNoteRef 로 저장할 것).
    public func storeSecret(entity: String, id: String, text: String) async throws -> String {
        try await unlockIfNeeded()
        let name = context.vaultNoteName(entity: entity, id: id)
        try await session.saveSecureNote(name: name, text: text)
        return name
    }

    public func readSecret(noteRef: String) async throws -> String? {
        try await unlockIfNeeded()
        return try await session.secureNoteText(name: noteRef)
    }

    @discardableResult
    public func deleteSecret(noteRef: String) async throws -> Bool {
        try await unlockIfNeeded()
        return try await session.deleteSecureNote(name: noteRef)
    }
}

public enum LedgerVaultError: Error, Equatable, CustomStringConvertible {
    case notConfigured

    public var description: String {
        "Vaultwarden 계정이 연결돼 있지 않습니다 — vault login <server> <email> 먼저 (비밀번호는 stdin)"
    }
}
