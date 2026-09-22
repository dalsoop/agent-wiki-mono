import InteropKit
import Foundation
import CommandKit
import AppPathsKit
import KnowledgeBaseWikiCore

/// 내부용 — 당분간 full `agent-wiki` 프록시 (knowledge-base-wiki monlith CLI).
/// 이관 완료 후 Studio 가 full CLI 소유.
public struct AgentWikiStudioService: Sendable {
    private let runner: CommandRunning
    private let agentWikiPath: String

    public init(
        runner: CommandRunning = ProcessCommandRunner(),
        agentWikiPath: String = HostPlatform.cliBinPath("agent-wiki")
    ) {
        self.runner = runner
        self.agentWikiPath = agentWikiPath
    }

    public func status() async -> String {
        let r = await runner.run(agentWikiPath, ["world", "list"])
        return r.ok ? r.trimmedStdout : "error: agent-wiki world list failed"
    }

    public func worldCatalog() -> [WikiWorldListItem] {
        let config = LedgerConfig.load()
        return WikiWorldPresentation.listItems(
            worlds: config.effectiveWorlds,
            selectedName: WikiWorldPresentation.inferredPersonWorld()
        )
    }

    public func remoteSharedStatus() async -> String {
        let r = await runner.run(agentWikiPath, ["gujo", "status"])
        return r.ok ? r.trimmedStdout : (r.stderr.isEmpty ? "원격 상태 조회 실패" : r.stderr)
    }

    public func forward(args: [String]) async -> (stdout: String, stderr: String, exitCode: Int32) {
        let r = await runner.run(agentWikiPath, args)
        return (r.stdout, r.stderr, r.exitCode)
    }

    /// `list --json` 을 돌려 `WikiRecord` 배열로 파싱한다. 파싱 실패는 빈 배열 + 에러 메시지.
    public func listRecords(world: String) async -> (records: [WikiRecord], error: String?) {
        let r = await forward(args: ["--world", world, "list", "--json"])
        guard r.exitCode == 0 else {
            return ([], r.stderr.isEmpty ? "list 실패 (exit \(r.exitCode))" : r.stderr)
        }
        guard let data = r.stdout.data(using: .utf8) else {
            return ([], "list --json 응답을 해석하지 못했습니다")
        }
        do {
            let envelope = try JSONDecoder().decode(WikiListEnvelope.self, from: data)
            return (envelope.result.objects, nil)
        } catch {
            return ([], "list --json 응답을 해석하지 못했습니다: \(error)")
        }
    }

    /// `publish` 는 본문을 stdin 으로 받는다(full CLI 계약) — `CommandRunning` 은 stdin 을
    /// 지원하지 않아 이 메서드만 별도로 `Process` 를 직접 구동한다.
    public func publish(
        world: String,
        title: String,
        body: String,
        type: String? = nil,
        tags: [String] = []
    ) async -> (stdout: String, stderr: String, exitCode: Int32) {
        var args = ["--world", world, "publish", "--title", title]
        if let type, !type.isEmpty { args += ["--type", type] }
        for tag in tags where !tag.isEmpty { args += ["--tag", tag] }
        return await Self.runWithStdin(agentWikiPath, args, stdin: body)
    }

    /// stdin 으로 본문을 흘리는 프로세스 실행. `publish` 전용이라 별도 헬퍼로 뺐다 —
    /// `CommandRunning` 프로토콜(swiftkit)에 stdin 지원을 추가하는 건 이 앱 범위 밖.
    static func runWithStdin(
        _ path: String,
        _ arguments: [String],
        stdin: String
    ) async -> (stdout: String, stderr: String, exitCode: Int32) {
        let result = await SafeProcessRunner.runAsync(
            executable: path,
            arguments: arguments,
            input: Data(stdin.utf8)
        )
        return (result.stdout, result.stderr, result.exitCode)
    }

    public func ensureDurableStore() throws {
        try DurableAppLayout.ensureDatabase(at: DurableAppLayout.sqliteURL(slug: "agent-wiki-studio"))
    }
}
