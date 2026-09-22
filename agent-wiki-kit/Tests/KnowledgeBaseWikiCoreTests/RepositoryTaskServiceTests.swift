import Foundation
import Testing
@testable import KnowledgeBaseWikiCore

@Suite("Repository task service")
struct RepositoryTaskServiceTests {
    @Test("worker failure persists, blocks verification, and a new binding enables retry")
    func failureReceiptAndRetry() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let service = RepositoryTaskService(
            store: fixture.store,
            repository: fixture.identity,
            author: "human")
        let task = try service.createTask(title: "Retry Grok", body: "run repository work")
        let firstBinding = try service.bind(
            taskID: task.id,
            runtimeTaskID: "runtime-failed",
            dispatchID: "dispatch-failed")

        var projection = RepositoryAgentOrchestration.projection(
            task: task,
            objects: fixture.store.scan(),
            currentSourceCommit: fixture.identity.sourceCommit)
        #expect(projection.state == .awaitingWorker)

        let failure = try service.recordWorkerFailure(
            taskID: task.id,
            runtimeTaskID: "runtime-failed",
            dispatchID: "dispatch-failed",
            worker: "repo-checker",
            exitCode: 1,
            message: "Grok usage balance exhausted")
        projection = RepositoryAgentOrchestration.projection(
            task: task,
            objects: fixture.store.scan(),
            currentSourceCommit: fixture.identity.sourceCommit)
        #expect(projection.state == .executionFailed)
        #expect(projection.workerFailureObjectId == failure.object.id)
        #expect(projection.workerFailureExitCode == 1)
        #expect(projection.workerFailureMessage == "Grok usage balance exhausted")
        #expect(projection.workerDoneObjectId == nil)
        #expect(throws: RepositoryTaskServiceError.self) {
            _ = try service.verify(taskID: task.id, checker: "checker", outcome: .verified)
        }

        let retryBinding = try service.bind(
            taskID: task.id,
            runtimeTaskID: "runtime-retry",
            dispatchID: "dispatch-retry")
        #expect(retryBinding.object.supersedes == firstBinding.object.id)
        projection = RepositoryAgentOrchestration.projection(
            task: task,
            objects: fixture.store.scan(),
            currentSourceCommit: fixture.identity.sourceCommit)
        #expect(projection.state == .awaitingWorker)
        #expect(projection.workerFailureObjectId == nil)

        _ = try service.recordWorkerDone(
            taskID: task.id,
            runtimeTaskID: "runtime-retry",
            dispatchID: "dispatch-retry",
            worker: "repo-checker",
            result: "retry succeeded")
        projection = RepositoryAgentOrchestration.projection(
            task: task,
            objects: fixture.store.scan(),
            currentSourceCommit: fixture.identity.sourceCommit)
        #expect(projection.state == .awaitingVerification)
        #expect(projection.workerDoneObjectId != nil)
    }

    @Test("GUI and CLI shared service closes the full agent workflow")
    func fullWorkflow() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let service = RepositoryTaskService(
            store: fixture.store,
            repository: fixture.identity,
            author: "human")

        let task = try service.createTask(title: "Ship workflow", body: "implement and verify")
        _ = try service.handoff(taskID: task.id, assignee: "release-maintainer")
        let binding = try service.bind(
            taskID: task.id,
            runtimeTaskID: "runtime-1",
            dispatchID: "dispatch-1",
            rules: ["AGENTS.md 준수"])

        #expect(binding.binding.canonicalTaskId == task.id)
        #expect(RepositoryAgentOrchestration.projection(
            task: task,
            objects: fixture.store.scan(),
            currentSourceCommit: fixture.identity.sourceCommit).state == .awaitingWorker)
        #expect(throws: RepositoryTaskServiceError.self) {
            _ = try service.verify(taskID: task.id, checker: "checker", outcome: .verified)
        }

        let worker = try service.recordWorkerDone(
            taskID: task.id,
            runtimeTaskID: "runtime-1",
            dispatchID: "dispatch-1",
            worker: "release-maintainer",
            result: "tests passed")
        #expect(worker.receipt.bindingObjectId == binding.object.id)

        let verification = try service.verify(
            taskID: task.id,
            checker: "checker:human",
            outcome: .verified)
        _ = try service.complete(
            taskID: task.id,
            verificationReceiptID: verification.object.id,
            result: "shipped")
        let knowledge = try service.publishKnowledgeCandidate(
            taskID: task.id,
            title: "Release workflow lesson",
            body: "Bind runtime identity before launch and require worker_done before checker approval.")

        let graph = LedgerTaskGraph(
            objects: fixture.store.scan(),
            currentSourceCommit: fixture.identity.sourceCommit)
        let item = try #require(graph.items.first { $0.taskId == task.id })
        #expect(item.status == .completed)
        #expect(item.assignee == "release-maintainer")
        #expect(item.orchestration.state == .verified)
        #expect(knowledge.tags.contains("promotion-candidate"))
        #expect(knowledge.cites.contains { $0.id == task.id && $0.rel == "learned-from-task" })
    }

    private func makeFixture() throws -> (root: URL, store: LedgerStore, identity: RepositoryIdentity) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let wiki = root.appendingPathComponent(".wiki", isDirectory: true)
        try FileManager.default.createDirectory(
            at: wiki.appendingPathComponent("objects"),
            withIntermediateDirectories: true)
        let identity = try RepositoryIdentity(
            remoteURL: "https://example.test/team/repository.git",
            worktreePath: root.path,
            gitCommonDirectory: root.appendingPathComponent(".git").path,
            currentBranch: "feature",
            defaultBranch: "main",
            sourceCommit: "abc123")
        return (root, LedgerStore(root: wiki), identity)
    }
}

@Suite("Repository agent role store")
struct RepositoryAgentRoleStoreTests {
    @Test("roles are repository-owned, engine-neutral, and Grok-capable")
    func repositoryRoleRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let wiki = root.appendingPathComponent(".wiki", isDirectory: true)
        try FileManager.default.createDirectory(at: wiki, withIntermediateDirectories: true)
        let repositoryRoot = RepositoryAgentRoleStore.repositoryRoot(forWorldRoot: wiki)
        let store = RepositoryAgentRoleStore(repositoryRoot: repositoryRoot)
        let definition = try store.makeDefinition(
            id: "release-maintainer",
            displayName: "Release Maintainer",
            summary: "Owns release readiness",
            engine: "grok",
            responsibilities: "Build, test, package, and report evidence.")
        let role = try store.save(id: "release-maintainer", definition: definition)

        #expect(repositoryRoot == root.standardizedFileURL)
        #expect(role.engine == "grok")
        #expect(role.id == "release-maintainer")
        #expect(role.fileURL.path.contains("/.agents/roles/"))
        #expect(!role.fileURL.path.contains("/.claude/agents/"))
        #expect(store.list().map(\.id) == ["release-maintainer"])
        #expect(throws: RepositoryAgentRoleStoreError.self) {
            _ = try store.save(id: "../escape", definition: definition)
        }
    }
}
