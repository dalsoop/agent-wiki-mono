import Foundation

struct VaultSessionStoredAccount: Codable {
    var endpoint: ServerEndpoint
    var email: String
    var kdf: Int
    var iterations: Int
}

/// 로그인 → 동기화 → 복호화 → CRUD 를 담당하는 세션 액터.
/// 잠금 시 메모리의 키를 폐기한다. Touch ID 재잠금해제는 Keychain 의
/// 생체 보호 항목(userKey)으로 한다.
public actor VaultSession {
    public enum SessionError: Error, LocalizedError, Equatable {
        case notUnlocked
        case noStoredKey
        case noAccount
        /// 이 킷이 왕복시키지 못하는 cipher 유형 — 저장하면 값이 지워지므로 손대지 않는다.
        case unsupportedItemType(Int)
        /// 새 로그인 항목은 웹 주소가 필수. 비우면 Bitwarden 이 웹사이트를 지운 것과 같다.
        case missingLoginURI

        public var errorDescription: String? {
            switch self {
            case .notUnlocked: return "볼트가 잠겨 있습니다"
            case .noStoredKey: return "저장된 잠금해제 키가 없습니다 — 마스터 패스워드로 잠금해제하세요"
            case .noAccount: return "로그인된 계정이 없습니다"
            case let .unsupportedItemType(type):
                return "\(VaultCipherType.label(type)) 항목은 이 앱이 아직 다루지 못합니다 — "
                    + "그대로 저장하면 값이 지워지므로 건드리지 않습니다"
            case .missingLoginURI:
                return "로그인 항목은 웹 주소(URI)가 필수입니다"
            }
        }
    }

    let keychain: KeychainStore
    var client: VaultwardenAPI?
    var accessToken: String?
    var refreshToken: String?
    var userKey: BitwardenCrypto.SymmetricKeySet?
    var kdf: BitwardenCrypto.KdfConfig?

    static let acctRefreshToken = "refreshToken"
    static let acctUserKey = "userKey.protected"
    static let acctAccount = "account"

    /// 진단(keychain-doctor) — 이 세션이 쓰는 키체인 항목 계정명 목록.
    public static let diagnosticAccounts = [acctAccount, acctRefreshToken, acctUserKey]

    public init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
    }

    /// 로그인 계정이 남아 있는가 (잠금 상태 포함).
    public var hasAccount: Bool {
        keychain.get(account: Self.acctAccount) != nil
    }

    public var isUnlocked: Bool { userKey != nil }

    public var accountEmail: String? { storedAccount()?.email }
    public var serverURL: String? { storedAccount()?.endpoint.label }
    public var serverEndpoint: ServerEndpoint? { storedAccount()?.endpoint }

    func storedAccount() -> VaultSessionStoredAccount? {
        keychain.get(account: Self.acctAccount)
            .flatMap { try? JSONDecoder().decode(VaultSessionStoredAccount.self, from: $0) }
    }

    /// 최초 로그인: prelogin → 마스터키 유도 → 토큰 발급 → 사용자 키 복호화.
    /// 서버가 2FA를 요구하면 `TwoFactorRequired` 를 그대로 throw 하며,
    /// 호출자는 코드를 받아 `twoFactor` 를 채워 재호출한다.
    public func login(endpoint: ServerEndpoint, email: String, password: String,
                      twoFactor: (code: String, provider: Int, remember: Bool)? = nil,
                      newDeviceOtp: String? = nil) async throws {
        let client = VaultwardenAPI(endpoint: endpoint)
        let pre = try await client.prelogin(email: email)
        let kdf = BitwardenCrypto.KdfConfig(kdf: pre.kdf, iterations: pre.kdfIterations)
        let masterKey = try BitwardenCrypto.masterKey(password: password, email: email, kdf: kdf)
        let hash = BitwardenCrypto.masterPasswordHash(masterKey: masterKey, password: password)

        let deviceID = deviceIdentifier()
        let token = try await client.login(email: email, passwordHash: hash,
                                           deviceID: deviceID, twoFactor: twoFactor,
                                           newDeviceOtp: newDeviceOtp)

        let stretched = BitwardenCrypto.stretchedKey(masterKey: masterKey)
        var key: BitwardenCrypto.SymmetricKeySet?
        if let encKey = token.key {
            let rawUserKey = try BitwardenCrypto.decrypt(
                BitwardenCrypto.EncString(parse: encKey), key: stretched)
            key = BitwardenCrypto.SymmetricKeySet(raw: rawUserKey)
        }
        guard let userKey = key else { throw BitwardenCrypto.CryptoError.invalidEncString }

        self.client = client
        self.accessToken = token.accessToken
        self.refreshToken = token.refreshToken
        self.userKey = userKey
        self.kdf = kdf

        let acct = VaultSessionStoredAccount(endpoint: endpoint, email: email, kdf: kdf.kdf, iterations: kdf.iterations)
        try keychain.set(JSONEncoder().encode(acct), account: Self.acctAccount)
        if let rt = token.refreshToken {
            try keychain.set(Data(rt.utf8), account: Self.acctRefreshToken)
        }
        try? keychain.setProtected(userKey.raw, account: Self.acctUserKey)
    }

    /// 메모리 키 폐기 (Keychain 항목은 유지 → Touch ID 잠금해제 가능).
    public func lock() {
        userKey = nil
        accessToken = nil
    }

    /// 마스터 패스워드로 잠금해제 (재로그인과 동일 흐름).
    public func unlock(password: String, twoFactor: (code: String, provider: Int, remember: Bool)? = nil) async throws {
        guard let acct = storedAccount() else { throw SessionError.noAccount }
        try await login(endpoint: acct.endpoint, email: acct.email, password: password, twoFactor: twoFactor)
    }

    /// Touch ID 잠금해제: Keychain 생체 보호 항목에서 userKey 복원.
    public func unlockWithBiometrics() async throws {
        try await unlockFromStoredKey(requireUserPresence: true)
    }

    /// 저장된 userKey 로 잠금해제.
    /// - `requireUserPresence: false` — GUI 가 이미 unlocked 일 때 CLI/에이전트용 (Touch ID 스킵).
    /// - `true` — Touch ID/기기 암호 프롬프트.
    public func unlockFromStoredKey(requireUserPresence: Bool = true) async throws {
        guard let acct = storedAccount() else { throw SessionError.noAccount }
        guard let raw = try await keychain.getProtected(
            account: Self.acctUserKey,
            prompt: "Vaultwarden Client 잠금 해제",
            requireUserPresence: requireUserPresence
        ),
              let key = BitwardenCrypto.SymmetricKeySet(raw: raw) else {
            throw SessionError.noStoredKey
        }
        self.userKey = key
        self.client = VaultwardenAPI(endpoint: acct.endpoint)
        try await ensureAccessToken()
    }

    /// dual-entry 공통 진입 순서:
    /// 1) 이미 메모리 unlocked
    /// 2) GUI 세션 브로커(소켓) — **정본** (Touch ID 없음, 프로세스가 달라도 세션 공유)
    /// 3) state mirror unlocked + 키체인 silent 로드 (브로커 없는 폴백)
    /// 4) Touch ID
    public func unlockPreferringGUISession(
        requestingApp: String = "vaultwarden-client-cli"
    ) async throws {
        if isUnlocked { return }
        if await unlockViaSessionBroker(requestingApp: requestingApp) {
            return
        }
        if VaultClientSessionGate.isGUIUnlocked() {
            try await unlockFromStoredKey(requireUserPresence: false)
            return
        }
        try await unlockFromStoredKey(requireUserPresence: true)
    }

    /// 현재 메모리 세션을 dual-entry 로 이관할 재료. locked 면 nil.
    public func exportUnlockedSession() -> VaultSessionMaterial? {
        guard let userKey, let acct = storedAccount() else { return nil }
        let rt = refreshToken
            ?? keychain.get(account: Self.acctRefreshToken).map { String(decoding: $0, as: UTF8.self) }
        return VaultSessionMaterial(
            userKeyRaw: userKey.raw,
            accessToken: accessToken,
            refreshToken: rt,
            endpoint: acct.endpoint,
            email: acct.email,
            kdf: acct.kdf,
            iterations: acct.iterations
        )
    }

    /// 브로커/다른 프로세스가 넘겨 준 세션으로 메모리 unlock (LA 없음).
    public func importUnlockedSession(_ material: VaultSessionMaterial) async throws {
        guard let key = BitwardenCrypto.SymmetricKeySet(raw: material.userKeyRaw) else {
            throw SessionError.noStoredKey
        }
        self.userKey = key
        self.client = VaultwardenAPI(endpoint: material.endpoint)
        self.accessToken = material.accessToken
        self.refreshToken = material.refreshToken
        self.kdf = BitwardenCrypto.KdfConfig(kdf: material.kdf, iterations: material.iterations)
        // broker에서 받은 토큰은 만료됐을 수 있으므로 항상 refresh 시도
        self.accessToken = nil
        try await ensureAccessToken()
    }

    func unlockViaSessionBroker(requestingApp: String) async -> Bool {
        #if os(macOS)
        do {
            let material = try await VaultSessionBrokerClient()
                .fetchSession(requestingApp: requestingApp)
            try await importUnlockedSession(material)
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }

    /// 로그아웃: 모든 저장 상태 삭제.
    public func logout() {
        lock()
        refreshToken = nil
        client = nil
        keychain.delete(account: Self.acctAccount)
        keychain.delete(account: Self.acctRefreshToken)
        keychain.delete(account: Self.acctUserKey)
    }

    func requireUnlocked() throws -> (VaultwardenAPI, String, BitwardenCrypto.SymmetricKeySet) {
        guard let client, let accessToken, let userKey else { throw SessionError.notUnlocked }
        return (client, accessToken, userKey)
    }

    func ensureAccessToken() async throws {
        guard accessToken == nil else { return }
        guard let client else { throw SessionError.noAccount }
        let stored = refreshToken
            ?? keychain.get(account: Self.acctRefreshToken).map { String(decoding: $0, as: UTF8.self) }
        guard let rt = stored else { throw SessionError.noStoredKey }
        let token = try await client.refresh(refreshToken: rt)
        accessToken = token.accessToken
        if let newRT = token.refreshToken {
            refreshToken = newRT
            try? keychain.set(Data(newRT.utf8), account: Self.acctRefreshToken)
        }
    }

    func deviceIdentifier() -> String {
        let acct = "deviceIdentifier"
        if let d = keychain.get(account: acct), let s = String(data: d, encoding: .utf8) { return s }
        let id = UUID().uuidString.lowercased()
        try? keychain.set(Data(id.utf8), account: acct)
        return id
    }
}
