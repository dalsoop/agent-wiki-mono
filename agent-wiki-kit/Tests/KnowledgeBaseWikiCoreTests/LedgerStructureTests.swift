import Foundation
import Testing

@testable import KnowledgeBaseWikiCore

/// 구조 진단의 계약 — 수치는 실측이고, 판정은 기준선(contract)이 정한다.
///
/// 실사고(2026-08-04): `blob gc` 가 reachable 을 **사건 source 만**으로 잡아서, md 객체가
/// 참조하는 원본 26개(12.2 MB)가 통째로 회수 대상이었다. blob 은 정본이라 지우면 복구할
/// 길이 없다. 층은 다 있는데 층 사이 배선이 빠지면 아무 명령도 실패하지 않고 조용히
/// 어긋난다 — 그래서 간선을 센다.
@Suite struct LedgerStructureTests {
    private func makeWorld() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("kbw-structure-\(UUID())", isDirectory: true)
    }

    /// 원본이 typed 참조(`source.blob`)로 걸려 있으면 gc 도달 간선이 충족이다.
    @Test func typedBlobReferenceCountsAsReachable() throws {
        let root = makeWorld()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LedgerStore(root: root)
        let sha = try BlobStore(root: root).put(Data("원문 바이트".utf8))

        var provenance = Provenance()
        provenance.blob = sha
        _ = try store.publish(author: "test", title: "근거: typed 참조", type: "evidence", body: "본문", extras: LedgerPublishExtras(source: provenance))

        let structure = LedgerStructure(root: root)
        let reachable = try #require(structure.edges.first { $0.id == "blob-reachable" })
        #expect(reachable.actual == 1)
        #expect(reachable.total == 1)
        #expect(reachable.status == .satisfied)
        #expect(reachable.contract == .invariant)
    }

    /// 본문에만 sha 를 적어두면 기계는 못 따라간다 — typed 간선이 미달로 잡혀야 한다.
    @Test func bodyOnlyReferenceIsNotTyped() throws {
        let root = makeWorld()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LedgerStore(root: root)
        let sha = try BlobStore(root: root).put(Data("원문 바이트 둘".utf8))
        _ = try store.publish(
            author: "test", title: "근거: 본문 언급", type: "evidence",
            body: "그림은 여기 [blob: \(sha)] 에 있다.")

        let structure = LedgerStructure(root: root)
        let typed = try #require(structure.edges.first { $0.id == "blob-typed" })
        let body = try #require(structure.edges.first { $0.id == "blob-body" })

        #expect(typed.actual == 0)          // 기계 참조 없음
        #expect(typed.status == .missing)
        #expect(body.actual == 1)           // 사람 참조는 있음
        #expect(body.contract == .informational)  // 관측만 — 미달로 세지 않는다
        #expect(!structure.breaches.contains { $0.id == "blob-body" })
    }

    /// 관측(informational) 간선은 미달 목록에도, 완성도 분모에도 들어가지 않는다.
    @Test func informationalEdgesDoNotCountTowardCompletion() throws {
        let root = makeWorld()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try LedgerStore(root: root).publish(
            author: "test", title: "근거: 완성도 분모", type: "evidence", body: "본문")

        let structure = LedgerStructure(root: root)
        let required = structure.edges.filter { $0.contract != .informational }
        #expect(structure.completion.required == required.count)
        #expect(structure.breaches.allSatisfy { $0.contract != .informational })
    }

    /// invariant 위반이 goal 미달보다 먼저 온다 — 화면 상단이 곧 우선순위다.
    @Test func breachesRankInvariantsFirst() throws {
        let root = makeWorld()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LedgerStore(root: root)
        // 아무도 안 가리키는 원본 — invariant(gc 도달) 위반을 만든다.
        _ = try BlobStore(root: root).put(Data("고아 원본".utf8))
        _ = try store.publish(author: "test", title: "근거: 순위", type: "evidence", body: "본문")

        let structure = LedgerStructure(root: root)
        let breaches = structure.breaches
        #expect(breaches.first?.id == "blob-reachable")
        #expect(breaches.first?.contract == .invariant)
    }
}

/// 미분류 백로그가 **목록**으로 나온다는 계약.
///
/// 숫자만 보여주는 화면은 진단에서 멈춘다 — 어떤 객체인지 알아야 처치로 이어진다.
/// 게이트 위반(기준선 이후)이 부채(기준선 이전)보다 먼저 온다: 위반은 지금 막아야
/// 하는 것이고 부채는 갚으면 좋은 것이라 무게가 다르다.
@Suite struct StructureBacklogTests {
    private func makeWorld() -> LedgerStore {
        LedgerStore(root: FileManager.default.temporaryDirectory
            .appendingPathComponent("kbw-backlog-\(UUID())", isDirectory: true))
    }

    @Test func gatedItemsComeBeforeLegacyDebt() throws {
        let store = makeWorld()
        defer { try? FileManager.default.removeItem(at: store.root) }
        // 시각을 명시한다. `Date()` 세 번은 같은 밀리초에 떨어질 수 있어, 전체 실행
        // 부하에서만 터지는 경합이 된다(실측: 격리 3회 통과·전체 1회 실패).
        let baseline = Date()
        let old = try store.publish(
            author: "test", title: "근거: 옛 부채", type: "evidence", body: "본문",
            now: baseline.addingTimeInterval(-60))
        _ = try store.publish(
            author: "test", title: "정책: 분류 기준선",
            type: LedgerClassificationPolicy.objectType,
            body: LedgerClassificationPolicy.body(since: baseline, reason: "시험"),
            now: baseline)
        // 기준선 이후 — 게이트 위반
        let fresh = try store.publish(
            author: "test", title: "근거: 새 위반", type: "evidence", body: "본문",
            now: baseline.addingTimeInterval(60))

        let structure = LedgerStructure(root: store.root)
        let ids = structure.pending.map(\.id)
        #expect(ids.contains(fresh.id))
        #expect(ids.contains(old.id))
        #expect(ids.firstIndex(of: fresh.id)! < ids.firstIndex(of: old.id)!)
        #expect(structure.pending.first { $0.id == fresh.id }?.gated == true)
        #expect(structure.pending.first { $0.id == old.id }?.gated == false)
    }

    /// 분류된 객체는 **분류 축** 백로그에서 빠진다.
    /// (인용 고립은 별개 축이라 남을 수 있다 — 두 부채는 서로 대신하지 못한다.)
    @Test func classifiedObjectsLeaveTheBacklog() throws {
        let store = makeWorld()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let object = try store.publish(
            author: "test", title: "근거: 분류됨", type: "evidence", body: "본문")
        #expect(LedgerStructure(root: store.root).pending
            .contains { $0.id == object.id && $0.lack == .classification })

        let classification = try #require(LedgerClassificationInput(
            domain: "dev-workflow", kind: "runbook", knowledge: "tech", reason: "시험"))
        _ = try store.publishScreening(
            author: "test", target: object, classification: classification, batch: nil)
        #expect(!LedgerStructure(root: store.root).pending
            .contains { $0.id == object.id && $0.lack == .classification })
    }
}

/// 인용 고립 계약 — 원장 안에 있어도 **걸어서 닿을 수 없는** 지식을 센다.
///
/// 기준선 평가(gujo wiki `ee696d03`, 2026-08-03)가 355개(24.4%)로 지적한 축이다.
/// 인용이 하나도 없으면 이름을 정확히 아는 검색으로만 닿고, 관련 근거를 따라
/// 걷다가는 절대 만날 수 없다. 분류와는 별개 부채다 — 분류가 돼 있어도 고립될 수 있다.
@Suite struct CitationIsolationTests {
    private func makeStore() -> LedgerStore {
        LedgerStore(root: FileManager.default.temporaryDirectory
            .appendingPathComponent("kbw-isolation-\(UUID())", isDirectory: true))
    }

    @Test func objectWithNoCitationIsCountedIsolated() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let anchor = try store.publish(
            author: "test", title: "개념: 상위 개념", type: "concept", body: "본문")
        _ = try store.publish(author: "test", title: "근거: 이어진 것", type: "evidence", body: "본문", extras: LedgerPublishExtras(cites: [.init(id: anchor.id, rel: "references")]))
        let lonely = try store.publish(
            author: "test", title: "근거: 고립된 것", type: "evidence", body: "본문")

        let structure = LedgerStructure(root: store.root)
        let edge = try #require(structure.edges.first { $0.id == "citation-reach" })
        #expect(edge.total == 3)
        #expect(edge.actual == 2)          // anchor 와 인용한 객체는 이어졌다
        #expect(edge.contract == .goal)

        let isolated = structure.pending.filter { $0.lack == .citation }.map(\.id)
        #expect(isolated == [lonely.id])
    }

    /// 인용을 **받기만** 해도 이어진 것으로 본다 — 방향은 상관없다.
    @Test func beingCitedCountsAsConnected() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let target = try store.publish(
            author: "test", title: "근거: 인용당함", type: "evidence", body: "본문")
        _ = try store.publish(author: "test", title: "개념: 가리키는 쪽", type: "concept", body: "본문", extras: LedgerPublishExtras(cites: [.init(id: target.id, rel: "references")]))

        let structure = LedgerStructure(root: store.root)
        #expect(structure.pending.filter { $0.lack == .citation }.isEmpty)
    }

    /// 분류돼 있어도 고립일 수 있다 — 두 부채는 서로 대신하지 못한다.
    @Test func classifiedObjectCanStillBeIsolated() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let object = try store.publish(
            author: "test", title: "근거: 분류됐지만 고립", type: "evidence", body: "본문")
        let classification = try #require(LedgerClassificationInput(
            domain: "dev-workflow", kind: "runbook", knowledge: "tech", reason: "시험"))
        _ = try store.publishScreening(
            author: "test", target: object, classification: classification, batch: nil)

        let structure = LedgerStructure(root: store.root)
        let lacks = structure.pending.filter { $0.id == object.id }.map(\.lack)
        #expect(!lacks.contains(.classification))   // 분류는 됐고
        #expect(lacks.contains(.citation))          // 고립은 남았다
    }
}
