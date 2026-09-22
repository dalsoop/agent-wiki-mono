import CommandKit
import Foundation
import OrchestratorClientKit
import Testing

@Suite("OrchestratorClientKit")
struct OrchestratorClientKitTests {
    @Test func jobSpecOmitsNilModelAndEmptyArrays() throws {
        let spec = AWOJobSpec(
            title: "t",
            workdir: "/tmp",
            prompt: "do the thing",
            model: nil,
            tenantID: "tenant:personal"
        )
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ock-spec-\(UUID().uuidString).json")
        try spec.writeJSON(to: tmp.path)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: tmp)) as? [String: Any]
        #expect(obj?["prompt"] as? String == "do the thing")
        #expect(obj?["worker"] as? String == "codex")
        #expect(obj?["tenantID"] as? String == "tenant:personal")
        #expect(obj?["model"] == nil)
        #expect(obj?["brief"] == nil)
        #expect(obj?["dependsOn"] == nil)
    }

    @Test func jobSpecAcceptsFlatWorkerEffortAndBacklogIDs() {
        let spec = AWOJobSpec(
            title: "t",
            workdir: "/tmp",
            prompt: "p",
            worker: "codex",
            effort: "high",
            backlogIDs: ["b1"],
            tenantID: "tenant:personal"
        )
        #expect(spec.worker == "codex")
        #expect(spec.effort == "high")
        #expect(spec.backlogIDs == ["b1"])
    }

    @Test func parseJobIDReadsNestedResult() {
        #expect(AWOOutcome.parseJobID(from: #"{"id":"abc"}"#) == "abc")
        #expect(AWOOutcome.parseJobID(from: #"{"job":{"id":"j1"}}"#) == "j1")
        #expect(AWOOutcome.parseJobID(from: #"{"ok":true,"result":{"id":"r1"}}"#) == "r1")
        #expect(AWOOutcome.parseJobID(from: "not json") == nil)
    }

    @Test func dispatchWritesSpecAndParsesJobID() async {
        let runner = RecordingRunner(result: CommandResult(
            stdout: #"{"id":"job-42"}"#, stderr: "", exitCode: 0))
        let client = AWOClient(runner: runner, executablePath: "/fake/awo")
        let outcome = await client.dispatch(
            AWOJobSpec(title: "hello", workdir: "/tmp", prompt: "p"),
            queueOnly: true
        )
        #expect(outcome.ok)
        #expect(outcome.jobID == "job-42")
        let args = await runner.lastArguments
        #expect(args.first == "dispatch")
        #expect(args.contains("--json"))
        #expect(args.contains("--queue-only"))
    }

    @Test func jobsDecodesNestedSpecArray() async {
        let json = """
        [{"id":"j1","state":"queued","spec":{"title":"t","worker":"grok","model":"grok-4.5"}}]
        """
        let runner = RecordingRunner(result: CommandResult(stdout: json, stderr: "", exitCode: 0))
        let client = AWOClient(runner: runner, executablePath: "/fake/awo")
        let jobs = await client.jobs()
        #expect(jobs.count == 1)
        #expect(jobs.first?.id == "j1")
        #expect(jobs.first?.spec.title == "t")
        #expect(jobs.first?.spec.worker == "grok")
    }

    @Test func jobsDecodesOkResultEnvelope() async {
        let json = """
        {"ok":true,"result":[{"id":"j2","state":"running","spec":{"title":"u"}}]}
        """
        let runner = RecordingRunner(result: CommandResult(stdout: json, stderr: "", exitCode: 0))
        let client = AWOClient(runner: runner, executablePath: "/fake/awo")
        let jobs = await client.jobs()
        #expect(jobs.map(\.id) == ["j2"])
    }

    @Test func inboxAutoDispatchDryRunDoesNotCallCLI() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ock-inbox-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let pending = """
        {"id":"item-1","title":"fix ui","body":"button","status":"pending","workdir":"\(dir.path)"}
        """
        try Data(pending.utf8).write(to: dir.appendingPathComponent("item-1.json"))
        let handed = """
        {"id":"item-2","title":"build","status":"pending","handoff":"infra-coordinator"}
        """
        try Data(handed.utf8).write(to: dir.appendingPathComponent("item-2.json"))
        let runner = RecordingRunner(result: CommandResult(stdout: "{}", stderr: "", exitCode: 0))
        let client = AWOClient(runner: runner, executablePath: "/fake/awo")
        let dispatcher = InboxAutoDispatcher(client: client, inboxDir: dir)
        let results = await dispatcher.dispatchPending(dryRun: true) { entry in
            AWOJobSpec(title: entry.title, workdir: entry.workdir ?? "/tmp", prompt: entry.body)
        }
        #expect(results.count == 1)
        #expect(results.first?.entry.id == "item-1")
        #expect(results.first?.outcome.message == "dry-run")
        let calls = await runner.callCount
        #expect(calls == 0)
    }

    @Test func inboxAutoDispatchRejectsMissingWorkdir() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ock-inbox-missing-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let pending = """
        {"id":"item-1","title":"gone","status":"pending","workdir":"/no/such/workdir-\(UUID().uuidString)"}
        """
        try Data(pending.utf8).write(to: dir.appendingPathComponent("item-1.json"))
        let runner = RecordingRunner(result: CommandResult(stdout: "{}", stderr: "", exitCode: 0))
        let client = AWOClient(runner: runner, executablePath: "/fake/awo")
        let dispatcher = InboxAutoDispatcher(client: client, inboxDir: dir)
        let results = await dispatcher.dispatchPending { entry in
            AWOJobSpec(title: entry.title, workdir: entry.workdir ?? "", prompt: entry.body)
        }
        #expect(results.count == 1)
        #expect(results.first?.outcome.ok == false)
        #expect(results.first?.outcome.message.contains("workdir 없음") == true)
        let calls = await runner.callCount
        #expect(calls == 0)
    }

    @Test func inboxEntryReadsInfraDetailAndCwd() throws {
        let json = Data(#"{"id":"i","title":"t","detail":"body text","cwd":"/src","source":"cli"}"#.utf8)
        let entry = try JSONDecoder().decode(InboxEntry.self, from: json)
        #expect(entry.body == "body text")
        #expect(entry.workdir == "/src")
        #expect(entry.status == "pending")
    }
}

private actor RecordingRunner: CommandRunning {
    let result: CommandResult
    private(set) var lastArguments: [String] = []
    private(set) var callCount = 0

    init(result: CommandResult) {
        self.result = result
    }

    func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval?) async -> CommandResult {
        lastArguments = arguments
        callCount += 1
        return result
    }
}
