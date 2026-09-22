import Foundation
import Testing
@testable import KnowledgeBaseWikiCore

@Suite struct RepositoryAgentOrchestrationContractTests {
    @Test func doneWithoutCheckerReceiptNeverCompletesTask() throws {
        let store = try temporaryStore()
        let task = try store.publish(author: "owner", title: "Gate me", type: "task", body: "work")
        _ = try store.publish(author: "worker", title: "worker_done", type: "done", body: "finished", extras: LedgerPublishExtras(cites: [.init(id: task.id, rel: "completes")]))

        let graph = LedgerTaskGraph(objects: store.scan(), currentSourceCommit: "abc123")
        let item = try #require(graph.items.first)
        #expect(!graph.isDone(task.id))
        #expect(item.status != .completed)
        #expect(item.orchestration.state == .unbound)
        #expect(item.orchestration.warnings.contains { $0.code == .completionWithoutVerification })
    }

    @Test func sourceCommitChangeMakesKnowledgeSnapshotStale() throws {
        let fixture = try boundTask(sourceCommit: "old-commit")
        let graph = LedgerTaskGraph(
            objects: fixture.store.scan(), currentSourceCommit: "new-commit")
        let gate = try #require(graph.items.first?.orchestration)

        #expect(gate.state == .stale)
        #expect(gate.warnings.contains { $0.code == .sourceCommitStale })
        #expect(gate.sourceCommit == "old-commit")
    }

    @Test func supersededKnowledgeProducesDeterministicReferencesAndWarning() throws {
        let fixture = try boundTask(sourceCommit: "same")
        let successor = try fixture.store.publish(author: "owner", title: "Knowledge v2", type: "decision", body: "v2", now: Date(timeIntervalSince1970: 30), extras: LedgerPublishExtras(supersedes: fixture.knowledge.id))
        let graph = LedgerTaskGraph(objects: fixture.store.scan(), currentSourceCommit: "same")
        let gate = try #require(graph.items.first?.orchestration)

        #expect(gate.state == .stale)
        #expect(gate.warnings.contains {
            $0.code == .knowledgeSuperseded
                && $0.objectId == fixture.knowledge.id
                && $0.supersededByObjectId == successor.id
        })
        #expect(gate.knowledgeObjectIds == [fixture.knowledge.id])
    }

    @Test func contextCapsuleEnforcesKnowledgeAndRuleBounds() throws {
        let tooManyKnowledge = (0...RepositoryAgentTaskBinding.maxKnowledgeObjectCount)
            .map { "knowledge-\($0)" }
        #expect(throws: RepositoryAgentOrchestrationError.self) {
            _ = try RepositoryAgentTaskBinding(RepositoryAgentTaskBinding.Draft(
                canonicalTaskId: "task", runtimeTaskId: "orca-task", dispatchId: "dispatch",
                knowledgeObjectIds: tooManyKnowledge, knowledgeSnapshotHash: "hash",
                sourceCommit: "commit", rulesCapsule: [],
                boundAt: Date(), knowledgeCapturedAt: Date()))
        }
        #expect(throws: RepositoryAgentOrchestrationError.self) {
            _ = try RepositoryAgentTaskBinding(RepositoryAgentTaskBinding.Draft(
                canonicalTaskId: "task", runtimeTaskId: "orca-task", dispatchId: "dispatch",
                knowledgeObjectIds: ["knowledge"], knowledgeSnapshotHash: "hash",
                sourceCommit: "commit",
                rulesCapsule: [String(repeating: "x", count: RepositoryAgentTaskBinding.maxRuleUTF8Bytes + 1)],
                boundAt: Date(), knowledgeCapturedAt: Date()))
        }
    }

    @Test func bindingParserDefaultsAdditiveV1FieldsAndIgnoresUnknownKeys() throws {
        let body = """
        {
          "schemaVersion": "knowledge-base-wiki.repository-agent-task-binding.v1",
          "taskId": "task-1",
          "runtimeTaskId": "runtime-1",
          "dispatchId": "dispatch-1",
          "knowledgeObjectIds": ["knowledge-1"],
          "knowledgeSnapshotHash": "snapshot",
          "sourceCommit": "commit",
          "boundAt": "2026-07-27T00:00:00Z",
          "futureAdditiveField": true
        }
        """
        let binding = try #require(RepositoryAgentTaskBinding.decode(body: body))
        #expect(binding.rulesCapsule == [])
        #expect(binding.knowledgeCapturedAt == binding.boundAt)
        #expect(binding.canonicalTaskId == "task-1")
        #expect(try binding.json().contains("\"canonicalTaskId\""))
        #expect(!(try binding.json()).contains("\"taskId\""))
    }

    @Test func matchingCheckerReceiptAndDoneCompletesHappyPath() throws {
        let fixture = try boundTask(sourceCommit: "same")
        let receipt = try RepositoryAgentVerificationReceipt(RepositoryAgentVerificationReceipt.Draft(
            canonicalTaskId: fixture.task.id,
            runtimeTaskId: fixture.binding.runtimeTaskId,
            dispatchId: fixture.binding.dispatchId,
            bindingObjectId: fixture.bindingObject.id,
            knowledgeSnapshotHash: fixture.binding.knowledgeSnapshotHash,
            sourceCommit: fixture.binding.sourceCommit,
            checker: "checker:release-gate",
            outcome: .verified,
            checkedAt: Date(timeIntervalSince1970: 20)))
        let receiptObject = try fixture.store.publish(author: receipt.checker, title: "Verification receipt", type: RepositoryAgentVerificationReceipt.objectType, body: try receipt.json(), now: receipt.checkedAt, extras: LedgerPublishExtras(cites: [
                .init(id: fixture.task.id, rel: RepositoryAgentOrchestration.verifiesRelation),
                .init(id: fixture.bindingObject.id, rel: RepositoryAgentOrchestration.verifiesBindingRelation),
            ]))
        let done = try fixture.store.publish(author: "worker", title: "Done", type: "done", body: "finished", now: Date(timeIntervalSince1970: 25), extras: LedgerPublishExtras(cites: [
                .init(id: fixture.task.id, rel: "completes"),
                .init(id: receiptObject.id, rel: RepositoryAgentOrchestration.verifiedByRelation),
            ]))

        let graph = LedgerTaskGraph(objects: fixture.store.scan(), currentSourceCommit: "same")
        let item = try #require(graph.items.first)
        #expect(graph.isDone(fixture.task.id))
        #expect(item.status == .completed)
        #expect(item.orchestration.state == .verified)
        #expect(item.orchestration.runtimeTaskId == fixture.binding.runtimeTaskId)
        #expect(item.orchestration.dispatchId == fixture.binding.dispatchId)
        #expect(item.orchestration.verificationReceiptObjectId == receiptObject.id)
        #expect(item.orchestration.doneObjectId == done.id)
        #expect(item.orchestration.warnings.isEmpty)
    }

    @Test func verifiedCompletionRemainsCompletedAfterRepositoryHeadAdvances() throws {
        let fixture = try boundTask(sourceCommit: "commit-before-ledger-write")
        let receipt = try RepositoryAgentVerificationReceipt(RepositoryAgentVerificationReceipt.Draft(
            canonicalTaskId: fixture.task.id,
            runtimeTaskId: fixture.binding.runtimeTaskId,
            dispatchId: fixture.binding.dispatchId,
            bindingObjectId: fixture.bindingObject.id,
            knowledgeSnapshotHash: fixture.binding.knowledgeSnapshotHash,
            sourceCommit: fixture.binding.sourceCommit,
            checker: "checker:release-gate",
            outcome: .verified,
            checkedAt: Date(timeIntervalSince1970: 20)))
        let receiptObject = try fixture.store.publish(author: receipt.checker, title: "Verification receipt", type: RepositoryAgentVerificationReceipt.objectType, body: try receipt.json(), now: receipt.checkedAt, extras: LedgerPublishExtras(cites: [
                .init(id: fixture.task.id, rel: RepositoryAgentOrchestration.verifiesRelation),
                .init(id: fixture.bindingObject.id, rel: RepositoryAgentOrchestration.verifiesBindingRelation),
            ]))
        _ = try fixture.store.publish(author: "worker", title: "Done", type: "done", body: "finished", now: Date(timeIntervalSince1970: 25), extras: LedgerPublishExtras(cites: [
                .init(id: fixture.task.id, rel: "completes"),
                .init(id: receiptObject.id, rel: RepositoryAgentOrchestration.verifiedByRelation),
            ]))

        let graph = LedgerTaskGraph(
            objects: fixture.store.scan(),
            currentSourceCommit: "commit-containing-binding-receipt-and-done")
        let item = try #require(graph.items.first)

        #expect(graph.isDone(fixture.task.id))
        #expect(item.status == .completed)
        #expect(item.orchestration.state == .verified)
        #expect(!item.orchestration.warnings.contains { $0.code == .sourceCommitStale })
    }

    @Test func exportedOrcaLikeAdapterFixturesDecodeCanonicalAndLegacyNames() throws {
        let task = try fixtureEvent("orca-task-event")
        let dispatch = try fixtureEvent("orca-dispatch-event")
        let workerDone = try fixtureEvent("orca-worker-done-event")
        let checker = try fixtureEvent("orca-checker-event")

        #expect(task.event == .task)
        #expect(task.canonicalTaskId == dispatch.canonicalTaskId)
        #expect(dispatch.event == .dispatch)
        #expect(dispatch.canonicalTaskId == "kbw-content-addressed-task-id")
        #expect(dispatch.knowledgeObjectIds.count == 2)
        #expect(workerDone.event == .workerDone)
        #expect(workerDone.canonicalTaskId == dispatch.canonicalTaskId)
        #expect(workerDone.result == "Focused tests passed; checker verification requested.")
        #expect(checker.event == .checker)
        #expect(checker.outcome == .verified)
    }

    @Test func workerDoneOnlyAwaitsAndDonePreflightFailsUntilVerifiedReceipt() throws {
        let fixture = try boundTask(sourceCommit: "same")
        let event = try RepositoryAgentAdapterEvent(RepositoryAgentAdapterEvent.Draft(
            event: .workerDone,
            canonicalTaskId: fixture.task.id,
            runtimeTaskId: fixture.binding.runtimeTaskId,
            dispatchId: fixture.binding.dispatchId,
            worker: "term_worker",
            result: "implemented",
            occurredAt: Date(timeIntervalSince1970: 20)))
        let workerDone = try RepositoryAgentWorkerDoneReceipt(
            event: event, bindingObjectId: fixture.bindingObject.id)
        let workerDoneObject = try fixture.store.publish(author: "term_worker", title: "worker_done", type: RepositoryAgentWorkerDoneReceipt.objectType, body: try workerDone.json(), now: event.occurredAt, extras: LedgerPublishExtras(cites: [
                .init(id: fixture.task.id, rel: RepositoryAgentOrchestration.reportsWorkerDoneRelation),
                .init(id: fixture.bindingObject.id, rel: RepositoryAgentOrchestration.reportsBindingRelation),
            ]))

        let projection = RepositoryAgentOrchestration.projection(
            task: fixture.task, objects: fixture.store.scan(), currentSourceCommit: "same")
        #expect(projection.state == .awaitingVerification)
        #expect(projection.workerDoneObjectId == workerDoneObject.id)
        #expect(throws: RepositoryAgentOrchestrationError.self) {
            try RepositoryAgentOrchestration.validateCompletion(
                task: fixture.task, receiptObjectId: workerDoneObject.id,
                objects: fixture.store.scan(), currentSourceCommit: "same")
        }

        let receipt = try RepositoryAgentVerificationReceipt(RepositoryAgentVerificationReceipt.Draft(
            canonicalTaskId: fixture.task.id,
            runtimeTaskId: fixture.binding.runtimeTaskId,
            dispatchId: fixture.binding.dispatchId,
            bindingObjectId: fixture.bindingObject.id,
            knowledgeSnapshotHash: fixture.binding.knowledgeSnapshotHash,
            sourceCommit: fixture.binding.sourceCommit,
            checker: "checker", outcome: .verified,
            checkedAt: Date(timeIntervalSince1970: 21)))
        let receiptObject = try fixture.store.publish(author: "checker", title: "verified", type: RepositoryAgentVerificationReceipt.objectType, body: try receipt.json(), now: receipt.checkedAt, extras: LedgerPublishExtras(cites: [
                .init(id: fixture.task.id, rel: RepositoryAgentOrchestration.verifiesRelation),
                .init(id: fixture.bindingObject.id, rel: RepositoryAgentOrchestration.verifiesBindingRelation),
            ]))
        #expect(try RepositoryAgentOrchestration.validateCompletion(
            task: fixture.task, receiptObjectId: receiptObject.id,
            objects: fixture.store.scan(), currentSourceCommit: "same").id == receiptObject.id)
    }

    @Test func capsuleIsDeterministicAndLimitsRulesToEight() throws {
        let fixture = try boundTask(sourceCommit: "same")
        let projection = RepositoryAgentOrchestration.projection(
            task: fixture.task, objects: fixture.store.scan(), currentSourceCommit: "same")
        let first = RepositoryAgentCapsule(
            canonicalTaskId: fixture.task.id, projection: projection)
        let second = RepositoryAgentCapsule(
            canonicalTaskId: fixture.task.id, projection: projection)
        #expect(first == second)
        #expect(first.rulesCapsule.count <= 8)
        #expect(first.canonicalTaskId == fixture.task.id)
        #expect(first.knowledgeSnapshotHash == fixture.binding.knowledgeSnapshotHash)

        #expect(throws: RepositoryAgentOrchestrationError.self) {
            _ = try RepositoryAgentAdapterEvent(RepositoryAgentAdapterEvent.Draft(
                event: .dispatch, canonicalTaskId: "task", runtimeTaskId: "runtime",
                dispatchId: "dispatch", sourceCommit: "commit",
                rulesCapsule: (0...8).map { "rule \($0)" }, occurredAt: Date()))
        }
    }

    @Test func rejectedCheckerReceiptCannotAuthorizeDone() throws {
        let fixture = try boundTask(sourceCommit: "same")
        let receipt = try RepositoryAgentVerificationReceipt(RepositoryAgentVerificationReceipt.Draft(
            canonicalTaskId: fixture.task.id,
            runtimeTaskId: fixture.binding.runtimeTaskId,
            dispatchId: fixture.binding.dispatchId,
            bindingObjectId: fixture.bindingObject.id,
            knowledgeSnapshotHash: fixture.binding.knowledgeSnapshotHash,
            sourceCommit: fixture.binding.sourceCommit,
            checker: "checker", outcome: .rejected,
            checkedAt: Date(timeIntervalSince1970: 20)))
        let receiptObject = try fixture.store.publish(author: "checker", title: "rejected", type: RepositoryAgentVerificationReceipt.objectType, body: try receipt.json(), now: receipt.checkedAt, extras: LedgerPublishExtras(cites: [
                .init(id: fixture.task.id, rel: RepositoryAgentOrchestration.verifiesRelation),
                .init(id: fixture.bindingObject.id, rel: RepositoryAgentOrchestration.verifiesBindingRelation),
            ]))

        #expect(throws: RepositoryAgentOrchestrationError.self) {
            try RepositoryAgentOrchestration.validateCompletion(
                task: fixture.task, receiptObjectId: receiptObject.id,
                objects: fixture.store.scan(), currentSourceCommit: "same")
        }
    }

    @Test func pullMaximumIsClampedAtPublicBoundary() {
        #expect(FleetPull.clampedMaxObjects(-4) == 1)
        #expect(FleetPull.clampedMaxObjects(17) == 17)
        #expect(FleetPull.clampedMaxObjects(10_000) == FleetPull.maxObjectsLimit)
    }

    private func boundTask(sourceCommit: String) throws -> (
        store: LedgerStore,
        task: LedgerObject,
        knowledge: LedgerObject,
        binding: RepositoryAgentTaskBinding,
        bindingObject: LedgerObject
    ) {
        let store = try temporaryStore()
        let knowledge = try store.publish(
            author: "owner", title: "Knowledge v1", type: "decision", body: "v1",
            now: Date(timeIntervalSince1970: 5))
        let task = try store.publish(
            author: "owner", title: "Task", type: "task", body: "work",
            now: Date(timeIntervalSince1970: 10))
        let objectIDs = [knowledge.id]
        let snapshot = RepositoryAgentOrchestration.knowledgeSnapshotHash(
            knowledgeObjectIds: objectIDs, objects: store.scan())
        let binding = try RepositoryAgentTaskBinding(RepositoryAgentTaskBinding.Draft(
            canonicalTaskId: task.id,
            runtimeTaskId: "task_runtime_1",
            dispatchId: "dispatch_1",
            knowledgeObjectIds: objectIDs,
            knowledgeSnapshotHash: snapshot,
            sourceCommit: sourceCommit,
            rulesCapsule: ["Only edit scoped files", "Run focused tests"],
            boundAt: Date(timeIntervalSince1970: 12),
            knowledgeCapturedAt: Date(timeIntervalSince1970: 11)))
        let bindingObject = try store.publish(author: "coordinator", title: "Orca binding", type: RepositoryAgentTaskBinding.objectType, body: try binding.json(), now: binding.boundAt, extras: LedgerPublishExtras(cites: [
                .init(id: task.id, rel: RepositoryAgentOrchestration.bindsRelation),
                .init(id: knowledge.id, rel: RepositoryAgentOrchestration.contextRelation),
            ]))
        return (store, task, knowledge, binding, bindingObject)
    }

    private func temporaryStore() throws -> LedgerStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("kbw-orchestration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return LedgerStore(root: root)
    }

    private func fixtureEvent(_ name: String) throws -> RepositoryAgentAdapterEvent {
        let url = try #require(Bundle.module.url(
            forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try RepositoryAgentAdapterEvent.decode(data: Data(contentsOf: url))
    }
}
