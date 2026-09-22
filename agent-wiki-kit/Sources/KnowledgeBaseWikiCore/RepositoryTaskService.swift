import Foundation

public enum RepositoryTaskServiceError: Error, CustomStringConvertible, Equatable {
    case objectNotFound(String)
    case ambiguousObject(String)
    case invalidTask(String)
    case repositoryRequired
    case activeBindingRequired(String)
    case bindingIdentityMismatch
    case workerResultTooLarge
    case workerFailureMessageTooLarge

    public var description: String {
        switch self {
        case .objectNotFound(let value): "객체를 찾을 수 없습니다: \(value)"
        case .ambiguousObject(let value): "객체 접두어가 모호합니다: \(value)"
        case .invalidTask(let value): "task 객체가 아닙니다: \(value)"
        case .repositoryRequired: "Git remote가 있는 저장소 world가 필요합니다"
        case .activeBindingRequired(let taskID): "active binding이 없습니다: \(taskID)"
        case .bindingIdentityMismatch: "runtimeTaskId/dispatchId가 active binding과 다릅니다"
        case .workerResultTooLarge: "worker 결과가 16KB 한도를 넘습니다"
        case .workerFailureMessageTooLarge: "worker 실패 메시지가 4KB 한도를 넘습니다"
        }
    }
}

/// 저장소 작업 원장의 단일 쓰기 경로. GUI와 CLI 모두 이 서비스를 호출한다.
public struct RepositoryTaskService: Sendable {
    public struct BindingResult: Sendable {
        public let object: LedgerObject
        public let binding: RepositoryAgentTaskBinding
    }

    public struct VerificationResult: Sendable {
        public let object: LedgerObject
        public let receipt: RepositoryAgentVerificationReceipt
    }

    public struct WorkerDoneResult: Sendable {
        public let object: LedgerObject
        public let receipt: RepositoryAgentWorkerDoneReceipt
    }

    public struct WorkerFailureResult: Sendable {
        public let object: LedgerObject
        public let receipt: RepositoryAgentWorkerFailureReceipt
    }

    public let store: LedgerStore
    public let repository: RepositoryIdentity?
    public let author: String

    public init(store: LedgerStore, repository: RepositoryIdentity?, author: String) {
        self.store = store
        self.repository = repository
        self.author = author
    }

    @discardableResult
    public func createTask(title: String, body: String, now: Date = Date()) throws -> LedgerObject {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { throw RepositoryTaskServiceError.invalidTask("빈 제목") }
        let cleanBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return try store.publish(
            author: author,
            title: cleanTitle,
            type: "task",
            body: cleanBody.isEmpty ? cleanTitle : cleanBody,
            now: now)
    }

    @discardableResult
    public func handoff(
        taskID: String,
        assignee: String,
        note: String = "",
        now: Date = Date()
    ) throws -> LedgerObject {
        let task = try resolveTask(taskID)
        let cleanAssignee = assignee.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanAssignee.isEmpty else { throw RepositoryTaskServiceError.invalidTask("빈 담당 역할") }
        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return try store.publish(author: author, title: "위임: \(task.title ?? String(task.id.prefix(8)))", type: "handoff", body: "위임 → \(cleanAssignee)" + (cleanNote.isEmpty ? "" : "\n\n\(cleanNote)"), now: now, extras: LedgerPublishExtras(cites: [.init(id: task.id, rel: "delegates")]))
    }

    public func bind(
        taskID: String,
        runtimeTaskID: String,
        dispatchID: String,
        knowledgeObjectIDs: [String] = [],
        rules: [String] = [],
        now: Date = Date()
    ) throws -> BindingResult {
        guard let repository else { throw RepositoryTaskServiceError.repositoryRequired }
        let task = try resolveTask(taskID)
        let objects = store.scan()
        let knowledgeIDs = try knowledgeObjectIDs.map { try resolve($0, objects: objects).id }
        let binding = try RepositoryAgentTaskBinding(RepositoryAgentTaskBinding.Draft(
            canonicalTaskId: task.id,
            runtimeTaskId: runtimeTaskID,
            dispatchId: dispatchID,
            knowledgeObjectIds: knowledgeIDs,
            knowledgeSnapshotHash: RepositoryAgentOrchestration.knowledgeSnapshotHash(
                knowledgeObjectIds: knowledgeIDs,
                objects: objects),
            sourceCommit: repository.sourceCommit,
            rulesCapsule: rules,
            boundAt: now,
            knowledgeCapturedAt: now))
        let previous = RepositoryAgentOrchestration.activeBinding(
            canonicalTaskId: task.id,
            objects: objects)?.object
        let object = try store.publish(author: author, title: "Runtime binding: \(task.title ?? String(task.id.prefix(8)))", type: RepositoryAgentTaskBinding.objectType, body: try binding.json(), now: now, extras: LedgerPublishExtras(cites: [.init(id: task.id, rel: RepositoryAgentOrchestration.bindsRelation)]
                + knowledgeIDs.map { .init(id: $0, rel: RepositoryAgentOrchestration.contextRelation) }, supersedes: previous?.id))
        return BindingResult(object: object, binding: binding)
    }

    public func recordWorkerDone(
        taskID: String,
        runtimeTaskID: String,
        dispatchID: String,
        worker: String,
        result: String,
        now: Date = Date()
    ) throws -> WorkerDoneResult {
        guard result.lengthOfBytes(using: .utf8) <= RepositoryAgentAdapterEvent.maxResultUTF8Bytes else {
            throw RepositoryTaskServiceError.workerResultTooLarge
        }
        let task = try resolveTask(taskID)
        let objects = store.scan()
        guard let active = RepositoryAgentOrchestration.activeBinding(
            canonicalTaskId: task.id,
            objects: objects)
        else { throw RepositoryTaskServiceError.activeBindingRequired(task.id) }
        guard active.binding.runtimeTaskId == runtimeTaskID,
              active.binding.dispatchId == dispatchID
        else { throw RepositoryTaskServiceError.bindingIdentityMismatch }
        let event = try RepositoryAgentAdapterEvent(RepositoryAgentAdapterEvent.Draft(
            event: .workerDone,
            canonicalTaskId: task.id,
            runtimeTaskId: runtimeTaskID,
            dispatchId: dispatchID,
            worker: worker,
            result: result,
            bindingObjectId: active.object.id,
            occurredAt: now))
        let receipt = try RepositoryAgentWorkerDoneReceipt(
            event: event,
            bindingObjectId: active.object.id)
        let object = try store.publish(author: worker, title: "Worker done (verification pending): \(task.title ?? String(task.id.prefix(8)))", type: RepositoryAgentWorkerDoneReceipt.objectType, body: try receipt.json(), now: now, extras: LedgerPublishExtras(cites: [
                .init(id: task.id, rel: RepositoryAgentOrchestration.reportsWorkerDoneRelation),
                .init(id: active.object.id, rel: RepositoryAgentOrchestration.reportsBindingRelation),
            ]))
        return WorkerDoneResult(object: object, receipt: receipt)
    }

    public func recordWorkerFailure(
        taskID: String,
        runtimeTaskID: String,
        dispatchID: String,
        worker: String,
        exitCode: Int32,
        message: String,
        now: Date = Date()
    ) throws -> WorkerFailureResult {
        let cleanWorker = worker.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanWorker.isEmpty else {
            throw RepositoryTaskServiceError.invalidTask("빈 worker")
        }
        guard !cleanMessage.isEmpty else {
            throw RepositoryTaskServiceError.invalidTask("빈 실패 메시지")
        }
        guard cleanMessage.lengthOfBytes(using: .utf8)
                <= RepositoryAgentWorkerFailureReceipt.maxMessageUTF8Bytes else {
            throw RepositoryTaskServiceError.workerFailureMessageTooLarge
        }
        let task = try resolveTask(taskID)
        let objects = store.scan()
        guard let active = RepositoryAgentOrchestration.activeBinding(
            canonicalTaskId: task.id,
            objects: objects)
        else { throw RepositoryTaskServiceError.activeBindingRequired(task.id) }
        guard active.binding.runtimeTaskId == runtimeTaskID,
              active.binding.dispatchId == dispatchID
        else { throw RepositoryTaskServiceError.bindingIdentityMismatch }
        let receipt = RepositoryAgentWorkerFailureReceipt(RepositoryAgentWorkerFailureReceipt.Draft(
            canonicalTaskId: task.id,
            runtimeTaskId: runtimeTaskID,
            dispatchId: dispatchID,
            bindingObjectId: active.object.id,
            worker: cleanWorker,
            exitCode: exitCode,
            message: cleanMessage,
            failedAt: now))
        let object = try store.publish(author: cleanWorker, title: "Worker failed (retry available): \(task.title ?? String(task.id.prefix(8)))", type: RepositoryAgentWorkerFailureReceipt.objectType, body: try receipt.json(), now: now, extras: LedgerPublishExtras(cites: [
                .init(id: task.id, rel: RepositoryAgentOrchestration.reportsWorkerFailureRelation),
                .init(id: active.object.id, rel: RepositoryAgentOrchestration.reportsBindingRelation),
            ]))
        return WorkerFailureResult(object: object, receipt: receipt)
    }

    public func verify(
        taskID: String,
        checker: String,
        outcome: RepositoryAgentVerificationReceipt.Outcome,
        now: Date = Date()
    ) throws -> VerificationResult {
        let task = try resolveTask(taskID)
        let objects = store.scan()
        guard let active = RepositoryAgentOrchestration.activeBinding(
            canonicalTaskId: task.id,
            objects: objects)
        else { throw RepositoryTaskServiceError.activeBindingRequired(task.id) }
        let projection = RepositoryAgentOrchestration.projection(
            task: task,
            objects: objects,
            currentSourceCommit: repository?.sourceCommit)
        guard projection.workerDoneObjectId != nil else {
            throw RepositoryTaskServiceError.invalidTask("worker_done 기록 전에는 checker 검증할 수 없습니다")
        }
        let receipt = try RepositoryAgentVerificationReceipt(RepositoryAgentVerificationReceipt.Draft(
            canonicalTaskId: task.id,
            runtimeTaskId: active.binding.runtimeTaskId,
            dispatchId: active.binding.dispatchId,
            bindingObjectId: active.object.id,
            knowledgeSnapshotHash: active.binding.knowledgeSnapshotHash,
            sourceCommit: active.binding.sourceCommit,
            checker: checker,
            outcome: outcome,
            checkedAt: now))
        let object = try store.publish(author: checker, title: "Verification \(outcome.rawValue): \(task.title ?? String(task.id.prefix(8)))", type: RepositoryAgentVerificationReceipt.objectType, body: try receipt.json(), now: now, extras: LedgerPublishExtras(cites: [
                .init(id: task.id, rel: RepositoryAgentOrchestration.verifiesRelation),
                .init(id: active.object.id, rel: RepositoryAgentOrchestration.verifiesBindingRelation),
            ]))
        return VerificationResult(object: object, receipt: receipt)
    }

    @discardableResult
    public func complete(
        taskID: String,
        verificationReceiptID: String,
        result: String,
        now: Date = Date()
    ) throws -> LedgerObject {
        let task = try resolveTask(taskID)
        let objects = store.scan()
        let receipt = try resolve(verificationReceiptID, objects: objects)
        try RepositoryAgentOrchestration.validateCompletion(
            task: task,
            receiptObjectId: receipt.id,
            objects: objects,
            currentSourceCommit: repository?.sourceCommit)
        let cleanResult = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return try store.publish(author: author, title: "완료: \(task.title ?? String(task.id.prefix(8)))", type: "done", body: cleanResult.isEmpty ? "완료." : cleanResult, now: now, extras: LedgerPublishExtras(cites: [
                .init(id: task.id, rel: "completes"),
                .init(id: receipt.id, rel: RepositoryAgentOrchestration.verifiedByRelation),
            ]))
    }

    /// 완료 작업에서 얻은 재사용 지식을 repo 원장에 먼저 발행한다. gujo 승격은 별도 확인 단계다.
    @discardableResult
    public func publishKnowledgeCandidate(
        taskID: String,
        title: String,
        body: String,
        now: Date = Date()
    ) throws -> LedgerObject {
        let task = try resolveTask(taskID)
        let projection = RepositoryAgentOrchestration.projection(
            task: task,
            objects: store.scan(),
            currentSourceCommit: repository?.sourceCommit)
        guard projection.doneObjectId != nil else {
            throw RepositoryTaskServiceError.invalidTask("검증 완료된 작업만 노하우 후보를 만들 수 있습니다")
        }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, !cleanBody.isEmpty else {
            throw RepositoryTaskServiceError.invalidTask("노하우 제목과 본문이 필요합니다")
        }
        var cites: [LedgerObject.Cite] = [.init(id: task.id, rel: "learned-from-task")]
        if let workerDone = projection.workerDoneObjectId {
            cites.append(.init(id: workerDone, rel: "distills-worker-result"))
        }
        return try store.publish(author: author, title: cleanTitle, type: "knowledge", body: cleanBody, now: now, extras: LedgerPublishExtras(cites: cites, tags: ["promotion-candidate", "repository-learning"]))
    }

    public func resolveTask(_ prefix: String) throws -> LedgerObject {
        let object = try resolve(prefix, objects: store.scan())
        guard object.effectiveType == "task" else {
            throw RepositoryTaskServiceError.invalidTask(object.id)
        }
        return object
    }

    private func resolve(_ prefix: String, objects: [LedgerObject]) throws -> LedgerObject {
        if let exact = objects.first(where: { $0.id == prefix }) { return exact }
        let matches = objects.filter { $0.id.hasPrefix(prefix.lowercased()) }
        if matches.isEmpty { throw RepositoryTaskServiceError.objectNotFound(prefix) }
        if matches.count > 1 { throw RepositoryTaskServiceError.ambiguousObject(prefix) }
        return matches[0]
    }
}
