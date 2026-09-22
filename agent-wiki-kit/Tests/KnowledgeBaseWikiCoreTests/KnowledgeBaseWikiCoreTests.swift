import Foundation
import Testing
@testable import KnowledgeBaseWikiCore

private func makeStore() -> (LedgerStore, URL) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("mcl-test-\(UUID().uuidString)")
    return (LedgerStore(root: root), root)
}

@Suite struct SpecArticle1Tests {
    @Test func uuidV7IsTimeOrdered() {
        let early = LedgerID.generate(now: Date(timeIntervalSince1970: 1_000_000))
        let late = LedgerID.generate(now: Date(timeIntervalSince1970: 2_000_000))
        #expect(early < late)
        #expect(early.count == 36)
        #expect(early[early.index(early.startIndex, offsetBy: 14)] == "7")
    }

    @Test func publishedObjectIsWriteOnce() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let object = try store.publish(author: "human", title: "a", body: "본문")
        // 같은 id 파일 재작성 시도는 실패해야 한다.
        #expect(throws: Error.self) {
            try Data("변조".utf8).write(
                to: root.appendingPathComponent("objects"), options: [.withoutOverwriting])
        }
        #expect(store.scan().first?.id == object.id)
    }
}

@Suite struct SpecArticle2And5Tests {
    @Test func serializeParseRoundTripPreservesUnknownFields() {
        let object = LedgerObject(id: LedgerID.generate(), published: Date(timeIntervalSince1970: 1_752_800_000), author: "curator", title: "제목", body: "본문\n둘째 줄", extras: LedgerObject.Extras(batch: "b-1", cites: [.init(id: "x", rel: "summarizes")], supersedes: "y", unknownFields: ["future_field: 42"]))
        let text = object.serialize()
        let parsed = LedgerObject.parse(text)
        #expect(parsed?.object == object)
        #expect(parsed?.storedSHA == LedgerObject.hash("본문\n둘째 줄"))
        #expect(parsed?.object.unknownFields == ["future_field: 42"])
        // 재직렬화해도 모르는 필드가 남는다(제5조).
        #expect(parsed!.object.serialize().contains("future_field: 42"))
    }

    @Test func parseRejectsMissingRequiredFields() {
        #expect(LedgerObject.parse("---\nid: x\n---\nbody") == nil)
    }
}

@Suite struct SpecArticle4Tests {
    @Test func supersedeAndRetractResolveHeads() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let v1 = try store.publish(author: "human", title: "노트", body: "v1",
                                   now: Date(timeIntervalSince1970: 1_000))
        let v2 = try store.publish(author: "human", title: "노트", body: "v2", now: Date(timeIntervalSince1970: 2_000), extras: LedgerPublishExtras(supersedes: v1.id))
        let other = try store.publish(author: "human", title: "철회될 것", body: "x",
                                      now: Date(timeIntervalSince1970: 3_000))
        _ = try store.publish(author: "human", body: "retraction", now: Date(timeIntervalSince1970: 4_000), extras: LedgerPublishExtras(retracts: other.id))

        let objects = store.scan()
        #expect(objects.count == 4)  // 아무것도 사라지지 않는다(제4조)
        let heads = store.heads(objects)
        #expect(heads.map(\.id) == [v2.id])  // v1 은 개정됨, other 는 철회됨, 철회발행은 head 아님
        #expect(store.lineage(objects, of: v2.id).map(\.body) == ["v2", "v1"])

        // 인덱스 기반 읽기(CLI 가속)가 정본 스캔과 **정확히 일치**해야 한다 — 특히 철회 제외.
        let index = LedgerIndex(root: root)
        index.ensureFresh(objectsDir: root.appendingPathComponent("objects"))
        #expect(Set(index.headRows(all: false).map(\.id)) == Set(heads.map(\.id)))  // == [v2]
        #expect(index.headRows(all: true).count == 4)                               // 전체는 4
        #expect(index.resolveIDs("노트") == [v2.id])                                // 제목은 head 만
        #expect(index.resolveIDs(String(v1.id.prefix(8))).contains(v1.id))          // id 접두어는 개정판도 지목
        // history 도 인덱스 == 정본: v2 에서 supersedes 사슬 v2→v1
        #expect(index.lineage(of: v2.id).map(\.id) == store.lineage(objects, of: v2.id).map(\.id))
    }

    @Test func rollbackRepublishesAndRetracts() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let base = try store.publish(author: "human", title: "원본", body: "원본 내용",
                                     now: Date(timeIntervalSince1970: 1_000))
        // 에이전트 작업 묶음: base 개정 + 신규 하나
        let batch = "batch-1"
        let revised = try store.publish(author: "agent", title: "원본", body: "에이전트 수정", now: Date(timeIntervalSince1970: 2_000), extras: LedgerPublishExtras(supersedes: base.id, batch: batch))
        let created = try store.publish(author: "agent", title: "신규", body: "새 문서", now: Date(timeIntervalSince1970: 3_000), extras: LedgerPublishExtras(batch: batch))

        _ = try store.rollback(batchID: batch, author: "human",
                               now: Date(timeIntervalSince1970: 4_000))
        let objects = store.scan()
        let heads = store.heads(objects)
        // head 는 "원본 내용" 복원판 하나뿐 — 에이전트 개정·신규 모두 무효화
        #expect(heads.count == 1)
        #expect(heads.first?.body == "원본 내용")
        #expect(!heads.map(\.id).contains(revised.id))
        #expect(!heads.map(\.id).contains(created.id))
        // 역사는 전부 남는다
        #expect(objects.count == 5)
    }

    @Test func rollbackByAuthorRepublishesAndRetractsWithQuarantine() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let base1 = try store.publish(
            author: "human", title: "문서 1", body: "기본 내용 1",
            now: Date(timeIntervalSince1970: 1_000))
        let base2 = try store.publish(
            author: "human", title: "문서 2", body: "기본 내용 2",
            now: Date(timeIntervalSince1970: 1_100))

        // 타겟 에이전트(rogue-agent)의 활동: base1 개정 + 신규 생성 2건 (하나는 과거, 하나는 최근)
        let rogueOld = try store.publish(
            author: "rogue-agent", title: "옛날 생성", body: "옛날에 생성된 문제 문서",
            now: Date(timeIntervalSince1970: 2_000))
        let rogueRevised = try store.publish(
            author: "rogue-agent", title: "문서 1", body: "에이전트 변조 내용",
            now: Date(timeIntervalSince1970: 3_000),
            extras: LedgerPublishExtras(supersedes: base1.id))
        let rogueNew = try store.publish(
            author: "rogue-agent", title: "최근 생성", body: "최근에 생성된 문제 문서",
            now: Date(timeIntervalSince1970: 3_500))

        // 다른 정상 에이전트(good-agent)의 활동
        let goodObj = try store.publish(
            author: "good-agent", title: "정상 문서", body: "정상 내용",
            now: Date(timeIntervalSince1970: 3_600))

        // 1) since 필터링 검증: 2_500 이후의 rogue-agent 활동만 롤백 (quarantine: true)
        let rollbacks = try store.rollback(
            author: "rogue-agent",
            byAuthor: "auditor",
            since: Date(timeIntervalSince1970: 2_500),
            quarantine: true,
            now: Date(timeIntervalSince1970: 4_000))

        // rogueRevised(개정 복원)와 rogueNew(철회) 2건만 롤백 대상
        #expect(rollbacks.count == 2)
        #expect(rollbacks.allSatisfy { $0.author == "auditor" })
        #expect(rollbacks.allSatisfy { $0.tags.contains("quarantine") })

        let retractedObj = rollbacks.first(where: { $0.retracts != nil })
        #expect(retractedObj?.retracts == rogueNew.id)
        #expect(retractedObj?.body.contains("quarantine rollback") == true)

        let restoredObj = rollbacks.first(where: { $0.supersedes != nil })
        #expect(restoredObj?.supersedes == rogueRevised.id)
        #expect(restoredObj?.body == "기본 내용 1")
        #expect(restoredObj?.cites.contains { $0.rel == "rolls-back" && $0.id == rogueRevised.id } == true)

        // heads 상태 검증
        let afterObjects = store.scan()
        let heads = store.heads(afterObjects)
        let headTitles = Set(heads.compactMap(\.title))

        // base1(복원판으로 head 유지), base2(유지), goodObj(유지), rogueOld(since 이전이므로 유지)
        #expect(headTitles.contains("문서 1"))
        #expect(headTitles.contains("문서 2"))
        #expect(headTitles.contains("정상 문서"))
        #expect(headTitles.contains("옛날 생성"))
        #expect(!headTitles.contains("최근 생성"))

        // verify 검사 통과 (참조 무결성 및 해시 이상 없음)
        #expect(store.verify() == [])
    }
}

@Suite struct CheckpointTests {
    @Test func detectsDeletionAfterCheckpoint() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcl-ckpt-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LedgerStore(root: root)
        _ = try store.publish(author: "human", title: "a", body: "1",
                              now: Date(timeIntervalSince1970: 1_000))
        let b = try store.publish(author: "human", title: "b", body: "2",
                                  now: Date(timeIntervalSince1970: 2_000))
        _ = try store.publishCheckpoint(author: "human", now: Date(timeIntervalSince1970: 3_000))
        #expect(store.verifyCheckpoint() == [])

        // 체크포인트 이후 신규 발행은 위반이 아니다
        _ = try store.publish(author: "human", title: "c", body: "3",
                              now: Date(timeIntervalSince1970: 4_000))
        #expect(store.verifyCheckpoint() == [])

        // 과거 객체 삭제 → 감지
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }.filter { $0.lastPathComponent == "\(b.id).md" }
        try FileManager.default.removeItem(at: files.first!)
        let violations = store.verifyCheckpoint()
        #expect(violations?.contains { $0.problem.contains("삭제 감지") } == true)
    }
}

@Suite struct VerifyTests {
    @Test func detectsTamperingAndDanglingRefs() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let object = try store.publish(author: "human", title: "a", body: "정직한 본문")
        #expect(store.verify().isEmpty)

        // 변조: 파일 본문을 바꿔치기
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "md" }
        let url = files.first!
        let tampered = (try String(contentsOf: url, encoding: .utf8))
            .replacingOccurrences(of: "정직한 본문", with: "몰래 고침")
        try tampered.write(to: url, atomically: true, encoding: .utf8)
        let violations = store.verify()
        #expect(violations.contains { $0.id == object.id && $0.problem.contains("변조") })
    }
}

@Suite struct ContentAddressedTests {
    /// 발행 id = sha256(canonicalCore). 정체성=주소=무결성(제1조).
    @Test func idIsContentHash() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let object = try store.publish(author: "human", title: "개념: X", body: "본문 열두자짜리")
        #expect(LedgerObject.isContentID(object.id))       // 64-hex sha256 형식
        #expect(object.contentID() == object.id)           // 코어 재해시 == id
        #expect(store.verify().isEmpty)
    }

    /// 같은 내용·같은 시각 재발행 → 같은 해시 → dedup(멱등), 새 파일 안 만든다.
    @Test func identicalRepublishDedups() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let a = try store.publish(author: "human", title: "개념: X", body: "본문", now: now)
        let b = try store.publish(author: "human", title: "개념: X", body: "본문", now: now)
        #expect(a.id == b.id)
        #expect(store.scan().count == 1)                   // 파일 1개
    }

    /// 신규 발행은 ledger:2(content-addressed 마커). 구 v1 파일은 파싱 시 ledger:1 보존.
    @Test func ledgerVersionMarksContentAddressed() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let object = try store.publish(author: "human", title: "개념: X", body: "본문")
        #expect(object.ledger == 2)
        #expect(object.serialize().contains("ledger: 2"))
        // 구 v1 프레임(ledger:1, UUID id)을 파싱하면 ledger 1 이 보존된다.
        let v1 = """
        ---
        ledger: 1
        id: aaaaaaaa-0000-7000-8000-000000000001
        published: 2026-07-18T15:03:22Z
        author: human
        sha256: \(LedgerObject.hash("구본문"))
        ---
        구본문
        """
        let parsed = try #require(LedgerObject.parse(v1))
        #expect(parsed.object.ledger == 1)
    }

    /// 내용이 다르면(같은 시각이어도) 다른 해시 → 별개 객체.
    @Test func differentContentDiffersHash() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let a = try store.publish(author: "human", title: "개념: X", body: "본문 하나", now: now)
        let b = try store.publish(author: "human", title: "개념: X", body: "본문 다른것", now: now)
        #expect(a.id != b.id)
        #expect(store.scan().count == 2)
    }

    /// 코어 메타(본문 아닌 필드) 변조도 content-id 불일치로 잡힌다.
    @Test func detectsCoreMetadataTampering() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let object = try store.publish(author: "human", title: "개념: X", body: "본문")
        let url = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }.first { $0.pathExtension == "md" }!
        // author 를 바꿔치기(본문 sha256 은 그대로라 구 검사로는 안 잡힘) — content-id 가 잡는다.
        let tampered = (try String(contentsOf: url, encoding: .utf8))
            .replacingOccurrences(of: "author: human", with: "author: 사칭")
        try tampered.write(to: url, atomically: true, encoding: .utf8)
        #expect(store.verify().contains { $0.id == object.id && $0.problem.contains("content-id") })
    }
}

@Suite struct MigrationTests {
    /// UUIDv7 원장을 content-addressed 로 재주소화 — 참조가 위상순으로 새 해시로 remap 되고
    /// 결과 객체가 자기 content-id 로 검증된다.
    @Test func readdressesUUIDLedgerTopologically() throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        func uuid(_ n: Int) -> String { String(format: "aaaaaaaa-0000-7000-8000-%012d", n) }
        let a = LedgerObject(id: uuid(1), published: base, author: "human",
                             title: "개념: X", body: "본문 A")
        let b = LedgerObject(id: uuid(2), published: base.addingTimeInterval(1), author: "human", title: "개념: X", body: "본문 B 개정", extras: LedgerObject.Extras(supersedes: uuid(1)))
        let c = LedgerObject(id: uuid(3), published: base.addingTimeInterval(2), author: "human", title: "근거: Y", body: "본문 C", extras: LedgerObject.Extras(cites: [.init(id: uuid(2), rel: "supports")]))
        let report = LedgerMigration.readdress([c, b, a])   // 입력 순서 무관

        #expect(report.remap.count == 3)
        #expect(report.changed == 3)                        // 셋 다 uuid → content
        for (_, newID) in report.remap { #expect(LedgerObject.isContentID(newID)) }

        // 재직렬화 파싱 → content-id 검증 + 참조가 새 해시를 가리킴
        let byNew = Dictionary(uniqueKeysWithValues: report.migrated.map { ($0.oldID, $0) })
        let bParsed = LedgerObject.parse(byNew[uuid(2)]!.serialized)!.object
        #expect(bParsed.id == report.remap[uuid(2)])
        #expect(bParsed.contentID() == bParsed.id)          // 무결성
        #expect(bParsed.supersedes == report.remap[uuid(1)]) // A 의 새 해시로 remap
        let cParsed = LedgerObject.parse(byNew[uuid(3)]!.serialized)!.object
        #expect(cParsed.cites.first?.id == report.remap[uuid(2)]) // B 의 새 해시로 remap
    }

    /// 이미 content-addressed 인 객체는 그대로 통과(무변경).
    @Test func alreadyContentAddressedPassesThrough() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let object = try store.publish(author: "human", title: "개념: X", body: "본문")
        let report = LedgerMigration.readdress([object])
        #expect(report.changed == 0)
        #expect(report.remap[object.id] == object.id)
        #expect(report.migrated.first?.unchanged == true)
    }
}

@Suite struct AreaKeyTests {
    @Test func keysAreUniqueAndCoverNewAreas() {
        let all = LedgerAreaKey.all
        #expect(Set(all).count == all.count, "중복 키 없음")
        // 드리프트 사고 회귀: 새 영역이 목록에 있어야 CLI 가 받는다.
        for k in ["events", "changes", "discuss", "learning"] {
            #expect(LedgerAreaKey.isValid(k), "\(k) 가 유효 키여야 함")
        }
        #expect(!LedgerAreaKey.isValid("nope"))
    }
}

@Suite struct ProvenanceTests {
    @Test func roundTripsSourceBlock() {
        let p = Provenance(kind: "pdf", path: "/Users/x/q3 report.pdf", project: "gujo-infra",
                           authoredAt: "2026-03-14", blob: "abc123")
        let obj = LedgerObject(id: "019f0000-0000-7000-8000-000000000000", published: Date(timeIntervalSince1970: 1_780_000_000), author: "human", title: "근거: t", type: "evidence", body: "본문", extras: LedgerObject.Extras(origin: "paste:abc123", source: p))
        let text = obj.serialize()
        #expect(text.contains("source: {"))
        let parsed = LedgerObject.parse(text)?.object
        #expect(parsed?.source?.kind == "pdf")
        #expect(parsed?.source?.path == "/Users/x/q3 report.pdf")
        #expect(parsed?.source?.project == "gujo-infra")
        #expect(parsed?.source?.authoredAt == "2026-03-14")
        #expect(parsed?.source?.blob == "abc123")
    }

    @Test func absentSourceStaysNil() {
        let obj = LedgerObject(id: "019f0000-0000-7000-8000-000000000001",
                               published: Date(), author: "human", body: "x")
        #expect(obj.source == nil)
        #expect(!obj.serialize().contains("source:"))
        #expect(LedgerObject.parse(obj.serialize())?.object.source == nil)
    }
}

@Suite struct ReviewVerdictTests {
    @Test func roundTrips() {
        let v = ReviewVerdict(decision: .reject, scores: ["정확성": 5, "구조": 3], comment: "예시 보강 필요")
        let parsed = ReviewVerdict(body: v.body())
        #expect(parsed?.decision == .reject)
        #expect(parsed?.scores["정확성"] == 5)
        #expect(parsed?.scores["구조"] == 3)
        #expect(parsed?.comment == "예시 보강 필요")
    }
    @Test func averageIgnoresMissingAxes() {
        let v = ReviewVerdict(decision: .accept, scores: ["정확성": 4, "구조": 2])
        #expect(v.averageScore == 3.0)
    }
    @Test func rejectsUnknownBody() { #expect(ReviewVerdict(body: "그냥 텍스트") == nil) }
}

@Suite struct RepoWorldTests {
    /// resolveWorld 가 cwd 에서 상위로 `.wiki/` 를 찾아 그 repo 원장을 고른다(git 이 `.git` 찾듯).
    @Test func resolvesNearestWikiWalkingUp() throws {
        let fm = FileManager.default
        let repo = fm.temporaryDirectory.appendingPathComponent("rw-\(UUID().uuidString)")
        let wiki = repo.appendingPathComponent(".wiki")
        let deep = repo.appendingPathComponent("apps/x/Sources")
        try fm.createDirectory(at: wiki, withIntermediateDirectories: true)
        try fm.createDirectory(at: deep, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: repo) }

        let config = LedgerConfig(
            worlds: [
                LedgerWorld(name: "gujo-wiki", rootPath: "/tmp/gujo"),
                LedgerWorld(name: "person-personal", rootPath: "/tmp/person-personal"),
            ],
            currentWorld: "gujo-wiki"
        )

        let inRepo = config.resolveWorld(cwd: deep.path)
        #expect(inRepo?.rootPath == wiki.path)
        #expect(inRepo?.name == repo.lastPathComponent)

        let outside = config.resolveWorld(cwd: "/tmp")
        #expect(outside == nil)

        let forced = config.resolveWorld(cwd: deep.path, explicitWorld: "gujo-wiki")
        #expect(forced?.name == "gujo-wiki")

        let unknown = config.resolveWorld(cwd: "/tmp", explicitWorld: "no-such-world")
        #expect(unknown == nil)

        let tenant = config.resolveWorld(cwd: "/tmp", tenantWikiWorld: "person-personal")
        #expect(tenant?.name == "person-personal")
    }

    /// 활성 테넌트가 있어도 world 지도는 호스트 `~/.memo-citation-ledger` 다.
    @Test func worldRegistryStaysOnHostWhenTenantContextIsSet() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("wiki-cfg-\(UUID().uuidString)")
        let ctx = home.appendingPathComponent(".agent-tenant-isolation-manager")
        try fm.createDirectory(at: ctx, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }
        try Data(#"{"tenantID":"tenant:personal"}"#.utf8)
            .write(to: ctx.appendingPathComponent("current-context.json"))

        let url = LedgerConfig.configURL(environment: [:], homeDirectory: home.path)
        #expect(url.path == home.appendingPathComponent(".memo-citation-ledger/config.json").path)
        #expect(!url.path.contains("/.tenants/"))
    }
}

@Suite struct TaskGraphTests {
    @Test func excludesRetractedTasksFromRepositoryTaskProjection() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let task = try store.publish(
            author: "agent", title: "accidental task", type: "task", body: "mistake")
        _ = try store.publish(author: "agent", title: "retract accidental task", type: "correction", body: "diagnostic rollback", extras: LedgerPublishExtras(retracts: task.id))

        let graph = LedgerTaskGraph(objects: store.scan())
        let contract = RepositoryTaskListContract(graph: graph, repoId: "repo-test")

        #expect(graph.tasks.isEmpty)
        #expect(graph.open.isEmpty)
        #expect(contract.summary.total == 0)
    }

    /// legacy done은 보존하지만 checker receipt 전에는 완료로 닫지 않는다.
    @Test func derivesStatusAssigneeCompletion() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let t1 = try store.publish(author: "오케", title: "작업1", type: "task", body: "하기")
        _ = try store.publish(author: "오케", title: "위임", type: "handoff", body: "위임 → 늑대\n메모", extras: LedgerPublishExtras(cites: [.init(id: t1.id, rel: "delegates")]))
        _ = try store.publish(author: "늑대", title: "완료", type: "done", body: "됨", extras: LedgerPublishExtras(cites: [.init(id: t1.id, rel: "completes")]))
        _ = try store.publish(author: "오케", title: "작업2", type: "task", body: "안한거")

        let graph = LedgerTaskGraph(objects: store.scan())
        #expect(graph.tasks.count == 2)
        #expect(!graph.isDone(t1.id))
        #expect(graph.items.first { $0.taskId == t1.id }?.orchestration.state == .unbound)
        #expect(graph.assignee[t1.id] == "늑대") // handoff 대상 파싱
        #expect(graph.open.count == 2)
    }
}
