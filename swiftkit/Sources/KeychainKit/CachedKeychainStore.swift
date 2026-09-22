#if canImport(Security)
import Foundation
import LocalAuthentication
import os
import Security

/// 캐시된 Keychain 저장소 — 앱 공용 SSOT.
///
/// 근본 문제: raw `SecItemCopyMatching` 은 securityd 시스템콜이라 느린데, SwiftUI `body` 처럼
/// 자주·요소마다 재평가되는 경로에서 이를 캐시 없이 반복하면 앱 전체가 버벅인다(실측:
/// agent-request, agent-vault). 이 저장소는 읽기를 **인메모리 메모이즈**(첫 1회만
/// Keychain 조회)하고 쓰기/삭제 때 무효화한다 — 그래서 render 경로에서 불려도 비용이 0 에 수렴한다.
///
/// **thread-safety**: `OSAllocatedUnfairLock` 으로 캐시 읽기·쓰기를 직렬화한다. static 메서드(실제 Keychain
/// 호출)는 잠금을 안 잡지만 GCD worker thread 에서 불려도 안전하게 설계됐다(SecItem API 자체가
/// thread-safe). 쓰기 시 `kSecAttrAccess` 를 붙일 때 신뢰할 바이너리 경로 목록.
/// `nil` 경로 항목은 "현재 프로세스"(SecTrustedApplicationCreateFromPath(nil)).
/// 기본(nil) 은 플랫폼 기본 ACL — 관제 dual-entry(GUI+Helpers) 만 명시 ACL 을 켠다.
public struct KeychainTrustedAccess: Sendable, Equatable {
    public var label: String
    /// 절대 경로. 빈 배열이면 현재 프로세스만 신뢰.
    public var applicationPaths: [String]

    public init(label: String, applicationPaths: [String] = []) {
        self.label = label
        self.applicationPaths = applicationPaths
    }

    /// GUI 앱 번들 + Helpers CLI 를 함께 신뢰 (agent-vault dual-entry).
    public static func dualEntryControlPlane(
        appBundlePath: String,
        helperCLIPath: String,
        label: String = "AgentVault control plane"
    ) -> KeychainTrustedAccess {
        var paths: [String] = []
        let macOS = (appBundlePath as NSString).appendingPathComponent("Contents/MacOS")
        let execName: String?
        do {
            execName = try FileManager.default.contentsOfDirectory(atPath: macOS).first { name in
                !name.hasPrefix(".")
            }
        } catch {
            // 번들 MacOS 를 못 열면 GUI 실행 파일을 신뢰 목록에 못 넣는다 — Helpers 만.
            execName = nil
        }
        if let execName {
            paths.append((macOS as NSString).appendingPathComponent(execName))
        }
        if FileManager.default.isExecutableFile(atPath: helperCLIPath) {
            paths.append(helperCLIPath)
        }
        return KeychainTrustedAccess(label: label, applicationPaths: paths)
    }
}

public final class CachedKeychainStore: Sendable {
    private struct Memory: Sendable {
        /// `nil` value = "Keychain 에 존재하지 않음"을 명시. key 자체가 없으면 "아직 안 읽음".
        var cache: [String: Data?] = [:]
        var lastReadTimedOut = false
    }

    private let service: String
    /// SecItem 접근성 상수. `CFString` 은 Sendable 이 아니라 문자열로 보관한다.
    private let accessibleRaw: String
    private let trustedAccess: KeychainTrustedAccess?
    private let memory = OSAllocatedUnfairLock(initialState: Memory())

    /// timeout 을 두면 느린 Keychain 조회가 앱 기동을 먹지 않는다.
    private let readTimeout: TimeInterval

    /// 가장 최근 `data(account:)` 호출이 Keychain 타임아웃으로 끝났는지.
    /// LicenseKit(LocalLicenseWallet) 처럼 "지갑이 비어서 그런지 조회가 안 돼서 그런지"를
    /// UI에서 구분해야 하는 소비자가 있다 — 빈 캐시(nil)만으로는 그 둘을 구별할 수 없다.
    public var lastReadTimedOut: Bool {
        memory.withLock { $0.lastReadTimedOut }
    }

    public init(
        service: String,
        accessible: CFString = kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        readTimeout: TimeInterval = 2.0,
        trustedAccess: KeychainTrustedAccess? = nil
    ) {
        self.service = service
        self.accessibleRaw = accessible as String
        self.readTimeout = readTimeout
        self.trustedAccess = trustedAccess
    }

    // MARK: 읽기 (캐시 우선)

    public func data(account: String) -> Data? {
        if let cached: Data? = memory.withLock({ state -> Data?? in
            guard let index = state.cache.index(forKey: account) else { return nil }
            state.lastReadTimedOut = false
            return .some(state.cache[index].value)
        }) {
            return cached
        }

        let result = KeychainItemIO.read(service: service, account: account, timeout: readTimeout)
        return memory.withLock { state in
            // 타임아웃으로 값을 못 얻은 경우 "없음"으로 캐시하면 안 된다 —
            // 지갑/게이트가 재시도 없이 빈 목록으로 고착된다.
            if result.timedOut, result.data == nil {
                state.lastReadTimedOut = true
                return nil
            }
            state.cache[account] = result.data
            state.lastReadTimedOut = false
            return result.data
        }
    }

    public func string(account: String) -> String? {
        data(account: account).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// 값 존재 여부 — 목록 UI 가 "이 항목에 비밀값이 있나"를 렌더마다 물어도 캐시로 답한다.
    public func has(account: String) -> Bool { data(account: account) != nil }

    /// 이 service 아래 account 이름 목록 (`kSecMatchLimitAll` + attributes only).
    /// 비밀값은 반환하지 않는다. 캐시하지 않음.
    public func listAccounts() -> [String] {
        KeychainItemIO.listAccounts(service: service, timeout: readTimeout)
    }

    // MARK: 쓰기 (캐시 무효화 = 새 값으로 갱신)

    @discardableResult
    public func set(_ value: String, account: String) -> Bool {
        setData(Data(value.utf8), account: account)
    }

    /// 성공 시에만 캐시를 갱신한다. SecItem 실패를 조용히 캐시에 넣으면 가짜 hasValue 가 된다.
    @discardableResult
    public func setData(_ value: Data, account: String) -> Bool {
        let ok = KeychainItemIO.write(
            service: service,
            account: account,
            value: value,
            accessible: accessibleRaw as CFString,
            trustedAccess: trustedAccess)
        _ = memory.withLock { state in
            if ok {
                state.cache.updateValue(value, forKey: account)
            } else {
                state.cache.removeValue(forKey: account)
            }
        }
        return ok
    }

    public func delete(account: String) {
        KeychainItemIO.remove(service: service, account: account)
        _ = memory.withLock { state in
            state.cache.updateValue(nil, forKey: account)
        }
    }

    /// 외부에서 Keychain 이 바뀌었을 수 있을 때 캐시를 비운다(다음 읽기에서 재조회).
    public func invalidate() {
        _ = memory.withLock { $0.cache.removeAll() }
    }

    public func invalidate(account: String) {
        _ = memory.withLock { $0.cache.removeValue(forKey: account) }
    }
}

/// SecItem 접근 — `CachedKeychainStore` 본체와 분리해 type-body-length 를 지킨다.
enum KeychainItemIO {
    static func base(service: String, account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    struct ReadResult {
        var data: Data?
        var timedOut: Bool
    }

    /// Keychain 읽기.
    ///
    /// **동기 `SecItemCopyMatching`** 을 쓴다. 예전 구현은 `DispatchQueue.global().async` +
    /// `DispatchSemaphore.wait(timeout:)` 이었는데, securityd 가 바쁘거나 cold 일 때
    /// 실제 조회는 수 초 걸리거나(실측 5s+), 같은 concurrent 큐 대기와 겹치면 **항상 타임아웃**
    /// 으로 떨어져 지갑/게이트가 "키 없음"으로 오진했다. 복구 안내가 `reset-corrupt`(전체 삭제)
    /// 라서 타임아웃 오탐 → 키 전량 유실 사고가 난다.
    ///
    /// `timeout > 0` 이면 백그라운드에서 동기 조회 후 상한만 건다(호출 스레드 블로킹 방지용).
    /// `timeout <= 0` 이면 호출 스레드에서 그대로 조회(테스트·짧은 경로).
    /// UI 본문 경로 비용은 상위 캐시가 막는다 — 여기 timeout 이 1차 방어선이 아니다.
    static func read(service: String, account: String, timeout: TimeInterval) -> ReadResult {
        if timeout <= 0 {
            return ReadResult(data: copyMatching(service: service, account: account), timedOut: false)
        }

        let box = OSAllocatedUnfairLock<Data?>(initialState: nil)
        let sem = DispatchSemaphore(value: 0)
        // 전용 큐 — concurrent global 풀 고갈 시 async 작업이 영원히 스케줄 안 되는 함정을 피한다.
        DispatchQueue(label: "keychainkit.read.\(service)", qos: .userInitiated).async {
            let data = copyMatching(service: service, account: account)
            _ = box.withLock { $0 = data }
            sem.signal()
        }
        let timedOut = sem.wait(timeout: .now() + timeout) == .timedOut
        let data = box.withLock { $0 }
        // 타임아웃이어도 직후 도착한 값은 살린다(오탐 완화). 못 기다린 경우만 timedOut=true.
        if timedOut, data == nil {
            return ReadResult(data: nil, timedOut: true)
        }
        return ReadResult(data: data, timedOut: false)
    }

    static func copyMatching(service: String, account: String) -> Data? {
        var query = base(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        #if canImport(LocalAuthentication)
        // 잠금 화면·Touch ID 프롬프트를 띄우지 않는다(에이전트/CLI headless).
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        #endif
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    /// true = Keychain 반영 성공.
    static func write(
        service: String,
        account: String,
        value: Data,
        accessible: CFString,
        trustedAccess: KeychainTrustedAccess?
    ) -> Bool {
        var query = base(service: service, account: account)
        let update: [String: Any] = [
            kSecValueData as String: value,
            kSecAttrAccessible as String: accessible,
        ]
        // SecItemUpdate 는 Access 변경이 까다로워 값만 갱신. 신규 Add 에만 ACL 부착.
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        query.merge(update) { _, new in new }
        #if os(macOS)
        if let access = makeAccess(trustedAccess) {
            query[kSecAttrAccess as String] = access
        }
        #endif
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        if addStatus == errSecSuccess { return true }
        #if os(macOS)
        if trustedAccess != nil {
            query.removeValue(forKey: kSecAttrAccess as String)
            return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
        }
        #endif
        return false
    }

    /// 관제 바이너리 신뢰 SecAccess. **항상 현재 프로세스**를 포함해 writer=reader 가 되게 한다.
    #if os(macOS)
    static func makeAccess(_ policy: KeychainTrustedAccess?) -> SecAccess? {
        guard let policy else { return nil }
        var trustedApps: [SecTrustedApplication] = []
        var current: SecTrustedApplication?
        if SecTrustedApplicationCreateFromPath(nil, &current) == errSecSuccess,
           let current {
            trustedApps.append(current)
        }
        for path in policy.applicationPaths {
            var app: SecTrustedApplication?
            let st = path.withCString { SecTrustedApplicationCreateFromPath($0, &app) }
            if st == errSecSuccess, let app {
                trustedApps.append(app)
            }
        }
        guard !trustedApps.isEmpty else { return nil }
        var access: SecAccess?
        let status = SecAccessCreate(
            policy.label as CFString,
            trustedApps as CFArray,
            &access)
        guard status == errSecSuccess else { return nil }
        return access
    }
    #endif

    static func remove(service: String, account: String) {
        let query = base(service: service, account: account)
        SecItemDelete(query as CFDictionary)
    }

    static func listAccountsNow(service: String) -> [String] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        #if canImport(LocalAuthentication)
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        #endif
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let rows = item as? [[String: Any]] else { return [] }
        return rows.compactMap { $0[kSecAttrAccount as String] as? String }.sorted()
    }

    static func listAccounts(service: String, timeout: TimeInterval) -> [String] {
        if timeout <= 0 { return listAccountsNow(service: service) }
        let box = OSAllocatedUnfairLock<[String]>(initialState: [])
        let sem = DispatchSemaphore(value: 0)
        DispatchQueue(label: "keychainkit.list.\(service)", qos: .userInitiated).async {
            let accounts = listAccountsNow(service: service)
            _ = box.withLock { $0 = accounts }
            sem.signal()
        }
        if sem.wait(timeout: .now() + timeout) == .timedOut { return [] }
        return box.withLock { $0 }
    }
}

#else
// Linux/non-Apple stub — KeychainKit compiles but provides no functionality.
// Use SharedFileTokenStore instead.
import Foundation

public struct KeychainTrustedAccess: Sendable, Equatable {
    public var label: String
    public var applicationPaths: [String]
    public init(label: String, applicationPaths: [String] = []) {
        self.label = label
        self.applicationPaths = applicationPaths
    }
    public static func dualEntryControlPlane(
        appBundlePath: String,
        helperCLIPath: String,
        label: String = "AgentVault control plane"
    ) -> KeychainTrustedAccess {
        KeychainTrustedAccess(label: label, applicationPaths: [helperCLIPath].filter { !$0.isEmpty })
    }
}

public final class CachedKeychainStore: Sendable {
    public var lastReadTimedOut: Bool { false }
    public init(
        service: String,
        accessible: Any? = nil,
        readTimeout: TimeInterval = 2.0,
        trustedAccess: KeychainTrustedAccess? = nil
    ) {}
    public func data(account: String) -> Data? { nil }
    public func string(account: String) -> String? { nil }
    public func has(account: String) -> Bool { false }
    public func listAccounts() -> [String] { [] }
    @discardableResult public func set(_ value: String, account: String) -> Bool { false }
    @discardableResult public func setData(_ value: Data, account: String) -> Bool { false }
    public func delete(account: String) {}
    public func invalidate() {}
    public func invalidate(account: String) {}
}
#endif
