import CommandKit
import CryptoKit
import Foundation
import os
import StateRootKit

/// 기계 주체 토큰의 출처(계약 v1 §6). 사람 로그인 세션보다 먼저 본다.
public protocol MachineStaffTokenSource: Sendable {
    /// `gst_` 토큰. 없거나 읽지 못하면 nil(오류가 아니다 — 그러면 사람 로그인 세션을 쓴다).
    func machineToken() -> String?
}

/// principal-secrets-mono 의 sops 암호문 `value` 를 `sops decrypt` 로 읽는다. 원문은 메모리에만 두고
/// 파일·Keychain·로그에 쓰지 않는다. 암호문 파일이 바뀌지 않으면(수정 시각) 다시 복호화하지 않는다 — 자동
/// 로테이션이 파일을 바꾸면 오래 도는 앱도 다음 호출에서 새 토큰을 읽는다.
///
/// - 경로: 환경 변수 `GUJO_STAFF_TOKEN_SOPS_FILE`(암호문 경로일 뿐 토큰이 아니다). 없으면 두 후보 중 있는 것 가운데
///   가장 최근에 바뀐 것: environment-secret-broker 의 전용 클론(자동 로테이션이 쓰는 곳, 상태 루트
///   `.environment-secret-broker/principal-secrets-mono`)과 사람이 쓰는 작업 사본(`~/Documents/…/principal-secrets-mono/main`).
/// - 식별자: `SOPS_AGE_KEY_FILE`, 없으면 `~/.config/sops/age/macbook-se.txt`.
public final class SopsMachineStaffToken: MachineStaffTokenSource, Sendable {
    public static let pathEnvironmentKey = "GUJO_STAFF_TOKEN_SOPS_FILE"
    public static let ageKeyEnvironmentKey = "SOPS_AGE_KEY_FILE"
    /// 저장소 안 경로.
    public static let secretPath = "secrets/macbook-tools/gujo-staff-agent.enc.yaml"
    public static let defaultRelativePath = "Documents/WORK/WORKSPACE/infra/principal-secrets-mono/main/" + secretPath
    /// environment-secret-broker 가 로테이션에 쓰는 전용 클론(상태 루트 기준).
    public static let managedCloneRelativePath = ".environment-secret-broker/principal-secrets-mono"
    public static let defaultAgeKeyRelativePath = ".config/sops/age/macbook-se.txt"

    public typealias Decrypt = @Sendable (_ file: String, _ ageKeyFile: String) -> String?

    private let candidates: [String]
    private let ageKeyFile: String
    private let decrypt: Decrypt
    private struct Cached: Sendable {
        let file: String?
        let modified: Date?
        let token: String?
    }

    /// 마지막 복호화 결과와 그때의 파일 수정 시각(없음도 결과다). nil 이면 아직 읽지 않았다.
    private let cache = OSAllocatedUnfairLock<Cached?>(initialState: nil)

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: String = NSHomeDirectory(),
        decrypt: @escaping Decrypt = SopsMachineStaffToken.sopsDecrypt
    ) {
        let configured = environment[Self.pathEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if configured.isEmpty {
            let clone = StateRootKit.url(Self.managedCloneRelativePath, environment: environment, homeDirectory: home)
                .appendingPathComponent(Self.secretPath).path
            self.candidates = [clone, (home as NSString).appendingPathComponent(Self.defaultRelativePath)]
        } else {
            self.candidates = [configured]
        }
        let ageKey = environment[Self.ageKeyEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.ageKeyFile = ageKey.isEmpty ? (home as NSString).appendingPathComponent(Self.defaultAgeKeyRelativePath) : ageKey
        self.decrypt = decrypt
    }

    /// 지금 읽을 암호문 경로(원문 없음). 후보가 하나도 없으면 첫 후보. doctor 출력용.
    public var path: String { current().file ?? candidates[0] }

    /// 있는 후보 가운데 가장 최근에 바뀐 파일과 그 수정 시각. 없는 후보는 건너뛴다(오류가 아니다).
    private func current() -> (file: String?, modified: Date?) {
        var best: (file: String?, modified: Date?) = (nil, nil)
        for candidate in candidates {
            var info = stat()
            guard stat(candidate, &info) == 0 else { continue }
            let modified = Date(
                timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec) + TimeInterval(info.st_mtimespec.tv_nsec) / 1e9)
            if best.modified == nil || modified > (best.modified ?? .distantPast) { best = (candidate, modified) }
        }
        return best
    }

    public func machineToken() -> String? {
        let (file, modified) = current()
        return cache.withLock { cached in
            if let cached, cached.file == file, cached.modified == modified { return cached.token }
            let token = file.map { Self.normalized(decrypt($0, ageKeyFile)) } ?? nil
            cached = Cached(file: file, modified: modified, token: token)
            return token
        }
    }

    static func normalized(_ raw: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.hasPrefix(GujoStaffAuth.tokenPrefix)
        else { return nil }
        return value
    }

    /// `sops decrypt --extract '["value"]' <file>` — 출력은 파이프로만 받는다.
    public static let sopsDecrypt: Decrypt = { file, ageKeyFile in
        var environment = ProcessInfo.processInfo.environment
        environment[ageKeyEnvironmentKey] = ageKeyFile
        let path = environment["PATH"] ?? "/usr/bin:/bin"
        environment["PATH"] = (HostPlatformPaths.standardBinPaths + [path]).joined(separator: ":")
        let result = SafeProcessRunner.runSync(
            executable: "/usr/bin/env",
            arguments: ["sops", "decrypt", "--extract", "[\"value\"]", file],
            environment: environment,
            timeout: 30)
        guard result.exitCode == 0 else { return nil }
        return result.stdout
    }
}

/// 기계 주체 토큰 없음 — 테스트와 "사람 로그인만" 정책 앱용.
public struct NoMachineStaffToken: MachineStaffTokenSource {
    public init() {}
    public func machineToken() -> String? { nil }
}

/// 고정 토큰 — 테스트용. 실제 앱에서 토큰 리터럴을 이 타입에 박지 말 것.
public struct StaticMachineStaffToken: MachineStaffTokenSource {
    private let token: String?
    public init(_ token: String?) { self.token = token }
    public func machineToken() -> String? { token }
}

/// 로테이션 결과(계약 §6). 토큰 원문은 메모리에만 있고, 호출한 쪽이 곧바로 암호문에 넣는다.
public struct MachineTokenRotation: Sendable {
    public let token: String
    public let expiresAt: Date
    public let abilities: [String]
}

/// 서버가 봉인한 토큰 상자(`x25519-hkdf-sha256-chacha20poly1305`, core `App\Staff\SealedTokenBox`).
public struct SealedTokenBox: Codable, Sendable, Equatable {
    public static let algorithm = "x25519-hkdf-sha256-chacha20poly1305"
    public static let info = Data("gujo-staff-machine-token-v1".utf8)

    public let alg: String
    public let epk: String
    public let nonce: String
    public let ciphertext: String

    /// 받는 쪽 비밀키로 연다. 형식이 다르거나 인증에 실패하면 던진다.
    public func open(with key: Curve25519.KeyAgreement.PrivateKey) throws -> String {
        guard alg == Self.algorithm,
              let ephemeral = Data(base64Encoded: epk),
              let nonceData = Data(base64Encoded: nonce),
              let sealed = Data(base64Encoded: ciphertext),
              sealed.count > 16
        else { throw GujoAuthError.malformedResponse("sealed_token 형식이 아님") }
        let peer = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: ephemeral)
        let shared = try key.sharedSecretFromKeyAgreement(with: peer)
        let symmetric = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self, salt: ephemeral + key.publicKey.rawRepresentation,
            sharedInfo: Self.info, outputByteCount: 32)
        let box = try ChaChaPoly.SealedBox(
            nonce: ChaChaPoly.Nonce(data: nonceData),
            ciphertext: sealed.prefix(sealed.count - 16), tag: sealed.suffix(16))
        let plaintext = try ChaChaPoly.open(box, using: symmetric, authenticating: ephemeral)
        guard let text = String(data: plaintext, encoding: .utf8) else {
            throw GujoAuthError.malformedResponse("sealed_token 이 UTF-8 이 아님")
        }
        return text
    }
}

/// 사람 기기 로그인의 승인 주소를 기본 브라우저로 연다(`/usr/bin/open`, AWS SSO CLI 방식).
/// 앱은 주소와 코드를 그대로 출력·표시하고, 사용자가 끄면(`--no-browser`) 부르지 않는다.
public enum DeviceCodeBrowser {
    @discardableResult
    public static func open(_ prompt: DeviceCodePrompt) -> Bool {
        let result = SafeProcessRunner.runSync(
            executable: "/usr/bin/open", arguments: [prompt.browserURL.absoluteString], timeout: 10)
        return result.exitCode == 0
    }
}
