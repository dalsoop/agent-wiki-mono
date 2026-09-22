import Foundation

extension RepositoryAgentOrchestration {
    public static func projection(
        task: LedgerObject,
        objects: [LedgerObject],
        currentSourceCommit: String? = nil
    ) -> RepositoryAgentTaskProjection {
        let ordered = objects.sorted { ($0.published, $0.id) < ($1.published, $1.id) }
        let doneObjects = ordered.filter {
            $0.effectiveType == "done"
                && $0.cites.contains { $0.id == task.id && $0.rel == "completes" }
        }
        let bindingObjects = ordered.filter { object in
            object.effectiveType == RepositoryAgentTaskBinding.objectType
                && object.cites.contains { $0.id == task.id && $0.rel == bindsRelation }
        }
        let decodedBindings = bindingObjects.compactMap { object -> (LedgerObject, RepositoryAgentTaskBinding)? in
            guard let binding = RepositoryAgentTaskBinding.decode(body: object.body),
                  binding.canonicalTaskId == task.id else { return nil }
            return (object, binding)
        }
        let supersededBindingIDs = Set(bindingObjects.compactMap(\.supersedes))
        let activeBinding = decodedBindings
            .filter { !supersededBindingIDs.contains($0.0.id) }
            .last ?? decodedBindings.last

        guard let (bindingObject, binding) = activeBinding else {
            var warnings: [RepositoryAgentTaskWarning] = []
            if !bindingObjects.isEmpty {
                warnings.append(.init(
                    code: .malformedBinding,
                    message: "runtime binding JSON/schema 또는 taskId가 유효하지 않습니다.",
                    objectId: bindingObjects.last?.id,
                    supersededByObjectId: nil))
            }
            if !doneObjects.isEmpty {
                warnings.append(.init(
                    code: .completionWithoutVerification,
                    message: "legacy done/worker_done은 보존되지만 checker receipt 없이는 완료가 아닙니다.",
                    objectId: doneObjects.last?.id,
                    supersededByObjectId: nil))
            }
            return emptyProjection(
                canonicalTaskId: task.id, state: .unbound, warnings: sorted(warnings))
        }

        let currentHash = knowledgeSnapshotHash(
            knowledgeObjectIds: binding.knowledgeObjectIds, objects: objects)
        var warnings: [RepositoryAgentTaskWarning] = []
        if let currentSourceCommit, !currentSourceCommit.isEmpty,
           currentSourceCommit != binding.sourceCommit {
            warnings.append(.init(
                code: .sourceCommitStale,
                message: "binding sourceCommit \(binding.sourceCommit) != 현재 \(currentSourceCommit)",
                objectId: bindingObject.id,
                supersededByObjectId: nil))
        }
        if currentHash != binding.knowledgeSnapshotHash {
            warnings.append(.init(
                code: .knowledgeSnapshotMismatch,
                message: "지식 snapshot hash가 현재 lineage heads와 다릅니다.",
                objectId: bindingObject.id,
                supersededByObjectId: nil))
        }
        for id in binding.knowledgeObjectIds.sorted() {
            guard let object = objects.first(where: { $0.id == id }) else { continue }
            let head = lineageHead(startingAt: object, objects: objects)
            if head.id != id {
                warnings.append(.init(
                    code: .knowledgeSuperseded,
                    message: "지식 \(id) 판이 \(head.id)로 supersede 됐습니다.",
                    objectId: id,
                    supersededByObjectId: head.id))
            }
        }

        let receiptObjects = ordered.filter {
            $0.effectiveType == RepositoryAgentVerificationReceipt.objectType
        }
        var validDone: (done: LedgerObject, receiptObject: LedgerObject)?
        for done in doneObjects {
            for cite in done.cites where cite.rel == verifiedByRelation {
                guard let receiptObject = receiptObjects.first(where: { $0.id == cite.id }),
                      let receipt = RepositoryAgentVerificationReceipt.decode(body: receiptObject.body)
                else { continue }
                let identityMatches = receipt.canonicalTaskId == task.id
                    && receipt.runtimeTaskId == binding.runtimeTaskId
                    && receipt.dispatchId == binding.dispatchId
                    && receipt.bindingObjectId == bindingObject.id
                    && receipt.knowledgeSnapshotHash == binding.knowledgeSnapshotHash
                    && receipt.sourceCommit == binding.sourceCommit
                    && receiptObject.cites.contains { $0.id == task.id && $0.rel == verifiesRelation }
                    && receiptObject.cites.contains { $0.id == bindingObject.id && $0.rel == verifiesBindingRelation }
                guard identityMatches else {
                    warnings.append(.init(
                        code: .verificationMismatch,
                        message: "verification receipt의 task/runtime/dispatch/context identity가 binding과 다릅니다.",
                        objectId: receiptObject.id,
                        supersededByObjectId: nil))
                    continue
                }
                guard receipt.outcome == .verified else {
                    warnings.append(.init(
                        code: .verificationRejected,
                        message: "checker가 이 dispatch 완료를 거부했습니다.",
                        objectId: receiptObject.id,
                        supersededByObjectId: nil))
                    continue
                }
                validDone = (done, receiptObject)
            }
        }
        if !doneObjects.isEmpty, validDone == nil,
           !warnings.contains(where: { $0.code == .verificationRejected || $0.code == .verificationMismatch }) {
            warnings.append(.init(
                code: .completionWithoutVerification,
                message: "done은 checker/gate verification receipt를 인용해야 완료됩니다.",
                objectId: doneObjects.last?.id,
                supersededByObjectId: nil))
        }

        // sourceCommit/snapshot freshness is a completion-time gate. Once a matching checker
        // receipt and done object have closed the task, the commit that records those immutable
        // ledger objects necessarily advances HEAD and must not reopen the completed task.
        if validDone != nil {
            warnings.removeAll {
                $0.code == .sourceCommitStale
                    || $0.code == .knowledgeSnapshotMismatch
                    || $0.code == .knowledgeSuperseded
            }
        }

        let isStale = warnings.contains {
            $0.code == .sourceCommitStale
                || $0.code == .knowledgeSnapshotMismatch
                || $0.code == .knowledgeSuperseded
        }
        let workerDoneObject = ordered.last { object in
            guard object.effectiveType == RepositoryAgentWorkerDoneReceipt.objectType,
                  let receipt = RepositoryAgentWorkerDoneReceipt.decode(body: object.body)
            else { return false }
            return receipt.canonicalTaskId == task.id
                && receipt.runtimeTaskId == binding.runtimeTaskId
                && receipt.dispatchId == binding.dispatchId
                && receipt.bindingObjectId == bindingObject.id
                && object.cites.contains { $0.id == task.id && $0.rel == reportsWorkerDoneRelation }
                && object.cites.contains { $0.id == bindingObject.id && $0.rel == reportsBindingRelation }
        }
        let workerFailure = ordered.compactMap { object -> (LedgerObject, RepositoryAgentWorkerFailureReceipt)? in
            guard object.effectiveType == RepositoryAgentWorkerFailureReceipt.objectType,
                  let receipt = RepositoryAgentWorkerFailureReceipt.decode(body: object.body),
                  receipt.canonicalTaskId == task.id,
                  receipt.runtimeTaskId == binding.runtimeTaskId,
                  receipt.dispatchId == binding.dispatchId,
                  receipt.bindingObjectId == bindingObject.id,
                  object.cites.contains(where: { $0.id == task.id && $0.rel == reportsWorkerFailureRelation }),
                  object.cites.contains(where: { $0.id == bindingObject.id && $0.rel == reportsBindingRelation })
            else { return nil }
            return (object, receipt)
        }.last
        let latestWorkerObject = [workerDoneObject, workerFailure?.0]
            .compactMap { $0 }
            .sorted { ($0.published, $0.id) < ($1.published, $1.id) }
            .last
        let latestIsDone = latestWorkerObject?.effectiveType == RepositoryAgentWorkerDoneReceipt.objectType
        let latestFailure = latestWorkerObject?.effectiveType == RepositoryAgentWorkerFailureReceipt.objectType
            ? workerFailure
            : nil
        let state: RepositoryAgentTaskProjection.State
        if validDone != nil {
            state = .verified
        } else if isStale {
            state = .stale
        } else if latestIsDone {
            state = .awaitingVerification
        } else if latestFailure != nil {
            state = .executionFailed
        } else {
            state = .awaitingWorker
        }
        return RepositoryAgentTaskProjection(
            schemaVersion: projectionSchemaVersion,
            canonicalTaskId: task.id,
            state: state,
            bindingObjectId: bindingObject.id,
            runtimeTaskId: binding.runtimeTaskId,
            dispatchId: binding.dispatchId,
            knowledgeObjectIds: binding.knowledgeObjectIds,
            knowledgeSnapshotHash: binding.knowledgeSnapshotHash,
            currentKnowledgeSnapshotHash: currentHash,
            sourceCommit: binding.sourceCommit,
            rulesCapsule: Array(binding.rulesCapsule.prefix(RepositoryAgentTaskBinding.maxRuleCount)),
            boundAt: binding.boundAt,
            knowledgeCapturedAt: binding.knowledgeCapturedAt,
            verificationReceiptObjectId: validDone?.receiptObject.id,
            workerDoneObjectId: (validDone != nil || latestIsDone) ? workerDoneObject?.id : nil,
            workerFailureObjectId: latestFailure?.0.id,
            workerFailureExitCode: latestFailure?.1.exitCode,
            workerFailureMessage: latestFailure?.1.message,
            doneObjectId: validDone?.done.id,
            warnings: sorted(warnings))
    }

    static func lineageHead(
        startingAt object: LedgerObject,
        objects: [LedgerObject]
    ) -> LedgerObject {
        var current = object
        var seen: Set<String> = []
        while !seen.contains(current.id) {
            seen.insert(current.id)
            guard let successor = objects
                .filter({ $0.supersedes == current.id })
                .sorted(by: { ($0.published, $0.id) < ($1.published, $1.id) })
                .last else { break }
            current = successor
        }
        return current
    }

    private static func emptyProjection(
        canonicalTaskId: String,
        state: RepositoryAgentTaskProjection.State,
        warnings: [RepositoryAgentTaskWarning]
    ) -> RepositoryAgentTaskProjection {
        RepositoryAgentTaskProjection(
            schemaVersion: projectionSchemaVersion,
            canonicalTaskId: canonicalTaskId,
            state: state,
            bindingObjectId: nil,
            runtimeTaskId: nil,
            dispatchId: nil,
            knowledgeObjectIds: [],
            knowledgeSnapshotHash: nil,
            currentKnowledgeSnapshotHash: nil,
            sourceCommit: nil,
            rulesCapsule: [],
            boundAt: nil,
            knowledgeCapturedAt: nil,
            verificationReceiptObjectId: nil,
            workerDoneObjectId: nil,
            workerFailureObjectId: nil,
            workerFailureExitCode: nil,
            workerFailureMessage: nil,
            doneObjectId: nil,
            warnings: warnings)
    }

}
