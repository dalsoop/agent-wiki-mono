import Foundation
import InteropKit

private func waitWithTimeout(_ process: Process, seconds: TimeInterval = 30) {
    let item = DispatchWorkItem { process.terminate() }
    DispatchQueue.global().asyncAfter(deadline: .now() + seconds, execute: item)
    process.waitUntilExit()
    item.cancel()
}

/// 공식 `bw` CLI 를 감싸는 얇은 헬퍼 — 조직·컬렉션·공유처럼 네이티브 크립토로
/// 직접 구현하기 무거운 기능을 CLI 에 위임하기 위한 토대. 여기서는 온보딩(설치·서버·
/// 로그인·잠금해제 상태 진단)에 필요한 만큼만 노출한다.
///
/// 세션 키는 키체인(`bw-cli-session`)에 둔다 — GUI 앱과 에이전트가 같은 세션을 공유.
public struct BitwardenCLI: Sendable {
    public struct RunResult: Sendable, Equatable {
        public var exitCode: Int32
        public var output: String
        public var ok: Bool { exitCode == 0 }
        public init(exitCode: Int32, output: String) {
            self.exitCode = exitCode
            self.output = output
        }
    }
    public struct Status: Sendable, Equatable {
        public enum Auth: String, Sendable { case unauthenticated, locked, unlocked }
        public var installed: Bool
        public var binPath: String?
        public var serverURL: String?
        public var userEmail: String?
        public var auth: Auth
        public var hasSession: Bool

        public init(installed: Bool = false, binPath: String? = nil, serverURL: String? = nil,
                    userEmail: String? = nil, auth: Auth = .unauthenticated, hasSession: Bool = false) {
            self.installed = installed
            self.binPath = binPath
            self.serverURL = serverURL
            self.userEmail = userEmail
            self.auth = auth
            self.hasSession = hasSession
        }

        /// 조직 기능을 쓸 수 있는 완성 상태.
        public var isReady: Bool { installed && auth == .unlocked && hasSession }
    }

    public static let sessionAccount = "BW_SESSION"
    public static let sessionService = "bw-cli-session"

    public init() {}

    /// 흔한 설치 위치를 훑어 bw 실행 파일을 찾는다.
    public func resolveBinary() -> String? {
        let candidates = [
            HostPlatform.cliBinPath("bw"), "/usr/local/bin/bw", "/usr/bin/bw",
            (NSHomeDirectory() as NSString).appendingPathComponent(".npm-global/bin/bw"),
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// 키체인에 저장된 세션 키(있으면).
    public func storedSession() -> String? {
        let store = KeychainStore(service: Self.sessionService)
        guard let d = store.get(account: Self.sessionAccount), let s = String(data: d, encoding: .utf8),
              !s.isEmpty else { return nil }
        return s
    }

    public func saveSession(_ token: String) {
        let store = KeychainStore(service: Self.sessionService)
        try? store.set(Data(token.utf8), account: Self.sessionAccount)
    }

    public func clearSession() {
        KeychainStore(service: Self.sessionService).delete(account: Self.sessionAccount)
    }

    /// `bw status` 로 현재 상태를 진단한다. bw 미설치면 installed=false 로 즉시 반환.
    public func status() async -> Status {
        guard let bin = resolveBinary() else { return Status() }
        let session = storedSession()
        let out = await run(bin, ["status"], session: session)
        var st = Status(installed: true, binPath: bin, hasSession: session != nil)
        if let data = out.data(using: .utf8),
           let obj = VaultwardenJSON.object(from: data) {
            st.serverURL = (obj["serverUrl"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            st.userEmail = (obj["userEmail"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            if let raw = obj["status"] as? String, let a = Status.Auth(rawValue: raw) { st.auth = a }
        }
        return st
    }

    /// bw 실행 결과 stdout(실패해도 stdout+stderr 합쳐 반환). 세션이 있으면 BW_SESSION 주입.
    @discardableResult
    public func run(_ bin: String, _ args: [String], session: String? = nil) async -> String {
        await runResult(bin, args, session: session).output
    }

    /// stdout/stderr 원문과 종료 코드를 함께 돌려준다. 비밀 조회자는 exit 0일 때만 값을 사용한다.
    public func runResult(_ bin: String, _ args: [String], session: String? = nil) async -> RunResult {
        await withCheckedContinuation { cont in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: bin)
            proc.arguments = args
            var env = ProcessInfo.processInfo.environment
            if let session { env["BW_SESSION"] = session }
            proc.environment = env
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe
            do {
                try proc.run()
            } catch {
                cont.resume(returning: RunResult(exitCode: 127, output: ""))
                return
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            waitWithTimeout(proc, seconds: 30)
            cont.resume(returning: RunResult(
                exitCode: proc.terminationStatus,
                output: String(decoding: data, as: UTF8.self)))
        }
    }
}
