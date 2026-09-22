import Foundation
import InteropKit

/// 자격증명 값이 저장돼 있을 만한 곳을 실제로 훑는 구현들.
///
/// 회전이 막히는 이유는 늘 하나다 — "이 값이 어디서 쓰이는지 모른다".
/// API 는 값을 돌려주지 않으므로, 후보 위치에서 **값처럼 생긴 문자열**을 긁어
/// `CredentialProvider.identify(value:)` 로 역인식하는 수밖에 없다.

/// 스캔이 **못 돌았다**는 것과 **찾은 게 없다**는 것은 다르다.
///
/// 둘을 같게 다루면 스캐너가 조용히 죽은 채 "소비처 없음 → 폐기해도 됨" 이 된다.
/// 2026-07-27 실측: `kubectl` 이 `/usr/local/bin` 에 있는데 `/opt/homebrew/bin` 을 보느라
/// k8s 스캔이 통째로 no-op 이었고, CLI 는 "+ k8s Secret 스캔함" 이라고 출력했다.
public enum ScannerError: Error, LocalizedError, Equatable, Sendable {
    case commandFailed(executable: String)
    case timedOut(executable: String, seconds: TimeInterval)

    public var errorDescription: String? {
        switch self {
        case let .commandFailed(executable):
            "\(executable) 를 실행하지 못했다. 스캔이 안 돈 것이지 소비처가 없는 게 아니다 — "
                + "경로를 확인하거나 그 스캐너를 빼고 돌려라."
        case let .timedOut(executable, seconds):
            "\(executable) 가 \(Int(seconds))초 안에 응답하지 않아 끊었다. Keychain 항목이 "
                + "접근 승인 프롬프트를 띄웠을 가능성이 크다(헤드리스라 아무도 못 누른다). "
                + "스캔이 안 돈 것이지 소비처가 없는 게 아니다 — 승인하거나 KEYCHAIN_SCAN_TIMEOUT 을 늘려라."
        }
    }
}

/// 자격증명 값을 알아보는 패턴. 제공자마다 접두사가 다르다.
public struct CredentialValuePattern: Sendable {
    /// `Regex` 는 Sendable 이 아니라 보관하지 않고 **패턴 문자열만** 들고 다닌다.
    /// 매칭 시점에 지역 생성한다(정규식 컴파일 비용보다 동시성 안전이 중요).
    public let pattern: String
    public let name: String

    public init(name: String, pattern: String) throws {
        _ = try Regex(pattern)   // 생성 시점에 문법 검증
        self.name = name
        self.pattern = pattern
    }

    /// GitLab 개인 액세스 토큰(`glpat-…`).
    public static func gitLabPAT() throws -> CredentialValuePattern {
        try CredentialValuePattern(name: "GitLab PAT", pattern: #"glpat-[A-Za-z0-9._-]{20,}"#)
    }

    /// 흔한 접두사들을 한 번에.
    public static func common() throws -> CredentialValuePattern {
        try CredentialValuePattern(
            name: "common",
            pattern: #"(glpat|gho|ghp|github_pat|xoxb|sk|st)-[A-Za-z0-9._-]{16,}"#)
    }

    public func matches(in text: String) -> [String] {
        guard let regex = try? Regex(pattern) else { return [] }
        return text.matches(of: regex).map { String(text[$0.range]) }
    }
}

// MARK: - 파일

/// 지정한 경로들을 훑어 자격증명 값을 찾는다.
///
/// - Important: 기본적으로 **에이전트 세션 로그·백업 파일은 건너뛴다.** 거기 있는 값은
///   "소비처"가 아니라 유출이다 — 교체 대상이 아니라 삭제 대상이므로 섞이면 안 된다.
///   유출 점검이 목적이면 `skipTranscripts: false` 로 켜서 따로 돌려라.
public struct FileConsumerScanner: ConsumerScanner {
    public let roots: [String]
    public let pattern: CredentialValuePattern
    public let skipTranscripts: Bool
    public let maxFileBytes: Int

    /// 전사·백업으로 취급해 건너뛸 경로 조각.
    public static let transcriptMarkers = [
        "/.codex/sessions/", "/.claude/projects/", "/.claude/history",
        ".pre-redact", ".bak", "/Caches/", "/.git/",
    ]

    public init(roots: [String], pattern: CredentialValuePattern,
                skipTranscripts: Bool = true, maxFileBytes: Int = 4 * 1024 * 1024) {
        self.roots = roots
        self.pattern = pattern
        self.skipTranscripts = skipTranscripts
        self.maxFileBytes = maxFileBytes
    }

    func shouldSkip(_ path: String) -> Bool {
        guard skipTranscripts else { return false }
        return Self.transcriptMarkers.contains { path.contains($0) }
    }

    public func scan() async throws -> [(value: String, consumer: CredentialConsumer)] {
        var out: [(String, CredentialConsumer)] = []
        for root in roots {
            var isDirectory: ObjCBool = false
            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: root, isDirectory: &isDirectory) else { continue }
            let paths: [String] = isDirectory.boolValue
                ? (fileManager.enumerator(atPath: root)?
                    .compactMap { ($0 as? String).map { root + "/" + $0 } } ?? [])
                : [root]
            for path in paths where !shouldSkip(path) {
                guard let size = try? fileManager.attributesOfItem(atPath: path)[.size] as? Int,
                      size <= maxFileBytes,
                      let text = try? String(contentsOfFile: path, encoding: .utf8)
                else { continue }
                let found = pattern.matches(in: text)
                guard !found.isEmpty else { continue }
                for value in Set(found) {
                    out.append((value, CredentialConsumer(
                        id: "file:\(path)",
                        kind: .file,
                        location: path,
                        occurrences: found.count { $0 == value })))
                }
            }
        }
        return out.map { (value: $0.0, consumer: $0.1) }
    }

    public func replace(_ consumer: CredentialConsumer, with newValue: String) async throws -> Bool {
        guard consumer.kind == .file else { return false }
        let path = consumer.location
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return false }
        var updated = text
        for old in pattern.matches(in: text) {
            updated = updated.replacingOccurrences(of: old, with: newValue)
        }
        guard updated != text else { return false }
        try updated.write(toFile: path, atomically: true, encoding: .utf8)
        return true
    }
}

// MARK: - 명령 출력

/// 임의의 명령을 돌려 그 출력에서 값을 찾는다.
/// k8s Secret(`kubectl get secret -A -o json`)처럼 API 뒤에 있는 저장소용.
///
/// 교체는 **자동으로 하지 않는다** — 저장소마다 쓰기 방법이 다르고, 잘못 쓰면
/// 되돌리기 어렵다. 찾아서 위치를 알려 주고 사람이 바꾸게 한다.
public struct CommandOutputScanner: ConsumerScanner {
    public typealias Runner = @Sendable (_ executable: String, _ arguments: [String]) async -> String?

    public let executable: String
    public let arguments: [String]
    public let pattern: CredentialValuePattern
    public let label: String
    /// 값 주변에서 위치 힌트를 뽑는다(예: JSON 키 이름). nil 이면 label 만 쓴다.
    public let locate: (@Sendable (_ output: String, _ value: String) -> String?)?
    private let runner: Runner

    public init(executable: String, arguments: [String], pattern: CredentialValuePattern,
                label: String,
                locate: (@Sendable (_ output: String, _ value: String) -> String?)? = nil,
                runner: @escaping Runner = CommandOutputScanner.processRunner) {
        self.executable = executable
        self.arguments = arguments
        self.pattern = pattern
        self.label = label
        self.locate = locate
        self.runner = runner
    }

    /// 종료코드가 0 이 아니면 **nil** 이다 — 즉 실패다.
    ///
    /// 실행은 됐지만 실패한 경우를 빈 출력으로 넘기면 "훑었는데 없더라" 가 된다.
    /// 2026-07-27 실측: 컨텍스트 없는 kubectl 이 exit 1 + 빈 stdout 을 냈고,
    /// 종료코드를 안 보던 이 함수가 그걸 "성공, 결과 없음" 으로 통과시켰다.
    public static let processRunner: Runner = { executable, arguments in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func scan() async throws -> [(value: String, consumer: CredentialConsumer)] {
        guard let output = await runner(executable, arguments) else {
            throw ScannerError.commandFailed(executable: executable)
        }
        var out: [(String, CredentialConsumer)] = []
        let found = pattern.matches(in: output)
        for value in Set(found) {
            let where_ = locate?(output, value) ?? label
            out.append((value, CredentialConsumer(
                id: "cmd:\(label):\(where_)",
                kind: .secretStore,
                location: where_,
                occurrences: found.count { $0 == value })))
        }
        return out.map { (value: $0.0, consumer: $0.1) }
    }

    /// 자동 교체하지 않는다 — 호출부가 `manual` 로 다루도록 false 를 돌려준다.
    public func replace(_ consumer: CredentialConsumer, with newValue: String) async throws -> Bool {
        false
    }
}

// MARK: - macOS Keychain

/// macOS Keychain 의 인터넷 암호 항목(git credential helper 가 쓰는 그 자리).
///
/// 파일 스캔으로는 **절대 안 보인다.** 2026-07-27 실측: glab 설정 파일에만 있는 줄 알았던
/// 토큰이 Keychain 에도 들어 있었다 — 파일만 고치고 구 토큰을 폐기했으면 그 순간부터
/// git push 가 인증 거부로 죽는다. 스캐너가 없어서 못 본 소비처가 정확히 이런 것이다.
///
/// - Note: `security` CLI 는 값을 인자로 받는다 → 교체 순간 `ps` 에 잠깐 노출된다.
///   CLI 가 stdin 을 지원하지 않아 우회로가 없다. 대신 **쓴 뒤 다시 읽어 확인**하고,
///   확인이 안 되면 false 를 돌려 회전이 폐기 단계로 넘어가지 못하게 막는다.
public struct KeychainConsumerScanner: ConsumerScanner {
    /// (표준출력, 종료코드).
    public typealias Runner = @Sendable (_ arguments: [String]) async -> (output: String, status: Int32)

    public let servers: [String]
    public let pattern: CredentialValuePattern
    private let runner: Runner

    public init(servers: [String], pattern: CredentialValuePattern,
                runner: @escaping Runner = KeychainConsumerScanner.securityRunner) {
        self.servers = servers
        self.pattern = pattern
        self.runner = runner
    }

    /// `security` 가 응답하지 않을 때 기다리는 한계(초). `KEYCHAIN_SCAN_TIMEOUT` 로 조절.
    public static var securityTimeout: TimeInterval {
        ProcessInfo.processInfo.environment["KEYCHAIN_SCAN_TIMEOUT"]
            .flatMap(Double.init) ?? 10
    }

    /// 타임아웃 때문에 값을 못 읽었다는 신호. "항목 없음"(정상)과 구분해야 한다.
    public static let timedOutStatus: Int32 = -2

    public static let securityRunner: Runner = { arguments in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        // stdin 을 /dev/null 로 묶는다 — 프롬프트가 입력을 기다리며 매달리는 걸 막는다.
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return ("", -1) }

        // 워치독 없는 readDataToEndOfFile 은 **영원히** 블록된다. 실측(2026-07-28):
        // 항목 ACL 이 이 바이너리를 허용하지 않으면 `security -w` 가 GUI 승인 프롬프트를
        // 띄우고, 헤드리스 CLI 는 아무 출력 없이 11분 넘게 멈춰 있었다. 사용자에겐
        // "느린 스캔"과 구분되지 않는다. 그래서 시간을 끊고 timedOut 으로 보고한다.
        let collected = DataBox()
        let reader = Thread {
            collected.set(pipe.fileHandleForReading.readDataToEndOfFile())
        }
        reader.start()

        let deadline = Date().addingTimeInterval(securityTimeout)
        while process.isRunning, Date() < deadline {
            usleep(20_000)
        }
        if process.isRunning {
            process.terminate()
            usleep(200_000)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            return (collected.get().flatMap { String(data: $0, encoding: .utf8) } ?? "",
                    timedOutStatus)
        }
        process.waitUntilExit()
        // 프로세스는 끝났으니 파이프도 EOF 다 — reader 가 곧 값을 채운다.
        let readDeadline = Date().addingTimeInterval(2)
        while collected.get() == nil, Date() < readDeadline { usleep(10_000) }
        let data = collected.get() ?? Data()
        return (String(data: data, encoding: .utf8) ?? "", process.terminationStatus)
    }

    /// 리더 스레드와 호출자가 함께 보는 한 칸짜리 상자.
    final class DataBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Data?
        func set(_ data: Data) { lock.lock(); value = data; lock.unlock() }
        func get() -> Data? { lock.lock(); defer { lock.unlock() }; return value }
    }

    /// `"acct"<blob>="oauth2"` / `"ptcl"<uint32>="htps"` 에서 값을 뽑는다.
    /// 타입 태그가 키마다 다르므로(`<blob>`·`<uint32>`) 태그는 건너뛰고 `="…"` 만 본다.
    /// `"path"<blob>=<NULL>` 처럼 값이 없는 줄은 자연히 걸러진다.
    static func attribute(_ key: String, in output: String) -> String? {
        for line in output.split(separator: "\n") {
            guard let keyRange = line.range(of: "\"\(key)\"<"),
                  let open = line.range(of: "=\"", range: keyRange.upperBound..<line.endIndex),
                  let close = line.range(of: "\"", range: open.upperBound..<line.endIndex)
            else { continue }
            return String(line[open.upperBound..<close.lowerBound])
        }
        return nil
    }

    /// `security` 는 항목이 없으면 44 로 끝난다 — 그건 정상적인 "없음" 이다.
    /// 실행 자체가 안 된 경우(-1)만 실패로 올린다.
    private func readValue(server: String) async throws -> String? {
        let (output, status) = await runner(["find-internet-password", "-s", server, "-w"])
        if status == Self.timedOutStatus {
            throw ScannerError.timedOut(executable: "/usr/bin/security",
                                        seconds: Self.securityTimeout)
        }
        if status < 0 { throw ScannerError.commandFailed(executable: "/usr/bin/security") }
        guard status == 0 else { return nil }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func scan() async throws -> [(value: String, consumer: CredentialConsumer)] {
        var out: [(String, CredentialConsumer)] = []
        for server in servers {
            guard let value = try await readValue(server: server),
                  let match = pattern.matches(in: value).first
            else { continue }
            let (attrs, status) = await runner(["find-internet-password", "-s", server])
            let account = status == 0 ? (Self.attribute("acct", in: attrs) ?? "") : ""
            out.append((match, CredentialConsumer(
                id: "keychain:\(server)",
                kind: .secretStore,
                location: "Keychain \(server)" + (account.isEmpty ? "" : " (\(account))"))))
        }
        return out.map { (value: $0.0, consumer: $0.1) }
    }

    public func replace(_ consumer: CredentialConsumer, with newValue: String) async throws -> Bool {
        guard consumer.id.hasPrefix("keychain:") else { return false }
        let server = String(consumer.id.dropFirst("keychain:".count))
        let (attrs, status) = await runner(["find-internet-password", "-s", server])
        guard status == 0, let account = Self.attribute("acct", in: attrs) else { return false }
        var arguments = ["add-internet-password", "-s", server, "-a", account,
                         "-w", newValue, "-U"]
        if let proto = Self.attribute("ptcl", in: attrs) {
            arguments += ["-r", proto]
        }
        guard await runner(arguments).status == 0 else { return false }
        // 썼다고 믿지 않는다 — 다시 읽어 확인한다. 못 확인하면 회전은 여기서 멈춘다.
        return try await readValue(server: server) == newValue
    }
}

// MARK: - Infisical

/// Infisical 볼트를 훑는다.
///
/// k8s Secret 스캐너가 찾는 값들의 **원본**이 대개 여기다 — ExternalSecret 이
/// Infisical 에서 당겨 Secret 을 만든다. 그래서 k8s 만 보면 "17곳에 있다" 까지는
/// 알아도 **어디를 고쳐야 그게 바뀌는지**는 모른다. 2026-07-27 실측이 정확히 그랬다.
///
/// 값은 `infisical dump --reveal` 한 번으로 받는다(경로마다 get 을 부르면 수백 번
/// 프로세스를 띄우게 된다). 교체는 하지 않는다 — 그 CLI 는 읽기 전용이고,
/// 볼트 쓰기는 되돌리기 어려워 사람이 한다.
public struct InfisicalConsumerScanner: ConsumerScanner {
    public typealias Runner = @Sendable (_ executable: String, _ arguments: [String]) async -> String?

    public let executable: String
    public let pattern: CredentialValuePattern
    /// 특정 환경만 볼 때(예: prod). nil 이면 접근 가능한 전 환경.
    public let environment: String?
    private let runner: Runner

    public static let candidateExecutables = [
        HostPlatform.cliBinPath("infisical"), "/usr/local/bin/infisical",
    ]

    public static func locate() -> String {
        candidateExecutables.first { FileManager.default.isExecutableFile(atPath: $0) }
            ?? candidateExecutables[0]
    }

    public init(executable: String = InfisicalConsumerScanner.locate(),
                environment: String? = nil,
                pattern: CredentialValuePattern,
                runner: @escaping Runner = CommandOutputScanner.processRunner) {
        self.executable = executable
        self.environment = environment
        self.pattern = pattern
        self.runner = runner
    }

    var arguments: [String] {
        var args = ["dump", "--reveal"]
        if let environment { args += ["--env", environment] }
        return args
    }

    /// `workspaceId \t env \t path \t key \t value` 한 줄씩.
    public func scan() async throws -> [(value: String, consumer: CredentialConsumer)] {
        guard let output = await runner(executable, arguments) else {
            throw ScannerError.commandFailed(executable: executable)
        }
        var out: [(String, CredentialConsumer)] = []
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 5 else { continue }
            let (env, path, key) = (String(fields[1]), String(fields[2]), String(fields[3]))
            // 값에 탭이 있으면 dump 가 공백으로 바꾸므로 나머지를 다시 합쳐도 안전하다.
            let value = fields[4...].joined(separator: "\t")
            for match in Set(pattern.matches(in: value)) {
                out.append((match, CredentialConsumer(
                    id: "infisical:\(env):\(path):\(key)",
                    kind: .secretStore,
                    location: "Infisical \(env) \(path)::\(key)")))
            }
        }
        return out.map { (value: $0.0, consumer: $0.1) }
    }

    /// 볼트에 자동으로 쓰지 않는다 — CLI 가 읽기 전용이고, 여기 값이 바뀌면
    /// ExternalSecret 을 타고 클러스터까지 번진다. 위치만 알려 주고 사람이 바꾼다.
    public func replace(_ consumer: CredentialConsumer, with newValue: String) async throws -> Bool {
        false
    }
}

// MARK: - k8s Secret

/// 클러스터의 Secret 을 훑는다.
///
/// 값이 base64 로 들어 있어 그냥 grep 하면 **안 보인다**. 2026-07-27 실사고에서
/// 평문 ConfigMap 하나만 보고 폐기하려던 토큰이 실은 17개 Secret 에 흩어져 있었다 —
/// 폐기 대상이 아니라 회전 대상이었다. 그 판단을 사람이 눈으로 하지 않게 하려고 있다.
///
/// 교체는 하지 않는다(`replace` 는 항상 false) — 클러스터에 쓰는 건 위험도가 다르고,
/// 롤아웃 재시작까지 엮이므로 사람이 한다.
public struct KubernetesSecretScanner: ConsumerScanner {
    public typealias Runner = @Sendable (_ executable: String, _ arguments: [String]) async -> String?

    /// `네임스페이스/이름:키 base64` 한 줄씩. 공백 구분이라 base64 패딩(`=`)이 살아남는다.
    public static let template = #"{{range .items}}{{$ns := .metadata.namespace}}{{$n := .metadata.name}}{{range $k, $v := .data}}{{$ns}}/{{$n}}:{{$k}} {{$v}}{{"\n"}}{{end}}{{end}}"#

    public let executable: String
    public let arguments: [String]
    public let pattern: CredentialValuePattern
    private let runner: Runner

    /// kubectl 설치 위치는 환경마다 다르다(brew/Docker Desktop/수동 설치).
    /// 한 곳만 보고 없으면 조용히 no-op 하는 게 이 스캐너의 최악 실패다.
    public static let candidateExecutables = [
        HostPlatform.cliBinPath("kubectl"), "/usr/local/bin/kubectl", "/usr/bin/kubectl",
    ]

    public static func locateKubectl() -> String {
        candidateExecutables.first { FileManager.default.isExecutableFile(atPath: $0) }
            ?? candidateExecutables[0]
    }

    static func kubectlArguments(namespace: String?) -> [String] {
        ["get", "secrets", namespace.map { "-n\($0)" } ?? "-A",
         "-o", "go-template=" + template]
    }

    public init(executable: String = KubernetesSecretScanner.locateKubectl(),
                namespace: String? = nil,
                pattern: CredentialValuePattern,
                runner: @escaping Runner = CommandOutputScanner.processRunner) {
        self.init(executable: executable,
                  arguments: Self.kubectlArguments(namespace: namespace),
                  pattern: pattern, runner: runner)
    }

    public init(executable: String, arguments: [String],
                pattern: CredentialValuePattern,
                runner: @escaping Runner = CommandOutputScanner.processRunner) {
        self.executable = executable
        self.arguments = arguments
        self.pattern = pattern
        self.runner = runner
    }

    /// 원격 클러스터용. 실무에서 k8s 는 보통 손에 든 기계에 없다 —
    /// 이 저장소 환경도 클러스터가 전부 다른 호스트에 있고, 맥의 kubectl 은 컨텍스트조차 없다.
    ///
    /// 원격 셸이 인자를 다시 쪼개므로 go-template 을 **작은따옴표로 묶어 한 덩어리**로 보낸다
    /// (템플릿 안에 공백이 있어서 안 묶으면 조각난다). 템플릿에 작은따옴표는 없다.
    public static func overSSH(host: String, namespace: String? = nil,
                               kubectl: String = "kubectl",
                               ssh: String = "/usr/bin/ssh",
                               pattern: CredentialValuePattern,
                               runner: @escaping Runner = CommandOutputScanner.processRunner)
        -> KubernetesSecretScanner {
        let remote = ([kubectl] + kubectlArguments(namespace: namespace))
            .map { $0.contains(" ") || $0.contains("{") ? "'\($0)'" : $0 }
            .joined(separator: " ")
        return KubernetesSecretScanner(
            executable: ssh,
            arguments: ["-o", "BatchMode=yes", "-o", "ConnectTimeout=10", host, remote],
            pattern: pattern, runner: runner)
    }

    public func scan() async throws -> [(value: String, consumer: CredentialConsumer)] {
        guard let output = await runner(executable, arguments) else {
            throw ScannerError.commandFailed(executable: executable)
        }
        var out: [(String, CredentialConsumer)] = []
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2,
                  let data = Data(base64Encoded: String(parts[1])),
                  let decoded = String(data: data, encoding: .utf8)
            else { continue }
            let found = pattern.matches(in: decoded)
            for value in Set(found) {
                out.append((value, CredentialConsumer(
                    id: "k8s:\(parts[0])",
                    kind: .secretStore,
                    location: String(parts[0]),
                    occurrences: found.count { $0 == value })))
            }
        }
        return out.map { (value: $0.0, consumer: $0.1) }
    }

    /// 클러스터에 자동으로 쓰지 않는다 — 위치만 알려 주고 사람이 바꾼다.
    public func replace(_ consumer: CredentialConsumer, with newValue: String) async throws -> Bool {
        false
    }
}

// MARK: - base64 안에 숨은 값

public extension CredentialValuePattern {
    /// k8s Secret 처럼 값이 base64 로 들어 있는 출력에서, 디코드해 다시 찾는다.
    /// JSON 문자열 토큰을 훑어 디코드 가능한 것만 시도한다.
    func matchesDecodingBase64(in text: String) -> [String] {
        var out = matches(in: text)
        let candidates = text.split(whereSeparator: { "\"' \n\t,{}[]:".contains($0) })
        for token in candidates where token.count >= 16 && token.count % 4 == 0 {
            guard let data = Data(base64Encoded: String(token)),
                  let decoded = String(data: data, encoding: .utf8) else { continue }
            out += matches(in: decoded)
        }
        return out
    }
}
