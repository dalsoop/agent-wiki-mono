import CommandKit
import Foundation
import os
import StateRootKit

/// 세션을 Secure Enclave 키(age-plugin-se, 이 맥의 macbook 주체)로 암호화한 파일에 둔다 — 결정 7(2026-09-30):
/// 사람 스태프 세션(갱신 토큰 포함)은 Keychain 에 두지 않는다. core 스태프 계약 v1 §7.
///
/// - 자리: 상태 루트 `.gujo-auth/sessions/<account>.json.age`, 폴더 0700·파일 0600. 평문은 디스크에 쓰지 않는다.
/// - 암호화: `age -a -r <recipient>`(ASCII armor — 프로세스 출력은 텍스트로만 안전하게 받는다)(recipient 는 식별자 파일의 `# public key:` 줄), 복호화: `age -d -i <식별자>`.
///   식별자는 `GUJO_AUTH_AGE_IDENTITY`, 없으면 `SOPS_AGE_KEY_FILE`, 없으면 `~/.config/sops/age/macbook-se.txt`.
/// - 이관: 파일이 없고 옛 Keychain 항목(`net.ranode.gujo`)이 있으면 파일로 옮긴 뒤 Keychain 항목을 지운다.
/// - 파일이 바뀌지 않으면(수정 시각) 다시 복호화하지 않는다.
public final class SecureEnclaveFileSessionStore: GujoSessionStore, Sendable {
    public static let relativeDirectory = ".gujo-auth/sessions"
    public static let identityEnvironmentKey = "GUJO_AUTH_AGE_IDENTITY"
    public static let defaultIdentityRelativePath = ".config/sops/age/macbook-se.txt"

    public typealias Cipher = @Sendable (_ arguments: [String], _ input: Data) -> Data?

    let directory: URL
    let identityFile: String
    let legacy: (any GujoSessionStore)?
    let cipher: Cipher
    private let cache = OSAllocatedUnfairLock<[String: (modified: Date, data: Data)]>(initialState: [:])

    public init(
        directory: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: String = NSHomeDirectory(),
        legacy: (any GujoSessionStore)? = KeychainSessionStore(),
        cipher: @escaping Cipher = SecureEnclaveFileSessionStore.age
    ) {
        self.directory = directory ?? StateRootKit.url(Self.relativeDirectory, environment: environment, homeDirectory: home)
        let configured = [environment[Self.identityEnvironmentKey], environment["SOPS_AGE_KEY_FILE"]]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        self.identityFile = configured ?? (home as NSString).appendingPathComponent(Self.defaultIdentityRelativePath)
        self.legacy = legacy
        self.cipher = cipher
    }

    func file(for account: String) -> URL {
        directory.appendingPathComponent("\(account).json.age")
    }

    /// 식별자 파일의 `# public key: age1…` 줄.
    func recipient() -> String? {
        guard let raw = FileManager.default.contents(atPath: identityFile) else { return nil }
        let text = String(decoding: raw, as: UTF8.self)
        for line in text.split(separator: "\n") where line.hasPrefix("# public key: ") {
            let value = line.dropFirst("# public key: ".count).trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("age1") { return value }
        }
        return nil
    }

    public func data(account: String) -> Data? {
        let url = file(for: account)
        guard let modified = Self.modified(url) else { return migrateFromLegacy(account: account) }
        if let hit = cache.withLock({ $0[account] }), hit.modified == modified { return hit.data }
        guard let sealed = FileManager.default.contents(atPath: url.path),
              let plain = cipher(["-d", "-i", identityFile], sealed)
        else { return nil }
        cache.withLock { $0[account] = (modified, plain) }
        return plain
    }

    @discardableResult
    public func setData(_ value: Data, account: String) -> Bool {
        guard let recipient = recipient(), let sealed = cipher(["-a", "-r", recipient], value) else { return false }
        let url = file(for: account)
        // 실패는 false 로 알린다 — 호출한 쪽(로그인)은 저장되지 않은 세션을 다시 요구한다.
        guard case .success = Result(catching: { try write(sealed, to: url, account: account) }) else { return false }
        if let modified = Self.modified(url) { cache.withLock { $0[account] = (modified, value) } }
        return true
    }

    private func write(_ sealed: Data, to url: URL, account: String) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let temporary = directory.appendingPathComponent(".\(account).\(UUID().uuidString).tmp")
        guard manager.createFile(atPath: temporary.path, contents: sealed, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        if manager.fileExists(atPath: url.path) {
            _ = try manager.replaceItemAt(url, withItemAt: temporary)
        } else {
            try manager.moveItem(at: temporary, to: url)
        }
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func delete(account: String) {
        cache.withLock { _ = $0.removeValue(forKey: account) }
        // 없는 파일이면 unlink 가 실패할 뿐이다. 옛 Keychain 항목도 함께 지운다.
        _ = unlink(file(for: account).path)
        legacy?.delete(account: account)
    }

    /// 옛 Keychain 항목을 파일로 옮기고 Keychain 에서 지운다. 옮기지 못하면 Keychain 은 그대로 두고 값을 돌려준다.
    func migrateFromLegacy(account: String) -> Data? {
        guard let legacy, let old = legacy.data(account: account) else { return nil }
        if setData(old, account: account) { legacy.delete(account: account) }
        return old
    }

    static func modified(_ url: URL) -> Date? {
        var info = stat()
        guard stat(url.path, &info) == 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec) + TimeInterval(info.st_mtimespec.tv_nsec) / 1e9)
    }

    /// `age` 를 stdin·stdout 파이프로만 부른다. 평문은 파일로 가지 않는다. PATH 에 age-plugin-se 가 있어야 한다.
    public static let age: Cipher = { arguments, input in
        var environment = ProcessInfo.processInfo.environment
        let path = environment["PATH"] ?? "/usr/bin:/bin"
        environment["PATH"] = (HostPlatformPaths.standardBinPaths + [path]).joined(separator: ":")
        let result = SafeProcessRunner.runSync(
            executable: HostPlatformPaths.homebrewBin + "/age", arguments: arguments,
            environment: environment, input: input, timeout: 30)
        guard result.exitCode == 0 else { return nil }
        return result.stdoutData
    }
}
