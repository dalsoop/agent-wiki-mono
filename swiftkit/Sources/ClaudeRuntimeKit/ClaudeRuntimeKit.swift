import Foundation
import InteropKit
import Security
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Claude Code가 macOS에서 사용하는 OAuth Keychain 항목의 최소 계약.
/// 호출자는 UI/계정 모델을 이 모듈에 끌어오지 않고도 읽기·저장·삭제를 주입할 수 있다.
public protocol ClaudeCredentialKeychainStoring: Sendable {
    func load() -> Data?
    func save(_ data: Data) throws
    func delete() throws
}

public enum ClaudeCredentialKeychainError: LocalizedError, Sendable, Equatable {
    case operationFailed(Int32)

    public var errorDescription: String? {
        switch self {
        case .operationFailed(let status): return "Claude Code Keychain 오류 (OSStatus \(status))"
        }
    }
}

/// SecurityAgent를 띄우지 않는 Claude Code OAuth Keychain 저장소.
/// ACL 접근이 허용되지 않으면 `nil`/오류를 반환해 UI와 CLI가 멈추지 않게 한다.
public struct ClaudeCredentialKeychainStore: ClaudeCredentialKeychainStoring {
    public static let service = "Claude Code-credentials"

    public init() {}

    public func load() -> Data? {
        // 구형 ACL 항목은 SecItemCopyMatching의 비대화형 옵션을 무시하고
        // SecurityAgent 응답을 무기한 기다릴 수 있다. 별도 프로세스로 격리해
        // 캡처가 실패해도 앱/CLI 자체는 반드시 돌아오게 한다.
        guard let result = ClaudeCommandRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/security"),
            arguments: ["find-generic-password", "-s", Self.service, "-w"],
            environment: ProcessInfo.processInfo.environment,
            timeout: 5
        ), !result.timedOut, result.terminationStatus == 0 else { return nil }
        var data = Data(result.output.utf8)
        while data.last == 0x0A || data.last == 0x0D { data.removeLast() }
        return data.isEmpty ? nil : data
    }

    public func save(_ data: Data) throws {
        // load()와 동일하게 /usr/bin/security 외부 프로세스 + 타임아웃으로 격리한다.
        // 앱 프로세스 안에서 SecItemUpdate/SecItemAdd를 직접 부르면 구형 ACL 항목이
        // SecurityAgent 응답을 무기한 대기해 앱이 hang/크래시된다(load 주석 참조).
        // 실패/타임아웃은 명시적 오류로 돌려 UI가 멈추지 않게 한다.
        guard let secret = String(data: data, encoding: .utf8) else {
            throw ClaudeCredentialKeychainError.operationFailed(errSecParam)
        }
        // macOS ARG_MAX 여유. OAuth blob은 보통 수 KB지만 방어적으로 제한한다.
        guard secret.utf8.count < 200_000 else {
            throw ClaudeCredentialKeychainError.operationFailed(errSecParam)
        }
        let env = ProcessInfo.processInfo.environment
        // 항목 유무와 무관하게 먼저 제거 후 추가 — SecItemUpdate + SecItemAdd 한 쌍을
        // CLI delete + add로 대체하여 upsert semantics를 유지한다.
        _ = ClaudeCommandRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/security"),
            arguments: ["delete-generic-password", "-s", Self.service],
            environment: env,
            timeout: 5
        )
        let result = ClaudeCommandRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/security"),
            arguments: [
                "add-generic-password",
                "-s", Self.service,
                "-a", NSUserName(),
                "-U",
                "-w", secret,
            ],
            environment: env,
            timeout: 5
        )
        guard let result, !result.timedOut, result.terminationStatus == 0 else {
            let status = result?.terminationStatus ?? Int32(errSecInternalError)
            throw ClaudeCredentialKeychainError.operationFailed(status)
        }
    }

    public func delete() throws {
        let result = ClaudeCommandRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/security"),
            arguments: ["delete-generic-password", "-s", Self.service],
            environment: ProcessInfo.processInfo.environment,
            timeout: 5
        )
        // /usr/bin/security CLI: 항목 없음 = exit 44. 정상 취급한다.
        guard let result, !result.timedOut,
              result.terminationStatus == 0 || result.terminationStatus == 44 else {
            let status = result?.terminationStatus ?? Int32(errSecInternalError)
            throw ClaudeCredentialKeychainError.operationFailed(status)
        }
    }
}

/// `claude auth status --json`의 UI-무관 최소 상태.
public struct ClaudeAuthStatus: Sendable, Equatable {
    public let loggedIn: Bool
    public let organizationID: String?
    public let email: String?

    public init(loggedIn: Bool, organizationID: String?, email: String?) {
        self.loggedIn = loggedIn
        self.organizationID = organizationID
        self.email = email
    }

    /// Claude CLI JSON을 안전하게 읽는다. 로그인/조직 필드는 버전별 누락을 허용한다.
    public static func parse(json data: Data) -> ClaudeAuthStatus? {
        let root: [String: Any]
        do {
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            root = obj
        } catch {
            return nil
        }
        guard let loggedIn = root["loggedIn"] as? Bool else { return nil }
        return ClaudeAuthStatus(
            loggedIn: loggedIn,
            organizationID: root["orgId"] as? String,
            email: root["email"] as? String
        )
    }
}

/// Claude CLI 실행 결과. 출력은 진단용이며 호출자가 비밀값을 그대로 노출하면 안 된다.
public struct ClaudeCommandResult: Sendable, Equatable {
    public let terminationStatus: Int32
    public let output: String
    public let timedOut: Bool

    public init(terminationStatus: Int32, output: String, timedOut: Bool) {
        self.terminationStatus = terminationStatus
        self.output = output
        self.timedOut = timedOut
    }
}

/// Claude CLI를 제한 시간 안에 실행하는 공통 seam. 앱별 `waitUntilExit()` 중복을 금지한다.
public enum ClaudeCommandRunner {
    public static func run(
        executable: URL = URL(fileURLWithPath: "/usr/bin/env"),
        arguments: [String],
        environment: [String: String]? = nil,
        timeout: TimeInterval = 30
    ) -> ClaudeCommandResult? {
        let process = Process()
        let completion = DispatchSemaphore(value: 0)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-runtime-\(UUID().uuidString).log")
        guard FileManager.default.createFile(
            atPath: outputURL.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ),
              let output = FileHandle(forWritingAtPath: outputURL.path) else {
            return nil
        }
        defer {
            try? output.close()
            try? FileManager.default.removeItem(at: outputURL)
        }
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = output
        process.terminationHandler = { _ in completion.signal() }
        guard (try? process.run()) != nil else { return nil }

        let finished = completion.wait(timeout: .now() + timeout) == .success
        if !finished, process.isRunning {
            process.terminate()
            if completion.wait(timeout: .now() + 1) != .success, process.isRunning {
                Darwin.kill(process.processIdentifier, SIGKILL)
                _ = completion.wait(timeout: .now() + 1)
            }
        }
        try? output.synchronize()
        let captured = (try? Data(contentsOf: outputURL)) ?? Data()
        guard !process.isRunning else {
            return ClaudeCommandResult(
                terminationStatus: 124,
                output: String(decoding: captured, as: UTF8.self),
                timedOut: true
            )
        }
        return ClaudeCommandResult(
            terminationStatus: process.terminationStatus,
            output: String(decoding: captured, as: UTF8.self),
            timedOut: !finished
        )
    }
}

/// Claude CLI 상태 확인. 실패/타임아웃은 nil로 처리하여 화면 렌더 경로를 막지 않는다.
public enum ClaudeAuthStatusReader {
    static func preferredClaudeDirectories(homeDirectory: String = NSHomeDirectory()) -> [String] {
        [
            URL(fileURLWithPath: homeDirectory).appendingPathComponent(".local/bin").path,
            HostPlatform.homebrewBin,
            "/usr/local/bin",
        ]
    }

    /// GUI 앱은 로그인 셸의 PATH를 물려받지 않는다. Homebrew로 설치한 `claude`를
    /// (또는 Claude 자체 업데이트 경로인 `~/.local/bin`) 명시적으로 앞에 넣어야
    /// 앱과 터미널의 로그인 상태가 같은 결과를 낸다.
    static func environmentForClaudeCLI(
        base: [String: String] = ProcessInfo.processInfo.environment,
        preferredDirectories: [String] = preferredClaudeDirectories(),
        currentUsername: String = NSUserName(),
        fileManager: FileManager = .default
    ) -> [String: String] {
        var environment = base
        // Claude's native updater binary uses USER to resolve the login keychain.
        // Minimal GUI/agent environments may provide HOME but omit USER.
        if environment["USER"]?.isEmpty != false, !currentUsername.isEmpty {
            environment["USER"] = currentUsername
        }
        let installedDirectories = preferredDirectories
            .filter { fileManager.isExecutableFile(atPath: "\($0)/claude") }
        guard !installedDirectories.isEmpty else { return environment }

        let current = environment["PATH"] ?? ""
        let existing = Set(current.split(separator: ":").map(String.init))
        let missing = installedDirectories.filter { !existing.contains($0) }
        guard !missing.isEmpty else { return environment }
        environment["PATH"] = (missing + (current.isEmpty ? [] : [current])).joined(separator: ":")
        return environment
    }

    public static func current(
        executable: URL = URL(fileURLWithPath: "/usr/bin/env"),
        arguments: [String] = ["claude", "auth", "status", "--json"],
        environment: [String: String]? = nil,
        timeout: TimeInterval = 3
    ) -> ClaudeAuthStatus? {
        let runtimeEnvironment = environmentForClaudeCLI(
            base: environment ?? ProcessInfo.processInfo.environment
        )
        guard let result = ClaudeCommandRunner.run(
            executable: executable,
            arguments: arguments,
            environment: runtimeEnvironment,
            timeout: timeout
        ), !result.timedOut, result.terminationStatus == 0 else { return nil }
        return ClaudeAuthStatus.parse(json: Data(result.output.utf8))
    }
}

/// Z.ai Coding Plan의 Claude Code 환경변수 계약. 토큰 자체는 호출자가 보관한다.
public enum ClaudeZaiRuntime {
    public static let baseURL = "https://api.z.ai/api/anthropic"
    public static let sonnetModel = "GLM-5.3"
    public static let opusModel = "GLM-5.3"
    public static let haikuModel = "GLM-5.3-Flash"

    /// 기본값으로 쓰는 GLM-5.3 계열 + 계정 오버라이드용 레거시 모델.
    /// UI 추천 목록·입력 검증에 쓴다(2026-08 출시: GLM-5.3, GLM-5.3-Flash).
    public static let knownModels: [String] = [
        "GLM-5.3",
        "GLM-5.3-Flash",
        "GLM-5.2",
        "GLM-4.5-Air",
    ]

    /// GLM-5.3 실측 창(docs.z.ai): 입력 1M · 출력 128K (GLM-5.2 과 동일).
    /// Claude Code 는 모르는 모델을 200k 로 가정하고 auto-compact 를 걸기 때문에,
    /// 이 값을 넣지 않으면 쓸 수 있는 컨텍스트의 80% 를 그냥 버린다.
    public static let contextWindowTokens = 1_000_000
    public static let maxOutputTokens = 128_000

    public static let contextWindowKey = "CLAUDE_CODE_MAX_CONTEXT_TOKENS"

    /// **Z.ai 설정임을 판정하는** 키. 컨텍스트 창은 여기 넣지 않는다 —
    /// 창 키가 없던 시절에 쓰인 settings.json 이 GLM 이 아닌 것으로 오판된다.
    public static let identifyingKeys: Set<String> = [
        "ANTHROPIC_AUTH_TOKEN",
        "ANTHROPIC_BASE_URL",
        "ANTHROPIC_DEFAULT_SONNET_MODEL",
        "ANTHROPIC_DEFAULT_OPUS_MODEL",
        "ANTHROPIC_DEFAULT_HAIKU_MODEL",
    ]

    /// 우리가 **쓰고 지우는** 키 전부(판정용 + 튜닝 키).
    public static let environmentKeys: Set<String> = identifyingKeys.union([contextWindowKey])

    public static func environment(
        token: String,
        baseURL: String? = nil,
        sonnetModel: String? = nil,
        opusModel: String? = nil,
        haikuModel: String? = nil,
        contextWindow: Int? = nil
    ) -> [String: String] {
        [
            "ANTHROPIC_AUTH_TOKEN": token,
            "ANTHROPIC_BASE_URL": baseURL ?? Self.baseURL,
            "ANTHROPIC_DEFAULT_SONNET_MODEL": sonnetModel ?? Self.sonnetModel,
            "ANTHROPIC_DEFAULT_OPUS_MODEL": opusModel ?? Self.opusModel,
            "ANTHROPIC_DEFAULT_HAIKU_MODEL": haikuModel ?? Self.haikuModel,
            contextWindowKey: String(contextWindow ?? Self.contextWindowTokens),
        ]
    }
}
