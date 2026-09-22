import Foundation
import Testing

@testable import KnowledgeBaseWikiCore

/// 분류 기준선 계약 — **기준선 이후 발행분만** 3축 분류를 요구한다.
///
/// 전면 게이트를 걸지 않는 이유(실측 2026-08-04): 지식 객체 914개 중 549개가 미분류고,
/// 그중 219개는 사람이 빠뜨린 게 아니라 과거 대량 이주 배치가 안 붙인 것이다. 전면
/// 게이트는 `verify` 를 첫날부터 항상 빨간불로 만들고, 상시 빨간불은 게이트를
/// 무력화한다 — 같은 날 프로모션 봉쇄 위반에서 실제로 그렇게 됐다(위반을 보고도
/// "통과시킨다"고 오독).
///
/// 그리고 분류는 검색 도달과 무관하다(미분류도 FTS 에 잡힌다). 값어치는 정밀도지
/// 도달률이 아니라서, 과거 부채를 급히 갚을 이유가 없다.
@Suite struct ClassificationBaselineTests {
    private func makeWorld() -> LedgerStore {
        LedgerStore(root: FileManager.default.temporaryDirectory
            .appendingPathComponent("kbw-baseline-\(UUID())", isDirectory: true))
    }

    private func declareBaseline(_ store: LedgerStore, since: Date, supersedes: String? = nil) throws -> LedgerObject {
        try store.publish(author: "test", title: "정책: 분류 기준선", type: LedgerClassificationPolicy.objectType, body: LedgerClassificationPolicy.body(since: since, reason: "시험"), extras: LedgerPublishExtras(supersedes: supersedes))
    }

    /// 기준선이 없으면 아무것도 요구하지 않는다.
    @Test func noBaselineRequiresNothing() throws {
        let store = makeWorld()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let object = try store.publish(
            author: "test", title: "근거: 미분류", type: "evidence", body: "본문")

        let policy = LedgerClassificationPolicy.current(objects: store.scan(), store: store)
        #expect(policy.since == nil)
        #expect(!policy.requiresClassification(object))
    }

    /// 기준선 이전 발행은 부채로 남되 게이트에 걸리지 않는다.
    @Test func objectsBeforeBaselineAreNotGated() throws {
        let store = makeWorld()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let old = try store.publish(
            author: "test", title: "근거: 옛것", type: "evidence", body: "본문")
        _ = try declareBaseline(store, since: Date().addingTimeInterval(1))

        let objects = store.scan()
        let policy = LedgerClassificationPolicy.current(objects: objects, store: store)
        #expect(policy.since != nil)
        #expect(!policy.requiresClassification(old))
        #expect(policy.unclassified(objects: objects, classified: []).isEmpty)
    }

    /// 기준선 이후 발행은 분류가 없으면 미달로 잡힌다.
    @Test func objectsAfterBaselineAreGated() throws {
        let store = makeWorld()
        defer { try? FileManager.default.removeItem(at: store.root) }
        _ = try declareBaseline(store, since: Date().addingTimeInterval(-1))
        let fresh = try store.publish(
            author: "test", title: "근거: 새것", type: "evidence", body: "본문")

        let objects = store.scan()
        let policy = LedgerClassificationPolicy.current(objects: objects, store: store)
        let pending = policy.unclassified(objects: objects, classified: [])
        #expect(pending.contains { $0.id == fresh.id })

        // 분류하면 풀린다.
        let cleared = policy.unclassified(objects: objects, classified: [fresh.id])
        #expect(!cleared.contains { $0.id == fresh.id })
    }

    /// 처리 기록(run·screening·policy 자신 등)은 지식이 아니라 요구 대상이 아니다.
    /// 정책 객체가 스스로를 게이트하면 선언하는 순간 위반이 된다.
    @Test func processObjectsAreExempt() throws {
        let store = makeWorld()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let declaration = try declareBaseline(store, since: Date().addingTimeInterval(-1))
        let run = try store.publish(
            author: "test", title: "실행: 야간 작업", type: "run", body: "본문")

        let objects = store.scan()
        let policy = LedgerClassificationPolicy.current(objects: objects, store: store)
        #expect(!policy.requiresClassification(declaration))
        #expect(!policy.requiresClassification(run))
        #expect(policy.unclassified(objects: objects, classified: []).isEmpty)
    }

    /// 기준선은 supersede 로만 옮긴다 — 최신 선언 하나가 유효하다.
    @Test func baselineMovesBySuperseding() throws {
        let store = makeWorld()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let early = Date().addingTimeInterval(-3600)
        let first = try declareBaseline(store, since: early)
        let later = Date().addingTimeInterval(3600)
        let second = try declareBaseline(store, since: later, supersedes: first.id)

        let policy = LedgerClassificationPolicy.current(objects: store.scan(), store: store)
        #expect(policy.declaredBy == second.id)
        // 미래로 옮겼으니 지금 발행분은 요구 대상이 아니다.
        let now = try store.publish(
            author: "test", title: "근거: 지금", type: "evidence", body: "본문")
        #expect(!policy.requiresClassification(now))
    }
}

/// 발행 **전** 초안으로도 판정할 수 있어야 한다 — publish 게이트가 이 형태를 쓴다.
///
/// verify 에만 게이트를 두면 verify 를 안 치는 세션은 그대로 놓친다(실제 사고
/// 2026-08-04 오전). 그래서 발행 시점에 막는데, 그때는 아직 원장에 없는 객체를
/// 판정해야 한다 — id 가 비고 published 가 지금인 초안.
@Suite struct ClassificationDraftGateTests {
    private func makeWorld() -> LedgerStore {
        LedgerStore(root: FileManager.default.temporaryDirectory
            .appendingPathComponent("kbw-draftgate-\(UUID())", isDirectory: true))
    }

    @Test func draftKnowledgeIsGatedBeforePublish() throws {
        let store = makeWorld()
        defer { try? FileManager.default.removeItem(at: store.root) }
        _ = try store.publish(
            author: "test", title: "정책: 분류 기준선",
            type: LedgerClassificationPolicy.objectType,
            body: LedgerClassificationPolicy.body(
                since: Date().addingTimeInterval(-1), reason: "시험"))

        let policy = LedgerClassificationPolicy.current(objects: store.scan(), store: store)
        let draft = LedgerObject(
            id: "0", published: Date(), author: "test",
            title: "근거: 아직 발행 안 함", type: "evidence", body: "본문")
        #expect(policy.requiresClassification(draft))

        // 처리 기록 초안은 막지 않는다 — 실행·철회까지 무겁게 하면 원장 밖으로 샌다.
        let runDraft = LedgerObject(
            id: "0", published: Date(), author: "test",
            title: "실행: 야간 작업", type: "run", body: "본문")
        #expect(!policy.requiresClassification(runDraft))
    }
}
