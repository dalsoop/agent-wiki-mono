import Foundation
import KnowledgeBaseWikiCore
import InteropKit

private func verifyTaskGraph(
    objects: [LedgerObject], repository: RepositoryIdentity?
) -> [LedgerViolation] {
    var violations: [LedgerViolation] = []
    let byID = Dictionary(objects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    var completeCount: [String: Int] = [:]
    for object in objects where object.effectiveType == "done" {
        for cite in object.cites where cite.rel == "completes" {
            completeCount[cite.id, default: 0] += 1
            if let target = byID[cite.id], target.effectiveType != "task" {
                violations.append(.init(id: object.id, problem: "done 이 task 아닌 객체를 완료: \(cite.id.prefix(8))"))
            }
        }
    }
    for (taskID, count) in completeCount where count > 1 {
        violations.append(.init(id: taskID, problem: "task 가 \(count)번 완료됨(중복 done)"))
    }
    let taskGraph = LedgerTaskGraph(objects: objects, currentSourceCommit: repository?.sourceCommit)
    for item in taskGraph.items {
        for warning in item.orchestration.warnings where [
            RepositoryAgentTaskWarning.Code.completionWithoutVerification,
            .verificationMismatch,
            .verificationRejected,
            .malformedBinding,
        ].contains(warning.code) {
            violations.append(.init(
                id: warning.objectId ?? item.taskId,
                problem: "repository-agent gate: \(warning.message)"))
        }
    }
    return violations
}

private func verifyClassificationPolicy(
    store: LedgerStore, objects: [LedgerObject]
) -> [LedgerViolation] {
    let policy = LedgerClassificationPolicy.current(objects: objects, store: store)
    guard policy.since != nil else { return [] }
    let classified = Set(LedgerClassification(objects: objects).domain.keys)
    return policy.unclassified(objects: objects, classified: classified).map {
        .init(id: $0.id,
              problem: "분류 기준선 이후 발행인데 3축 분류 없음 — "
                + "`classify \($0.id.prefix(8)) --domain … --kind … --knowledge … --reason …`")
    }
}

private func verifyIndexFreshness(store: LedgerStore) -> [LedgerViolation] {
    let indexPath = store.root.appendingPathComponent("state/index.db")
    guard FileManager.default.fileExists(atPath: indexPath.path) else { return [] }
    let index = LedgerIndex(root: store.root)
    let objectsDir = store.root.appendingPathComponent("objects")
    guard index.isStale(objectsDir: objectsDir) else { return [] }
    let indexed = index.objectCount()
    let onDisk = index.diskCensus(objectsDir: objectsDir).count
    return [.init(
        id: "index",
        problem: "파생 인덱스가 뒤처짐(인덱스 \(indexed) · 디스크 \(onDisk)) "
            + "— search 도달 불가. `index sync` 로 맞추세요")]
}

public func runVerify(
    store: LedgerStore,
    worlds: [LedgerWorld] = [],
    repository: RepositoryIdentity? = nil
) {
    var violations = store.verify()
    violations.append(contentsOf: PromotionVerifier.verify(
        store: store, peerWorlds: worlds, currentRepository: repository))
    if let checkpointViolations = store.verifyCheckpoint() {
        violations.append(contentsOf: checkpointViolations)
    } else {
        FileHandle.standardError.write(Data("(체크포인트 없음 — `checkpoint` 로 기준점을 만드세요)\n".utf8))
    }
    let objects = store.scan()
    violations.append(contentsOf: verifyTaskGraph(objects: objects, repository: repository))
    if let authorViolations = AuthorAudit.run(root: store.root, objects: objects) {
        violations.append(contentsOf: authorViolations)
    }
    violations.append(contentsOf: verifyClassificationPolicy(store: store, objects: objects))
    violations.append(contentsOf: verifyIndexFreshness(store: store))
    if violations.isEmpty {
        print("이상 없음 (객체 \(objects.count)개, 체크포인트 검사 포함)") // allow:debug
    } else {
        for violation in violations { print("\(violation.id): \(violation.problem)") } // allow:debug
        exit(2)
    }
}

