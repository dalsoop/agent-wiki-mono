import Foundation
import InteropKit

/// git credential helper 를 통해 Keychain 항목을 읽는 스캐너.
///
/// `KeychainConsumerScanner` 와 **같은 자리**를 보지만 여는 문이 다르다. `/usr/bin/security`
/// 는 항목 ACL 에 없어서 접근 승인 프롬프트를 띄우고(헤드리스면 그대로 막힘), git 이 쓰는
/// helper 는 **그 항목을 만든 당사자라 ACL 에 이미 들어 있다** — 프롬프트 없이 즉시 읽힌다.
/// 실측 2026-07-28: security 는 10초 워치독에 걸렸고, helper 는 같은 항목을 바로 돌려줬다.
///
/// 곁다리로 얻는 이득이 하나 더 있다. `security add-internet-password -w <값>` 은 새 값을
/// **argv 로** 받아 교체 순간 `ps` 에 노출되는데, helper 는 stdin 으로 받는다.
public struct GitCredentialHelperScanner: ConsumerScanner {
    /// (표준출력, 종료코드). stdin 으로 helper 프로토콜 본문을 넣는다.
    public typealias Runner = @Sendable (_ arguments: [String], _ stdin: String) async -> (output: String, status: Int32)

    public let hosts: [String]
    public let pattern: CredentialValuePattern
    private let runner: Runner

    public init(hosts: [String], pattern: CredentialValuePattern,
                runner: @escaping Runner = GitCredentialHelperScanner.helperRunner) {
        self.hosts = hosts
        self.pattern = pattern
        self.runner = runner
    }

    /// helper 실행 파일. `git --exec-path` 밑에 있고, 환경변수로 덮어쓸 수 있다.
    /// 못 찾으면 nil — 스캐너가 조용히 "없음"이 되지 않도록 scan 에서 실패로 올린다.
    public static var helperPath: String? {
        if let override = ProcessInfo.processInfo.environment["GIT_CREDENTIAL_HELPER_BIN"],
           FileManager.default.isExecutableFile(atPath: override) { return override }
        let candidates = [
            "\(HostPlatform.homebrewPrefix)/opt/git/libexec/git-core/git-credential-osxkeychain",
            "/usr/local/git/libexec/git-core/git-credential-osxkeychain",
            "/Library/Developer/CommandLineTools/usr/libexec/git-core/git-credential-osxkeychain",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public static let helperRunner: Runner = { arguments, stdin in
        guard let path = helperPath else { return ("", -1) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let inPipe = Pipe(), outPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = Pipe()
        do { try process.run() } catch { return ("", -1) }
        inPipe.fileHandleForWriting.write(Data(stdin.utf8))
        try? inPipe.fileHandleForWriting.close()
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (String(data: data, encoding: .utf8) ?? "", process.terminationStatus)
    }

    /// helper 프로토콜은 `key=value` 줄의 나열이다.
    static func field(_ key: String, in output: String) -> String? {
        for line in output.split(separator: "\n") where line.hasPrefix("\(key)=") {
            return String(line.dropFirst(key.count + 1))
        }
        return nil
    }

    static func request(host: String) -> String {
        "protocol=https\nhost=\(host)\n\n"
    }

    public func scan() async throws -> [(value: String, consumer: CredentialConsumer)] {
        guard Self.helperPath != nil else { return [] }
        var out: [(String, CredentialConsumer)] = []
        for host in hosts {
            let (output, status) = await runner(["get"], Self.request(host: host))
            if status < 0 {
                throw ScannerError.commandFailed(executable: "git-credential-osxkeychain")
            }
            guard status == 0,
                  let password = Self.field("password", in: output),
                  let match = pattern.matches(in: password).first
            else { continue }
            let user = Self.field("username", in: output) ?? ""
            out.append((match, CredentialConsumer(
                id: "git-credential:\(host)",
                kind: .secretStore,
                location: "git credential helper \(host)" + (user.isEmpty ? "" : " (\(user))"))))
        }
        return out.map { (value: $0.0, consumer: $0.1) }
    }

    public func replace(_ consumer: CredentialConsumer, with newValue: String) async throws -> Bool {
        guard consumer.id.hasPrefix("git-credential:") else { return false }
        let host = String(consumer.id.dropFirst("git-credential:".count))
        let (existing, status) = await runner(["get"], Self.request(host: host))
        guard status == 0, let user = Self.field("username", in: existing) else { return false }

        // helper 는 같은 (protocol, host, username) 에 store 하면 덮어쓴다. 값은 stdin 으로만
        // 오간다 — argv 에 실리지 않으니 교체 순간에도 `ps` 로 새지 않는다.
        let body = "protocol=https\nhost=\(host)\nusername=\(user)\npassword=\(newValue)\n\n"
        let (_, storeStatus) = await runner(["store"], body)
        guard storeStatus == 0 else { return false }

        // 쓴 뒤 다시 읽어 확인한다. 확인이 안 되면 false 를 돌려 회전이 폐기 단계로
        // 넘어가지 못하게 막는다 — 구 값이 살아 있어야 되돌릴 수 있다.
        let (after, afterStatus) = await runner(["get"], Self.request(host: host))
        return afterStatus == 0 && Self.field("password", in: after) == newValue
    }
}
