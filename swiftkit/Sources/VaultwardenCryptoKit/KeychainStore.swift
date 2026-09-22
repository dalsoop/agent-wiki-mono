import Foundation
import Security
import LocalAuthentication

/// 앱 전용 Keychain 저장소.
/// - 일반 항목: refresh token 등
/// - 생체 보호 항목: 사용자 대칭키(잠금해제용) — 읽을 때 Touch ID/암호 요구
public struct KeychainStore: Sendable {
    public let service: String

    public init(service: String = "com.dalsoop.wardenbar") {
        self.service = service
    }

    public enum KeychainError: Error, LocalizedError {
        case status(OSStatus)
        public var errorDescription: String? {
            switch self {
            case .status(let s):
                if s == errSecUserCanceled { return "사용자가 인증을 취소했습니다" }
                return "Keychain 오류 (\(s))"
            }
        }
    }

    // MARK: - 일반 항목

    public func set(_ data: Data, account: String) throws {
        var query = baseQuery(account: account)
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let s = SecItemAdd(query as CFDictionary, nil)
        guard s == errSecSuccess else {
            throw KeychainError.status(addStatus(s, updatingInstead: account, data: data))
        }
    }

    /// 재설치로 바이너리(cdhash)가 바뀌면 옛 항목의 ACL 이 옛 바이너리만 신뢰해
    /// `SecItemDelete` 가 몰래 실패하고, 이어지는 `SecItemAdd` 가 `errSecDuplicateItem`
    /// 로 죽는다(2026-08-23 실측 — "Keychain 오류 (-25299)" 재로그인 막다길).
    /// 이 시점에는 `SecItemUpdate` 로 폴백한다 — Security Agent 가 승인 프롬프트를
    /// 띄우고 사용자가 한 번 승인하면 항목과 ACL 이 함께 갱신돼 재로그인만으로
    /// 자가치유된다. 그 외 실패 상태는 그대로 돌려준다.
    public static func shouldFallbackToUpdate(_ status: OSStatus) -> Bool {
        status == errSecDuplicateItem
    }

    func addStatus(_ status: OSStatus, updatingInstead account: String, data: Data) -> OSStatus {
        guard Self.shouldFallbackToUpdate(status) else { return status }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        return SecItemUpdate(baseQuery(account: account) as CFDictionary, attributes as CFDictionary)
    }

    public func get(account: String) -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    public func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }

    // MARK: - 생체 보호 항목

    /// 잠금해제용 userKey 저장. Developer ID(비-App Store) 앱은 SecAccessControl 생체 키체인이
    /// keychain-access-groups entitlement + provisioning profile 을 요구해 -34018 로 막히고,
    /// 그 entitlement 를 붙이면 프로파일 없이는 앱 실행 자체가 거부된다(실측). 그래서 키는
    /// 일반 login 키체인(this-device-only, at-rest 암호화)에 두고, 읽기 전에 getProtected 가
    /// LAContext 로 Touch ID/암호를 요구한다(앱 레벨 게이트). 하드웨어 바인딩은 아니지만
    /// login 키체인 밖으로 키가 나가지 않고, 편의 잠금해제로는 표준적인 절충이다.
    public func setProtected(_ data: Data, account: String) throws {
        delete(account: account)
        var query = baseQuery(account: account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let s = SecItemAdd(query as CFDictionary, nil)
        guard s == errSecSuccess else {
            throw KeychainError.status(addStatus(s, updatingInstead: account, data: data))
        }
    }

    /// Touch ID/기기 암호로 사용자 확인 후 userKey 를 반환. 인증 실패/취소 시 throw,
    /// 저장된 항목이 없으면(첫 로그인 전) 프롬프트 없이 nil.
    ///
    /// - Parameter requireUserPresence: false 이면 LA 프롬프트 없이 키만 읽는다.
    ///   GUI 가 이미 unlocked 인 dual-entry CLI 경로용. (키 자체는 SecAccessControl 이 아니라
    ///   앱 레벨 게이트이므로, GUI 잠금 상태와 맞추는 게 정본.)
    ///
    /// async/await 로 구현 — 세마포어로 호출 스레드(actor executor)를 막으면
    /// LAContext 콜백과 데드락 나 지문 프롬프트가 떠도 진행이 안 된다(실측 버그).
    public func getProtected(
        account: String,
        prompt: String,
        requireUserPresence: Bool = true
    ) async throws -> Data? {
        guard get(account: account) != nil else { return nil }
        if requireUserPresence {
            let context = LAContext()
            // 직전 생체 성공 재사용 — 같은 세션 안 연속 호출 완화
            context.touchIDAuthenticationAllowableReuseDuration =
                LATouchIDAuthenticationMaximumAllowableReuseDuration
            context.localizedCancelTitle = "취소"
            // 생체만 우선 — 기기 암호 시트로 확 넘어가며 포커스가 튀는 경로를 줄인다.
            // 생체 불가 기기에서만 deviceOwnerAuthentication(암호) 폴백.
            var authError: NSError?
            let policy: LAPolicy
            if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) {
                policy = .deviceOwnerAuthenticationWithBiometrics
            } else if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) {
                policy = .deviceOwnerAuthentication
            } else {
                throw KeychainError.status(errSecAuthFailed)
            }
            let result: (ok: Bool, err: Error?) = await withCheckedContinuation { cont in
                context.evaluatePolicy(policy, localizedReason: prompt) { success, err in
                    cont.resume(returning: (success, err))
                }
            }
            if !result.ok {
                // 취소류(사용자·시스템·앱 취소)는 errSecUserCanceled 로 — 호출부가 조용히 비밀번호 폴백.
                if let la = result.err as? LAError,
                   [.userCancel, .systemCancel, .appCancel].contains(la.code) {
                    throw KeychainError.status(errSecUserCanceled)
                }
                throw KeychainError.status(errSecAuthFailed)
            }
        }
        return get(account: account)
    }

    private func baseQuery(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    // MARK: - 진단(keychain-doctor)

    /// 항목 하나의 단계별 판정 — 비밀값은 출력하지 않고 OSStatus 만 낸다.
    /// 재설치 후 "재로그인도 막히는" ACL 고착을 화면 없이 잡는 관측 지점이다.
    public struct KeychainProbe: Codable, Sendable {
        public let account: String
        /// 속성 조회(값 미반환). 0=조회됨, -25300=항목 없음.
        public let find: Int
        /// 비밀값 읽기(읽고 즉시 폐기 — 잠금해제·재로그인이 실제로 걸리는 경로).
        /// ACL 이 이 바이너리를 거부하면 -25293, 승인 프롬프트를 띄우거나 실패한다.
        public let readData: Int
        /// 무해한 속성(comment) 갱신 — 속성 축 쓰기 권한. 데이터 축과 결론이 다를 수 있다
        /// (2026-08-23 실측: comment 갱신은 0 이어도 데이터 쓰기가 -25293).
        public let updateAttribute: Int
    }

    /// 진단 probe — 비밀값을 한 번 읽어(메모리에서 즉시 폐기, 출력 없음) 데이터 경로의
    /// ACL 판정까지 내고, comment 속성에 도장만 찍는다(비밀값 불변).
    /// 쓰기 권한이 없으면 Security Agent 승인 프롬프트가 뜨거나 실패 상태가 돌아온다.
    public func probe(account: String) -> KeychainProbe {
        var out: CFTypeRef?
        let find = SecItemCopyMatching(baseQuery(account: account) as CFDictionary, &out)
        var readQuery = baseQuery(account: account)
        readQuery[kSecReturnData as String] = true
        readQuery[kSecMatchLimit as String] = kSecMatchLimitOne
        var dataOut: CFTypeRef?
        let read = SecItemCopyMatching(readQuery as CFDictionary, &dataOut)
        let update = SecItemUpdate(
            baseQuery(account: account) as CFDictionary,
            [kSecAttrComment as String: "vaultwarden-client keychain-doctor probe"] as CFDictionary
        )
        return KeychainProbe(account: account, find: Int(find), readData: Int(read), updateAttribute: Int(update))
    }
}
