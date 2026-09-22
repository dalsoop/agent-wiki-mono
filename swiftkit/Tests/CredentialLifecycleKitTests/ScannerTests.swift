import Foundation
import Testing
@testable import CredentialLifecycleKit

private func makeTempDir() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("cred-scanner-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func write(_ text: String, to dir: URL, _ name: String) throws -> String {
    let path = dir.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: path.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try text.write(to: path, atomically: true, encoding: .utf8)
    return path.path
}

private let sample = "glpat-AbCdEfGhIjKlMnOpQrSt"
private let other = "glpat-ZzZzZzZzZzZzZzZzZzZz"  // allow:secret — 스캐너 시험용 합성 토큰

@Suite("값 패턴")
struct PatternTests {
    @Test("GitLab PAT 를 찾는다")
    func findsPAT() throws {
        let pattern = try CredentialValuePattern.gitLabPAT()
        #expect(pattern.matches(in: "url=https://oauth2:\(sample)@host/x.git") == [sample])
    }

    @Test("짧은 문자열은 토큰으로 보지 않는다")
    func ignoresShort() throws {
        #expect(try CredentialValuePattern.gitLabPAT().matches(in: "glpat-short").isEmpty)
    }

    @Test("잘못된 정규식은 생성 시점에 걸린다")
    func rejectsBadPattern() {
        #expect(throws: (any Error).self) {
            _ = try CredentialValuePattern(name: "bad", pattern: "[unclosed")
        }
    }

    @Test("base64 안에 숨은 값도 찾는다 — k8s Secret 이 이 형태다")
    func decodesBase64() throws {
        let pattern = try CredentialValuePattern.gitLabPAT()
        let encoded = Data(sample.utf8).base64EncodedString()
        let json = #"{"data":{"token":"\#(encoded)"}}"#
        #expect(pattern.matches(in: json).isEmpty)          // 그냥 보면 안 보이고
        #expect(pattern.matchesDecodingBase64(in: json) == [sample])  // 디코드해야 보인다
    }
}

@Suite("파일 스캐너")
struct FileScannerTests {
    @Test("설정 파일에서 값과 위치를 찾는다")
    func findsInFile() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = try write("token: \(sample)\n", to: dir, "config.yml")

        let scanner = FileConsumerScanner(roots: [dir.path],
                                          pattern: try .gitLabPAT())
        let found = try await scanner.scan()
        #expect(found.count == 1)
        #expect(found.first?.value == sample)
        #expect(found.first?.consumer.location == path)
        #expect(found.first?.consumer.kind == .file)
    }

    /// 이 라이브러리가 존재하는 이유와 직결된다 — 전사에 남은 값은 **소비처가 아니라 유출**이다.
    /// 교체 대상으로 섞이면 회전이 로그를 고치고 정작 설정은 안 고치는 참사가 된다.
    @Test("에이전트 세션 로그는 소비처로 잡지 않는다")
    func skipsTranscripts() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try write("token \(sample)", to: dir, ".codex/sessions/2026/rollout-x.jsonl")
        _ = try write("token \(sample)", to: dir, ".claude/projects/p/s.jsonl")
        _ = try write("token \(sample)", to: dir, "config.yml.bak")
        _ = try write("token: \(sample)", to: dir, "real-config.yml")

        let scanner = FileConsumerScanner(roots: [dir.path], pattern: try .gitLabPAT())
        let found = try await scanner.scan()
        #expect(found.count == 1)
        #expect(found.first?.consumer.location.hasSuffix("real-config.yml") == true)
    }

    @Test("유출 점검 목적이면 전사도 포함해 훑을 수 있다")
    func canIncludeTranscripts() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try write("token \(sample)", to: dir, ".codex/sessions/x.jsonl")

        let scanner = FileConsumerScanner(roots: [dir.path], pattern: try .gitLabPAT(),
                                          skipTranscripts: false)
        #expect(try await scanner.scan().count == 1)
    }

    @Test("큰 파일은 건너뛴다 — 로그가 GB 단위인 환경이 있다")
    func skipsHugeFiles() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try write(String(repeating: "x", count: 2048) + sample, to: dir, "big.txt")

        let scanner = FileConsumerScanner(roots: [dir.path], pattern: try .gitLabPAT(),
                                          maxFileBytes: 512)
        #expect(try await scanner.scan().isEmpty)
    }

    @Test("교체하면 파일 안 값이 실제로 바뀐다")
    func replaceRewritesFile() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = try write("a: \(sample)\nb: \(sample)\n", to: dir, "c.yml")

        let scanner = FileConsumerScanner(roots: [dir.path], pattern: try .gitLabPAT())
        let consumer = try await scanner.scan().first!.consumer
        #expect(try await scanner.replace(consumer, with: "glpat-NEWNEWNEWNEWNEWNEWNEW"))

        let after = try String(contentsOfFile: path, encoding: .utf8)
        #expect(!after.contains(sample))
        #expect(after.components(separatedBy: "glpat-NEWNEWNEWNEWNEWNEWNEW").count - 1 == 2)
    }

    @Test("바꿀 게 없으면 false — 헛되이 파일을 건드리지 않는다")
    func noopReplaceReturnsFalse() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try write("nothing here", to: dir, "c.yml")
        let scanner = FileConsumerScanner(roots: [dir.path], pattern: try .gitLabPAT())
        let consumer = CredentialConsumer(id: "x", kind: .file,
                                          location: dir.appendingPathComponent("c.yml").path)
        #expect(try await scanner.replace(consumer, with: "new") == false)
    }
}

@Suite("명령 출력 스캐너")
struct CommandScannerTests {
    @Test("명령 출력에서 값을 찾고 위치를 붙인다")
    func findsInOutput() async throws {
        let output = #"{"metadata":{"name":"repo-cred"},"data":{"token":"\#(sample)"}}"#
        let scanner = CommandOutputScanner(
            executable: "/bin/echo", arguments: [], pattern: try .gitLabPAT(),
            label: "k8s",
            locate: { out, _ in
                out.contains("repo-cred") ? "secret/repo-cred" : nil
            },
            runner: { _, _ in output })
        let found = try await scanner.scan()
        #expect(found.first?.value == sample)
        #expect(found.first?.consumer.location == "secret/repo-cred")
        #expect(found.first?.consumer.kind == .secretStore)
    }

    @Test("자동 교체하지 않는다 — 저장소마다 쓰기 방법이 달라 잘못 쓰면 되돌리기 어렵다")
    func neverAutoReplaces() async throws {
        let scanner = CommandOutputScanner(executable: "/bin/echo", arguments: [],
                                           pattern: try .gitLabPAT(), label: "k8s",
                                           runner: { _, _ in sample })
        let consumer = try await scanner.scan().first!.consumer
        #expect(try await scanner.replace(consumer, with: "new") == false)
    }

    /// "못 돌았다" 를 "없다" 로 보고하면 폐기해도 되는 줄 안다 — 그게 사고다.
    @Test("명령이 실행조차 안 되면 던진다 — 빈 결과로 삼키지 않는다")
    func commandFailureThrows() async {
        await #expect(throws: ScannerError.commandFailed(executable: "/nonexistent")) {
            let scanner = CommandOutputScanner(executable: "/nonexistent", arguments: [],
                                               pattern: try .gitLabPAT(), label: "x",
                                               runner: { _, _ in nil })
            _ = try await scanner.scan()
        }
    }
}

@Suite("Keychain 스캐너")
struct KeychainScannerTests {
    /// 실제 `security find-internet-password` 출력 형식 (2026-07-27 실측).
    private static let attrs = """
    keychain: "/Users/x/Library/Keychains/login.keychain-db"
    class: "inet"
    attributes:
        "acct"<blob>="oauth2"
        "path"<blob>=<NULL>
        "port"<uint32>=0x00000000
        "ptcl"<uint32>="htps"
        "srvr"<blob>="gitlab.internal.kr"
    """

    @Test("타입 태그가 달라도 속성을 읽는다 — blob 과 uint32 가 섞여 있다")
    func parsesMixedTags() {
        #expect(KeychainConsumerScanner.attribute("acct", in: Self.attrs) == "oauth2")
        #expect(KeychainConsumerScanner.attribute("ptcl", in: Self.attrs) == "htps")
        #expect(KeychainConsumerScanner.attribute("srvr", in: Self.attrs) == "gitlab.internal.kr")
        #expect(KeychainConsumerScanner.attribute("path", in: Self.attrs) == nil)  // <NULL>
        #expect(KeychainConsumerScanner.attribute("port", in: Self.attrs) == nil)  // 0x…
    }

    @Test("Keychain 에 든 토큰을 소비처로 잡는다 — 파일 스캔으로는 안 보이는 자리")
    func findsInKeychain() async throws {
        let scanner = KeychainConsumerScanner(
            servers: ["gitlab.internal.kr", "other.host"], pattern: try .gitLabPAT(),
            runner: { args in
                guard args.contains("gitlab.internal.kr") else { return ("", 44) }
                return args.contains("-w") ? (sample + "\n", 0) : (Self.attrs, 0)
            })
        let found = try await scanner.scan()
        #expect(found.count == 1)
        #expect(found.first?.value == sample)
        #expect(found.first?.consumer.location == "Keychain gitlab.internal.kr (oauth2)")
    }

    @Test("응답 없는 security 는 매달리지 않고 timedOut 으로 올라온다")
    func timeoutSurfacesInsteadOfHanging() async throws {
        let scanner = KeychainConsumerScanner(
            servers: ["gitlab.internal.kr"], pattern: try .gitLabPAT(),
            runner: { _ in ("", KeychainConsumerScanner.timedOutStatus) })
        await #expect(throws: ScannerError.self) { try await scanner.scan() }
    }

    @Test("실제 security 워치독이 시간을 끊는다")
    func securityRunnerHasWatchdog() async throws {
        // `security help` 는 즉시 끝난다 — 워치독이 정상 경로를 망치지 않는지만 본다.
        let (_, status) = await KeychainConsumerScanner.securityRunner(["help"])
        #expect(status != KeychainConsumerScanner.timedOutStatus)
    }

    @Test("교체는 쓴 뒤 다시 읽어 확인한다")
    func replaceVerifiesReadBack() async throws {
        let newValue = "glpat-NEWNEWNEWNEWNEWNEWNEW"
        let written = Written()
        let scanner = KeychainConsumerScanner(
            servers: ["h"], pattern: try .gitLabPAT(),
            runner: { args in
                if args.first == "add-internet-password" {
                    await written.set(true)
                    return ("", 0)
                }
                if args.contains("-w") {
                    return (await written.value ? newValue : sample, 0)
                }
                return (Self.attrs, 0)
            })
        let consumer = CredentialConsumer(id: "keychain:h", kind: .secretStore, location: "h")
        #expect(try await scanner.replace(consumer, with: newValue))
    }

    /// 이게 안전장치의 핵심 — 썼다고 보고했지만 실제로 안 바뀌었으면 false 를 돌려
    /// 회전이 '폐기' 단계로 못 넘어가게 한다.
    @Test("쓰기가 반영 안 됐으면 false — 구 토큰이 살아남는다")
    func replaceFailsWhenNotPersisted() async throws {
        let scanner = KeychainConsumerScanner(
            servers: ["h"], pattern: try .gitLabPAT(),
            runner: { args in
                args.contains("-w") && args.first != "add-internet-password"
                    ? (sample, 0)          // 계속 옛 값이 읽힌다
                    : (Self.attrs, 0)
            })
        let consumer = CredentialConsumer(id: "keychain:h", kind: .secretStore, location: "h")
        #expect(try await scanner.replace(consumer, with: "glpat-NEWNEWNEWNEWNEWNEWNEW") == false)
    }

    /// 44 = 항목 없음. 이건 진짜 "없음" 이라 건너뛰는 게 맞다.
    @Test("항목이 없으면(44) 조용히 건너뛴다")
    func missingItem() async throws {
        let scanner = KeychainConsumerScanner(servers: ["nope"], pattern: try .gitLabPAT(),
                                              runner: { _ in ("", 44) })
        #expect(try await scanner.scan().isEmpty)
    }

    /// 반면 security 자체가 안 돌면(-1) "없음" 이 아니다.
    @Test("security 를 실행 못 하면 던진다")
    func securityLaunchFailureThrows() async {
        await #expect(throws: ScannerError.commandFailed(executable: "/usr/bin/security")) {
            let scanner = KeychainConsumerScanner(servers: ["h"], pattern: try .gitLabPAT(),
                                                  runner: { _ in ("", -1) })
            _ = try await scanner.scan()
        }
    }
}

private actor Written {
    private(set) var value = false
    func set(_ new: Bool) { value = new }
}

@Suite("k8s Secret 스캐너")
struct KubernetesScannerTests {
    private func line(_ location: String, _ value: String) -> String {
        "\(location) \(Data(value.utf8).base64EncodedString())"
    }

    @Test("base64 로 숨은 값을 Secret 단위로 찾는다")
    func findsEncoded() async throws {
        let output = [line("argocd/repo-cred:password", "https://oauth2:\(sample)@host/x"),
                      line("kube-system/unrelated:token", "nothing"),
                      line("argocd/other-cred:password", sample)].joined(separator: "\n")
        let scanner = KubernetesSecretScanner(pattern: try .gitLabPAT(), runner: { _, _ in output })
        let found = try await scanner.scan()
        #expect(found.count == 2)
        #expect(Set(found.map(\.consumer.location))
            == ["argocd/repo-cred:password", "argocd/other-cred:password"])
        #expect(found.allSatisfy { $0.value == sample })
        #expect(found.allSatisfy { $0.consumer.kind == .secretStore })
    }

    @Test("클러스터에 자동으로 쓰지 않는다")
    func neverWritesToCluster() async throws {
        let scanner = KubernetesSecretScanner(pattern: try .gitLabPAT(),
                                              runner: { _, _ in self.line("ns/s:k", sample) })
        let consumer = try await scanner.scan().first!.consumer
        #expect(try await scanner.replace(consumer, with: "new") == false)
    }

    /// 이걸 빈 결과로 삼키면 "k8s 도 훑었는데 없더라" 가 되고, 실은 훑지도 않았다.
    /// 2026-07-27 실측으로 정확히 이 상태였다 — kubectl 이 /usr/local/bin 에 있었다.
    @Test("kubectl 을 못 돌리면 던진다 — 안 훑은 걸 없다고 하지 않는다")
    func missingKubectlThrows() async {
        await #expect(throws: ScannerError.commandFailed(executable: "/nope/kubectl")) {
            let scanner = KubernetesSecretScanner(executable: "/nope/kubectl",
                                                  pattern: try .gitLabPAT(),
                                                  runner: { _, _ in nil })
            _ = try await scanner.scan()
        }
    }

    @Test("kubectl 경로를 후보들에서 찾는다 — brew 만 보면 안 된다")
    func locatesKubectl() {
        #expect(KubernetesSecretScanner.candidateExecutables.contains("/usr/local/bin/kubectl"))
        #expect(KubernetesSecretScanner.candidateExecutables
            .contains(KubernetesSecretScanner.locateKubectl()))
    }

    @Test("깨진 줄은 건너뛴다 — 부분 출력이 전체를 죽이지 않게")
    func toleratesGarbage() async throws {
        let output = ["", "no-space-here", "ns/s:k !!!not-base64!!!", line("ns/ok:k", sample)]
            .joined(separator: "\n")
        let scanner = KubernetesSecretScanner(pattern: try .gitLabPAT(), runner: { _, _ in output })
        #expect(try await scanner.scan().map(\.consumer.location) == ["ns/ok:k"])
    }

    @Test("네임스페이스를 지정하면 -A 대신 -n 을 쓴다")
    func namespaceArgument() throws {
        #expect(KubernetesSecretScanner(pattern: try .gitLabPAT()).arguments.contains("-A"))
        #expect(KubernetesSecretScanner(namespace: "argocd", pattern: try .gitLabPAT())
            .arguments.contains("-nargocd"))
    }

    /// 원격 셸이 인자를 다시 쪼개므로 템플릿이 통째로 한 덩어리여야 한다.
    /// 안 묶으면 `{{$ns}}/{{$n}}:{{$k}} {{$v}}` 의 공백에서 조각나 명령이 깨진다.
    @Test("SSH 경로는 go-template 을 따옴표로 묶어 한 인자로 보낸다")
    func sshQuotesTemplate() throws {
        let scanner = KubernetesSecretScanner.overSSH(host: "root@10.0.0.1",
                                                      pattern: try .gitLabPAT())
        #expect(scanner.executable == "/usr/bin/ssh")
        #expect(scanner.arguments.contains("root@10.0.0.1"))
        #expect(scanner.arguments.contains("BatchMode=yes"))
        let remote = scanner.arguments.last ?? ""
        #expect(remote.hasPrefix("kubectl get secrets -A -o '"))
        #expect(remote.hasSuffix("'"))
        // 원격 명령은 인자 하나여야 한다 — 쪼개져 여러 인자가 되면 안 된다.
        #expect(scanner.arguments.filter { $0.contains("go-template") }.count == 1)
    }

    @Test("SSH 경로도 같은 파싱을 쓴다")
    func sshParsesSameOutput() async throws {
        let scanner = KubernetesSecretScanner.overSSH(
            host: "h", pattern: try .gitLabPAT(),
            runner: { _, _ in self.line("argocd/repo:password", sample) })
        #expect(try await scanner.scan().map(\.consumer.location) == ["argocd/repo:password"])
    }
}

@Suite("Infisical 스캐너")
struct InfisicalScannerTests {
    private func row(_ env: String, _ path: String, _ key: String, _ value: String) -> String {
        ["ws-1", env, path, key, value].joined(separator: "\t")
    }

    @Test("볼트 경로·키까지 위치로 남긴다 — k8s Secret 의 원본이 여기다")
    func findsInVault() async throws {
        let output = [row("prod", "/saas/gitlab", "gitlab_dev_token", sample),
                      row("prod", "/saas/gitlab", "gitlab_lxc_vmid", "50063"),
                      row("dev", "/ai-agents/hermes", "HERMES_GITLAB_TOKEN", other)]
            .joined(separator: "\n")
        let scanner = InfisicalConsumerScanner(pattern: try .gitLabPAT(), runner: { _, _ in output })
        let found = try await scanner.scan()
        #expect(found.count == 2)
        #expect(found.first(where: { $0.value == sample })?.consumer.location
            == "Infisical prod /saas/gitlab::gitlab_dev_token")
        #expect(found.allSatisfy { $0.consumer.kind == .secretStore })
    }

    @Test("URL 안에 박힌 토큰도 찾는다")
    func findsInsideURL() async throws {
        let output = row("prod", "/x", "DEPLOY_REPO_URL",
                         "https://oauth2:\(sample)@gitlab.internal.kr/a/b.git")
        let scanner = InfisicalConsumerScanner(pattern: try .gitLabPAT(), runner: { _, _ in output })
        #expect(try await scanner.scan().first?.value == sample)
    }

    @Test("환경을 지정하면 --env 를 넘긴다")
    func environmentArgument() throws {
        #expect(try InfisicalConsumerScanner(pattern: .gitLabPAT()).arguments == ["dump", "--reveal"])
        #expect(try InfisicalConsumerScanner(environment: "prod", pattern: .gitLabPAT())
            .arguments == ["dump", "--reveal", "--env", "prod"])
    }

    /// 볼트 값이 바뀌면 ExternalSecret 을 타고 클러스터까지 번진다 — 자동으로 안 쓴다.
    @Test("볼트에 자동으로 쓰지 않는다")
    func neverWrites() async throws {
        let scanner = InfisicalConsumerScanner(pattern: try .gitLabPAT(),
                                               runner: { _, _ in self.row("prod", "/x", "K", sample) })
        let consumer = try await scanner.scan().first!.consumer
        #expect(try await scanner.replace(consumer, with: "new") == false)
    }

    @Test("CLI 를 못 돌리면 던진다 — 볼트를 안 봤는데 '없다' 로 보고하지 않는다")
    func throwsWhenCLIMissing() async {
        await #expect(throws: ScannerError.commandFailed(executable: "/nope/infisical")) {
            let scanner = InfisicalConsumerScanner(executable: "/nope/infisical",
                                                   pattern: try .gitLabPAT(),
                                                   runner: { _, _ in nil })
            _ = try await scanner.scan()
        }
    }

    @Test("깨진 줄은 건너뛴다")
    func toleratesGarbage() async throws {
        let output = ["", "짧은줄", "a\tb\tc", row("prod", "/x", "K", sample)].joined(separator: "\n")
        let scanner = InfisicalConsumerScanner(pattern: try .gitLabPAT(), runner: { _, _ in output })
        #expect(try await scanner.scan().count == 1)
    }
}

@Suite("스캐너 + 회전 결합")
struct ScannerRotationTests {
    private actor Provider: CredentialProvider {
        nonisolated let sourceName = "test"
        let targetValue: String
        private(set) var revoked: [CredentialID] = []
        init(targetValue: String) { self.targetValue = targetValue }
        func listCredentials() async throws -> [ManagedCredential] { [] }
        func issue(like target: ManagedCredential, name: String) async throws -> IssuedCredential {
            IssuedCredential(id: CredentialID(2), name: name, value: "glpat-ROTATEDROTATEDROTATED")
        }
        func revoke(id: CredentialID) async throws { revoked.append(id) }
        func identify(value: String) async throws -> CredentialID? {
            value == targetValue ? CredentialID(1) : nil
        }
        func revokedIDs() -> [CredentialID] { revoked }
    }

    @Test("파일 소비처를 찾아 회전까지 끝난다")
    func endToEnd() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = try write("token: \(sample)\n", to: dir, "app.yml")
        _ = try write("token: \(other)\n", to: dir, "unrelated.yml")

        let target = ManagedCredential(
            identity: .init(id: CredentialID(1), name: "t", owner: "svc", ownerID: "1"),
            life: .init(createdAt: Date())
        )
        let provider = Provider(targetValue: sample)
        let scanner = FileConsumerScanner(roots: [dir.path], pattern: try .gitLabPAT())
        let coordinator = RotationCoordinator(provider: provider, scanners: [scanner])

        var progress = try await coordinator.discoverConsumers(for: target)
        // 남의 토큰이 든 파일은 잡히지 않아야 한다.
        #expect(progress.consumers.count == 1)
        #expect(progress.consumers.first?.location == path)

        try await coordinator.rotate(&progress, newName: "t-rotated") { _ in true }
        #expect(progress.isComplete)
        #expect(await provider.revokedIDs() == [CredentialID(1)])

        let after = try String(contentsOfFile: path, encoding: .utf8)
        #expect(after.contains("glpat-ROTATEDROTATEDROTATED"))
        #expect(!after.contains(sample))
    }
}

@Suite("git credential helper 스캐너")
struct GitCredentialHelperScannerTests {
    /// helper 프로토콜 응답 한 벌.
    static func response(password: String) -> String {
        "protocol=https\nhost=gitlab.internal.kr\nusername=devops\npassword=\(password)\n"
    }

    @Test("helper 로 읽은 토큰을 소비처로 잡는다 — security ACL 승인이 필요 없는 경로")
    func findsViaHelper() async throws {
        let scanner = GitCredentialHelperScanner(
            hosts: ["gitlab.internal.kr", "other.host"], pattern: try .gitLabPAT(),
            runner: { _, stdin in
                guard stdin.contains("gitlab.internal.kr") else { return ("", 0) }
                return (Self.response(password: sample), 0)
            })
        let found = try await scanner.scan()
        #expect(found.count == 1)
        #expect(found.first?.value == sample)
        #expect(found.first?.consumer.location == "git credential helper gitlab.internal.kr (devops)")
    }

    @Test("helper 를 실행하지 못하면 '없음'이 아니라 실패로 올린다")
    func executionFailureIsNotEmptiness() async throws {
        let scanner = GitCredentialHelperScanner(
            hosts: ["gitlab.internal.kr"], pattern: try .gitLabPAT(),
            runner: { _, _ in ("", -1) })
        await #expect(throws: ScannerError.self) { try await scanner.scan() }
    }

    @Test("교체는 stdin 으로만 값을 넘기고 쓴 뒤 다시 읽어 확인한다")
    func replaceVerifiesReadBack() async throws {
        let newValue = "glpat-NEWNEWNEWNEWNEWNEWNEW"
        let stored = StoredBody()
        let scanner = GitCredentialHelperScanner(
            hosts: ["gitlab.internal.kr"], pattern: try .gitLabPAT(),
            runner: { args, stdin in
                if args.first == "store" {
                    await stored.set(stdin)
                    return ("", 0)
                }
                let current = await stored.body == nil ? sample : newValue
                return (Self.response(password: current), 0)
            })
        let consumer = CredentialConsumer(
            id: "git-credential:gitlab.internal.kr", kind: .secretStore, location: "x")
        #expect(try await scanner.replace(consumer, with: newValue))
        // 값은 stdin 본문에만 있어야 한다 — argv 에 실리면 교체 순간 ps 로 샌다.
        #expect(await stored.body?.contains("password=\(newValue)") == true)
    }
}

private actor StoredBody {
    private(set) var body: String?
    func set(_ new: String) { body = new }
}
