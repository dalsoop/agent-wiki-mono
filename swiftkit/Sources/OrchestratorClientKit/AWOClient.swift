import CommandKit
import Foundation
import InteropKit

/// AWO(agent-worker-orchestrator) CLI를 호출하는 공유 클라이언트.
///
/// 24개 앱이 각자 CLI 경로를 하드코딩하고 JobSpec을 재정의하던 것을 이 클라이언트로 통합한다.
/// `CommandRunning` 프로토콜을 쓰므로 테스트에서 목킹할 수 있다.
public struct AWOClient: Sendable {
    private let runner: any CommandRunning
    private let timeout: TimeInterval
    /// nil 이면 후보 경로에서 실행 파일을 찾는다. 테스트는 가짜 경로를 넣는다(디스크 존재를 보지 않음).
    private let executablePathOverride: String?

    public init(
        runner: any CommandRunning = ProcessCommandRunner(),
        executablePath: String? = nil,
        timeout: TimeInterval = 30
    ) {
        self.runner = runner
        self.executablePathOverride = executablePath
        self.timeout = timeout
    }

    // MARK: - 바이너리 경로

    /// Homebrew PATH helpers 는 스텁일 수 있다 — 앱 번들 바이너리를 두 번째로 본다.
    public static var executableCandidates: [String] {
        [
            HostPlatform.cliBinPath("agent-worker-orchestrator"),
            "/Applications/agent-worker-orchestrator.app/Contents/MacOS/agent-worker-orchestrator",
        ]
    }

    public static var executablePath: String {
        resolvedExecutable() ?? HostPlatform.cliBinPath("agent-worker-orchestrator")
    }

    public static func resolvedExecutable() -> String? {
        executableCandidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public static var isInstalled: Bool {
        resolvedExecutable() != nil
    }

    private var binary: String? {
        if let executablePathOverride { return executablePathOverride }
        return Self.resolvedExecutable()
    }

    // MARK: - dispatch

    /// JobSpec을 임시 JSON 파일로 쓰고 `agent-worker-orchestrator dispatch` 호출.
    public func dispatch(_ spec: AWOJobSpec, queueOnly: Bool = false) async -> AWOOutcome {
        guard let binary else {
            return AWOOutcome(ok: false, message: "agent-worker-orchestrator 미설치", exitCode: 127)
        }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ock-dispatch-\(UUID().uuidString).json")
        do {
            try spec.writeJSON(to: tmp.path)
        } catch {
            return AWOOutcome(ok: false, message: "스펙 저장 실패: \(error.localizedDescription)", exitCode: -1)
        }
        defer { try? FileManager.default.removeItem(at: tmp) }

        var args = ["dispatch", tmp.path, "--json"]
        if queueOnly { args.append("--queue-only") }
        let r = await runner.run(binary, args, timeout: timeout)
        let jobID = AWOOutcome.parseJobID(from: r.stdout)
        return AWOOutcome(
            ok: r.ok,
            message: r.ok ? r.trimmedStdout : errorText(r),
            exitCode: r.exitCode,
            jobID: jobID
        )
    }

    // MARK: - jobs

    /// 잡 목록 조회. JSON 파싱에 실패하면 빈 배열을 반환한다.
    public func jobs(state: String? = nil, tenant: String? = nil, includeFinished: Bool = false) async -> [AWOJobSummary] {
        guard let binary else { return [] }
        var args = ["jobs", "--json"]
        if let s = state { args += ["--state", s] }
        if let t = tenant { args += ["--tenant", t] }
        if includeFinished { args.append("--include-finished") }
        let r = await runner.run(binary, args, timeout: timeout)
        guard r.ok, let data = r.stdout.data(using: .utf8) else { return [] }
        return Self.decodeJobs(data)
    }

    // MARK: - report

    /// 잡 상세 조회.
    public func report(jobID: String) async -> AWOOutcome {
        guard let binary else {
            return AWOOutcome(ok: false, message: "agent-worker-orchestrator 미설치", exitCode: 127)
        }
        let r = await runner.run(binary, ["report", jobID, "--json"], timeout: timeout)
        return AWOOutcome(ok: r.ok, message: r.ok ? r.trimmedStdout : errorText(r), exitCode: r.exitCode)
    }

    // MARK: - cost

    /// 비용 조회.
    public func cost(tenant: String? = nil) async -> AWOOutcome {
        guard let binary else {
            return AWOOutcome(ok: false, message: "agent-worker-orchestrator 미설치", exitCode: 127)
        }
        var args = ["cost", "--json"]
        if let t = tenant { args += ["--tenant", t] }
        let r = await runner.run(binary, args, timeout: timeout)
        return AWOOutcome(ok: r.ok, message: r.ok ? r.trimmedStdout : errorText(r), exitCode: r.exitCode)
    }

    // MARK: - retry

    /// 실패 잡 재시도.
    public func retry(jobID: String, feedback: String? = nil) async -> AWOOutcome {
        guard let binary else {
            return AWOOutcome(ok: false, message: "agent-worker-orchestrator 미설치", exitCode: 127)
        }
        var args = ["retry", jobID, "--json"]
        if let fb = feedback { args += ["--feedback", fb] }
        let r = await runner.run(binary, args, timeout: timeout)
        return AWOOutcome(ok: r.ok, message: r.ok ? r.trimmedStdout : errorText(r), exitCode: r.exitCode)
    }

    // MARK: - Private

    private func errorText(_ r: CommandResult) -> String {
        let stderr = r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let stdout = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return stderr.isEmpty ? stdout : stderr
    }

    static func decodeJobs(_ data: Data) -> [AWOJobSummary] {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode([AWOJobSummary].self, from: data)
        } catch {}
        struct Envelope: Decodable {
            let result: [AWOJobSummary]?
        }
        do {
            let env = try decoder.decode(Envelope.self, from: data)
            if let arr = env.result {
                return arr
            }
        } catch {}
        return []
    }
}
