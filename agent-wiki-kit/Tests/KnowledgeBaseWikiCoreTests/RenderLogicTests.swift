import Foundation
import Testing
@testable import KnowledgeBaseWikiCore

private func obj(_ title: String?, type: String? = nil, body: String = "본문",
                 tags: [String] = [], cites: [LedgerObject.Cite] = [],
                 author: String = "agent", now: TimeInterval = 1_000) -> LedgerObject {
    LedgerObject(id: LedgerID.generate(now: Date(timeIntervalSince1970: now)), published: Date(timeIntervalSince1970: now), author: author, title: title, type: type, body: body, extras: LedgerObject.Extras(tags: tags, cites: cites))
}

@Suite struct EffectiveTypeTests {
    @Test func explicitTypeWins() {
        #expect(obj("근거: x", type: "concept").effectiveType == "concept")
    }
    @Test func derivedFromTitlePrefix() {
        #expect(obj("근거: x").effectiveType == "evidence")
        #expect(obj("개념: x").effectiveType == "concept")
        #expect(obj("엔티티: x").effectiveType == "entity")
        #expect(obj("색인").effectiveType == "index")
        #expect(obj("선별: x").effectiveType == "screening")
        #expect(obj("플레이북: x").effectiveType == "playbook")
    }
    @Test func processVsKnowledge() {
        #expect(obj("선별: x").isProcess)          // 절차
        #expect(obj("체크포인트: 500").isProcess)
        #expect(!obj("근거: x").isProcess)          // 지식
        #expect(!obj("개념: x").isProcess)
        #expect(!obj("결정: x").isProcess)          // 결정=지식
        #expect(!obj("플레이북: x").isProcess)      // 플레이북=독립 범주(절차기록 아님)
    }
    @Test func nfdTitleNormalizes() {
        // NFD("개념") 도 effectiveType 이 concept
        let nfd = "\u{1100}\u{1162}\u{1102}\u{1167}\u{11B7}: x"  // 개념 분해형
        #expect(obj(nfd).effectiveType == "concept")
    }
}

@Suite struct ProcessTypeSingleSourceTests {
    /// SQL IN-리스트는 processTypes 단일원에서만 파생돼야 한다(하드코딩 복사본 금지).
    @Test func sqlDerivesFromSet() {
        let expected = LedgerObject.processTypes.sorted().map { "'\($0)'" }.joined(separator: ",")
        #expect(LedgerObject.processTypesSQL == expected)
        // 모든 절차 type 이 리터럴에 들어있다
        for type in LedgerObject.processTypes {
            #expect(LedgerObject.processTypesSQL.contains("'\(type)'"))
        }
        // 지식 type 은 절대 포함되지 않는다
        for type in ["concept", "entity", "evidence", "decision", "index"] {
            #expect(!LedgerObject.processTypesSQL.contains("'\(type)'"))
        }
    }
}

@Suite struct ParseClassificationTests {
    @Test func extractsThreeAxes() {
        let body = "screens: abc\ndomain: dev-workflow\nkind: runbook\nknowledge: tech\n기타"
        let c = LedgerObject.parseClassification(body)
        #expect(c.domain == "dev-workflow")
        #expect(c.kind == "runbook")
        #expect(c.knowledge == "tech")
    }
    @Test func missingAxesAreNil() {
        let c = LedgerObject.parseClassification("domain: only-domain")
        #expect(c.domain == "only-domain")
        #expect(c.kind == nil)
        #expect(c.knowledge == nil)
    }

    @Test func classificationInputRequiresValidAxesAndReason() {
        #expect(LedgerClassificationInput(
            domain: "infra-hosting", kind: "incident", knowledge: "domain", reason: "NFS 경로에 영향을 준다") != nil)
        #expect(LedgerClassificationInput(
            domain: "unknown", kind: "incident", knowledge: "domain", reason: "근거") == nil)
        #expect(LedgerClassificationInput(
            domain: "infra-hosting", kind: "incident", knowledge: "domain", reason: " ") == nil)
    }
}

@Suite struct FactInterpretationTests {
    @Test func factVsInterpretationSubsetsOfProcess() {
        // 두 부분집합은 processTypes 안에 있어야 하고 서로 겹치지 않는다
        #expect(LedgerObject.factTypes.isSubset(of: LedgerObject.processTypes))
        #expect(LedgerObject.interpretationTypes.isSubset(of: LedgerObject.processTypes))
        #expect(LedgerObject.factTypes.isDisjoint(with: LedgerObject.interpretationTypes))
    }
    @Test func predicates() {
        #expect(obj("run: x").isFact)
        #expect(obj("체크포인트: 5").isFact)
        #expect(!obj("run: x").isInterpretation)
        #expect(obj("분류: x").isInterpretation)
        #expect(obj("반박: x").isInterpretation)
        #expect(!obj("분류: x").isFact)
        // 지식은 둘 다 아니다
        #expect(!obj("개념: x").isFact)
        #expect(!obj("개념: x").isInterpretation)
    }
    /// 관계도가 이 계약에 기대 노드를 색칠·포함한다(해석=brown 포함, 사실=제외).
    /// 다섯 해석 type 전부 isInterpretation 이어야 그래프에서 판단이 안 새고 잡힌다.
    @Test func allInterpretationTitlesClassifyAsInterpretation() {
        for (prefix, _) in [("분류", "classification"), ("재확인", "reverification"),
                            ("재현", "reproduction"), ("반박", "refutation"), ("이의", "objection")] {
            #expect(obj("\(prefix): 샘플").isInterpretation, "\(prefix) 는 해석이어야 함")
            #expect(!obj("\(prefix): 샘플").isFact)
        }
    }
}

@Suite struct EventDepthTests {
    @Test func legacyEventDecodesWithDefaults() throws {
        // 구 이벤트(level/parent/outcome 없음)도 디코드돼야 — 하위호환.
        let legacy = #"{"id":"e1","occurred":"2020-01-01T00:00:00Z","recorded":"2020-01-01T00:00:00Z","writer":"tick","subject":"s","rel":"관측","attrs":{}}"#
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let e = try decoder.decode(Event.self, from: Data(legacy.utf8))
        #expect(e.level == .step)     // 기본
        #expect(e.parent == nil)
        #expect(e.outcome == nil)
    }

    @Test func openRunsDetectsStranded() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ledger-depth-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = EventLog(root: dir)
        let old = Date(timeIntervalSince1970: 1000)
        // 좌초: 시작만 있고 완료 없음
        let stranded = Event(writer: "verifier", subject: "verifier", rel: "역할 실행", occurred: old, level: .run, extras: Event.Extras(outcome: .pending))
        try log.append(stranded)
        // 정상: 시작 + 성공
        let done = Event(writer: "wiki", subject: "wiki", rel: "역할 실행", occurred: old, level: .run, extras: Event.Extras(outcome: .pending))
        try log.append(done)
        try log.append(Event(writer: "wiki", subject: "wiki", rel: "성공", occurred: old, level: .run, extras: Event.Extras(parent: done.id, outcome: .ok)))
        // 단계 하나
        try log.append(Event(writer: "verifier", subject: "obj", rel: "근거검색", occurred: old, level: .step, extras: Event.Extras(parent: stranded.id)))

        let open = log.openRuns(olderThan: Date(timeIntervalSince1970: 2000))
        #expect(open.map(\.id) == [stranded.id])          // 좌초만
        #expect(log.children(of: stranded.id).count == 1)  // 그 단계
        // cutoff 이 발생 이전이면 아직 좌초 아님
        #expect(log.openRuns(olderThan: Date(timeIntervalSince1970: 500)).isEmpty)
    }
}

@Suite struct ObservesFieldTests {
    @Test func roundTrips() {
        let o = LedgerObject(id: LedgerID.generate(), published: Date(timeIntervalSince1970: 1), author: "agent", title: "분류: x", body: "본문", extras: LedgerObject.Extras(cites: [.init(id: "abc", rel: "screens")], observes: ["evt-1", "evt-2"]))
        let parsed = LedgerObject.parse(o.serialize())
        #expect(parsed?.object.observes == ["evt-1", "evt-2"])
        #expect(parsed?.object.cites.count == 1)  // cite 와 분리 보존
    }
    @Test func graphTimelineJoinsObjectsAndEvents() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ledger-graph-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let graph = LedgerGraph(root: dir)
        let entity = obj("엔티티: gujo-wiki")
        // 해석 객체가 사건을 observes
        let analysis = obj("분류: 결정", cites: [.init(id: entity.id, rel: "screens")])
        let events = [
            Event(writer: "tick", subject: entity.id, rel: "동결", extras: Event.Extras(object: "llmwiki")),
            Event(writer: "tick", subject: "other", rel: "무관", extras: Event.Extras(object: entity.id)),
        ]
        let analysisWithObserve = LedgerObject(id: analysis.id, published: analysis.published, author: "agent-a", title: "분류: 결정", body: "본문", extras: LedgerObject.Extras(observes: [events[0].id]))
        graph.rebuild(objects: [entity, analysisWithObserve], events: events)
        let c = graph.counts()
        #expect(c.nodes == 4)   // 엔티티 + 해석 + 사건2
        // 타임라인 — 엔티티를 subject/object 로 삼은 사건 둘 다 잡힌다
        let tl = graph.timeline(of: entity.id)
        #expect(tl.count == 2)
        // 해석 추적 — 사건0 을 observes 한 해석 객체
        #expect(graph.interpretations(of: events[0].id) == [analysisWithObserve.id])
    }

    @Test func timelineDedupesWhenSubjectEqualsObject() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ledger-tl-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let graph = LedgerGraph(root: dir)
        let ent = obj("엔티티: X")
        // subject == object 인 사건 — 두 간선이 생기지만 타임라인엔 한 번만.
        let e = Event(writer: "t", subject: ent.id, rel: "실패", extras: Event.Extras(object: ent.id))
        graph.rebuild(objects: [ent], events: [e])
        #expect(graph.timeline(of: ent.id).count == 1)
    }

    @Test func eventLogAppendReadBitemporal() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ledger-event-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = EventLog(root: dir)
        let past = Date(timeIntervalSince1970: 1_600_000_000)      // 2020 (사후 기록)
        let recent = Date(timeIntervalSince1970: 1_700_000_000)    // 2023
        try log.append(Event(writer: "tick", subject: "obj-A", rel: "실행", occurred: recent, extras: Event.Extras(source: "sha1")))
        try log.append(Event(writer: "agent-b", subject: "obj-B", rel: "관측", occurred: past))
        let all = log.all()
        #expect(all.count == 2)
        #expect(all[0].occurred == past)         // occurred 순 정렬 — 사후기록도 제자리
        #expect(all[1].occurred == recent)
        #expect(log.count() == 2)
        #expect(log.reachableBlobSHAs() == ["sha1"])   // provenance 집계
        // 다른 writer 는 다른 세그먼트 → 경합 없이 병존
        #expect(log.segments().count == 2)
    }

    @Test func blobRoundTripAndIntegrity() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ledger-blob-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = BlobStore(root: dir)
        let payload = Data("run stdout: 실패\n에러코드 137".utf8)
        let sha = try store.put(payload)
        #expect(sha == BlobStore.sha256(payload))       // content-addressed
        #expect(store.exists(sha))
        #expect(store.get(sha) == payload)              // round-trip
        #expect(store.verify(sha))                       // 무결성
        #expect(try store.put(payload) == sha)          // 멱등(write-once)
        // gc — reachable 에 없으면 제거
        #expect(store.prune(keeping: []) == 1)
        #expect(!store.exists(sha))
    }

    @Test func observesNotCheckedByVerify() throws {
        // 사건 참조는 md 객체가 아니라 verify 참조검사에 걸리면 안 된다
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ledger-observes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = LedgerStore(root: dir)
        _ = try store.publish(author: "agent", title: "분류: x", body: "본문", extras: LedgerPublishExtras(observes: ["nonexistent-event-id"]))
        let violations = store.verify()
        // observes 대상이 원장에 없어도 위반이 아니어야 한다
        #expect(!violations.contains { $0.problem.contains("없는 객체 참조") })
    }
}

@Suite struct ClassificationTests {
    @Test func promotesScreensStampToHead() {
        let ev = obj("근거: 코드서명", type: "evidence")
        let stamp = obj("선별: 코드서명", type: "screening",
                        body: "domain: macos-apps\nkind: decision\nknowledge: domain",
                        cites: [.init(id: ev.id, rel: "screens")])
        let c = LedgerClassification(objects: [ev, stamp])
        #expect(c.domain[ev.id] == "macos-apps")
        #expect(c.kind[ev.id] == "decision")
        #expect(c.knowledge[ev.id] == "domain")
    }
    @Test func promotesToLineageHead() {
        let v1 = obj("근거: x", type: "evidence", now: 1_000)
        let v2 = LedgerObject(id: LedgerID.generate(now: Date(timeIntervalSince1970: 2_000)), published: Date(timeIntervalSince1970: 2_000), author: "agent", title: "근거: x", type: "evidence", body: "v2", extras: LedgerObject.Extras(supersedes: v1.id))
        let stamp = obj("선별: x", type: "screening", body: "domain: dev-workflow",
                        cites: [.init(id: v1.id, rel: "screens")], now: 3_000)
        let c = LedgerClassification(objects: [v1, v2, stamp])
        #expect(c.domain[v2.id] == "dev-workflow")   // v1 스탬프가 head v2 로 승격
    }

    @Test func supersededScreeningDoesNotOverrideItsRevision() {
        let ev = obj("근거: 분류 개정", type: "evidence")
        let old = obj("선별: 분류 개정", type: "screening",
                      body: "domain: infra-hosting\nkind: overview\nknowledge: domain",
                      cites: [.init(id: ev.id, rel: "screens")], now: 2_000)
        let revised = LedgerObject(id: LedgerID.generate(now: Date(timeIntervalSince1970: 3_000)), published: Date(timeIntervalSince1970: 3_000), author: "agent", title: "선별: 분류 개정", type: "screening", body: "domain: dev-workflow\nkind: decision\nknowledge: preference", extras: LedgerObject.Extras(cites: [.init(id: ev.id, rel: "screens")], supersedes: old.id))
        let c = LedgerClassification(objects: [ev, old, revised])
        #expect(c.domain[ev.id] == "dev-workflow")
        #expect(c.kind[ev.id] == "decision")
        #expect(c.knowledge[ev.id] == "preference")
    }
}

@Suite struct SearchTests {
    @Test func rankingAndProcessExclusion() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mcl-search-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LedgerStore(root: root)
        _ = try? store.publish(author: "agent", title: "개념: 코드서명 SSOT", type: "concept",
                               body: "코드서명 정본은 여기다")
        _ = try? store.publish(author: "agent", title: "근거: 딴것", type: "evidence", body: "무관")
        _ = try? store.publish(author: "agent", title: "선별: 코드서명", type: "screening",
                               body: "코드서명 코드서명")  // 절차 — 제외돼야
        let objects = store.scan()
        let hits = LedgerSearch(store: store, objects: objects, query: "코드서명").hits
        #expect(hits.first?.object.title == "개념: 코드서명 SSOT")  // 제목 매치 최상
        #expect(!hits.contains { $0.object.effectiveType == "screening" })  // 절차 제외
    }
    @Test func emptyQueryNoHits() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mcl-search2-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LedgerStore(root: root)
        _ = try? store.publish(author: "agent", title: "개념: x", type: "concept", body: "y")
        #expect(LedgerSearch(store: store, objects: store.scan(), query: "  ").hits.isEmpty)
    }
}

@Suite struct OKFExportTests {
    @Test func exportsConceptsAndReservedFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mcl-okf-\(UUID())")
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("mcl-okf-out-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: out) }
        let store = LedgerStore(root: root)
        _ = try store.publish(author: "wiki-maintainer", title: "개념: 테스트개념", type: "concept", body: "내용")
        _ = try store.publish(author: "human", title: "체크포인트: 1", type: "checkpoint", body: "objects: 1")
        let objects = store.scan()
        let summary = try OKFExporter.export(objects: objects, heads: store.heads(objects), to: out)
        #expect(summary.contains("개념 1"))
        #expect(FileManager.default.fileExists(atPath: out.appendingPathComponent("index.md").path))
        #expect(FileManager.default.fileExists(atPath: out.appendingPathComponent("log.md").path))
        let concept = try String(contentsOf: out.appendingPathComponent("concepts/테스트개념.md"), encoding: .utf8)
        #expect(concept.contains("type: Concept"))   // OKF 필수 필드
    }
}

@Suite struct IndexTests {
    @Test func syncSearchAndClassification() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mcl-idx-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LedgerStore(root: root)
        let ev = try store.publish(author: "agent", title: "개념: 코드서명 SSOT", type: "concept",
                                   body: "코드서명 정본은 app-build-manager")
        _ = try store.publish(author: "agent", title: "근거: 무관", type: "evidence", body: "딴것")
        _ = try store.publish(author: "agent", title: "선별: 코드서명", type: "screening", body: "domain: macos-apps\nknowledge: domain", extras: LedgerPublishExtras(cites: [.init(id: ev.id, rel: "screens")]))
        let index = LedgerIndex(root: root)
        let r = index.sync(objectsDir: root.appendingPathComponent("objects"))
        #expect(r.upserted == 3)
        #expect(index.objectCount() == 3)
        // FTS 검색 — 절차(선별) 제외, 개념 매치
        let hits = index.search("코드서명")
        #expect(hits.contains { $0.title == "개념: 코드서명 SSOT" })
        #expect(!hits.contains { $0.type == "screening" })
        // 분류 승격 (스탬프 → head)
        #expect(hits.first { $0.title == "개념: 코드서명 SSOT" }?.domain == "macos-apps")
        // 증분: 재sync 는 변경 없음
        #expect(index.sync(objectsDir: root.appendingPathComponent("objects")).upserted == 0)
    }

    @Test func indexesAliasesAndGeneratedScreening() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mcl-alias-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LedgerStore(root: root)
        let object = try store.publish(author: "agent", title: "근거: 승인 게이트", type: "evidence", body: "승인 요청을 처리한다", extras: LedgerPublishExtras(tags: ["alias:agent-request", "alias:자동승인"]))
        let input = try #require(LedgerClassificationInput(
            domain: "agent-orchestration", kind: "overview", knowledge: "domain", reason: "에이전트 승인 흐름을 다룬다"))
        _ = try store.publishScreening(author: "agent", target: object, classification: input)
        let index = LedgerIndex(root: root)
        _ = index.sync(objectsDir: root.appendingPathComponent("objects"))
        #expect(index.search("agent-request").contains { $0.id == object.id })
        #expect(index.search("자동승인", domain: "agent-orchestration").contains { $0.id == object.id })
    }
}

@Suite struct VersionTests {
    @Test func versionIsNonEmptyStable() {
        #expect(!LedgerVersion.current.isEmpty)
    }
}

@Suite struct VerifierRotationTests {
    @Test func rotationDefersRecentlySelected() {
        let ranked = ["a", "b", "c", "d"]
        // a·b 최근 선정됨 → c·d 우선
        let r1 = EventLog.rotatedTargets(ranked: ranked, recentlySelected: ["a", "b"], limit: 2)
        #expect(r1 == ["c", "d"])
    }
    @Test func rotationResetsWhenAllRecent() {
        let ranked = ["a", "b"]
        // 다 최근이면(한 바퀴) 리셋 — ranked 그대로
        let r = EventLog.rotatedTargets(ranked: ranked, recentlySelected: ["a", "b"], limit: 2)
        #expect(r == ["a", "b"])
    }
    @Test func subjectsWithEventWindow() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rot-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = EventLog(root: dir)
        let now = Date(timeIntervalSince1970: 2_000_000)
        try log.append(Event(writer: "verifier", subject: "x", rel: "재검증 선정", occurred: now, level: .step))
        try log.append(Event(writer: "verifier", subject: "old", rel: "재검증 선정", occurred: Date(timeIntervalSince1970: 1_000_000), level: .step))
        let recent = log.subjectsWithEvent(rel: "재검증 선정", since: Date(timeIntervalSince1970: 1_500_000))
        #expect(recent == ["x"])   // 창 밖 old 는 제외
    }
}

@Suite struct BlobMediaTests {
    @Test func sniffsCommonTypes() {
        #expect(BlobStore.sniff(Data([0x25,0x50,0x44,0x46,0x2D])).label == "PDF")
        #expect(BlobStore.sniff(Data([0x89,0x50,0x4E,0x47])).label == "PNG")
        #expect(BlobStore.sniff(Data([0x49,0x44,0x33,0x03])).label == "MP3")
        #expect(BlobStore.sniff(Data("그냥 텍스트".utf8)).isText)
        #expect(BlobStore.sniff(Data([0x00,0x01,0x02,0xFF])).label == "바이너리")
        #expect(BlobStore.sniff(Data([0x25,0x50,0x44,0x46])).ext == "pdf")
    }
    @Test func reverseRefsFindConnectedEvents() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("blobref-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = EventLog(root: dir)
        try log.append(Event(writer: "a", subject: "s1", rel: "수집", extras: Event.Extras(source: "SHA")))
        try log.append(Event(writer: "b", subject: "s2", rel: "검토", extras: Event.Extras(source: "SHA")))
        try log.append(Event(writer: "c", subject: "s3", rel: "무관", extras: Event.Extras(source: "OTHER")))
        let refs = log.eventsReferencing(blob: "SHA")
        #expect(refs.count == 2)
        #expect(refs.map(\.rel) == ["수집", "검토"])
    }
}

@Suite struct RecentChangesTests {
    @Test func classifiesNewRevisedRetracted() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = LedgerStore(root: dir)
        let a = try store.publish(author: "wiki-maintainer", title: "개념: X", body: "본문 열자")   // 신규
        let b = try store.publish(author: "wiki-maintainer", title: "개념: X", body: "개정 사유: 보강\n\n더 긴 본문 열두자짜리", extras: LedgerPublishExtras(supersedes: a.id))   // 개정
        _ = try store.publish(author: "human", title: "체크포인트: 1", body: "objects: 1")   // 절차 → 제외
        let changes = store.recentChanges(store.scan())
        #expect(changes.count == 2)                       // 절차 제외
        #expect(changes[0].id == b.id && changes[0].kind == .revised)
        #expect(changes[0].reason == "보강")
        #expect(changes[0].deltaChars > 0)                // 본문 늘어남
        #expect(changes[1].kind == .new)
    }
}

@Suite struct DiscussionThreadTests {
    @Test func openVsAnswered() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("disc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = LedgerStore(root: dir)
        let page = try store.publish(author: "wiki-maintainer", title: "개념: X", body: "본문")
        let q = try store.publish(author: "human", title: "질문: 개념: X", body: "왜?", extras: LedgerPublishExtras(cites: [.init(id: page.id, rel: "discusses")]))
        _ = try store.publish(author: "human", title: "이의: 개념: X", body: "틀림", extras: LedgerPublishExtras(cites: [.init(id: page.id, rel: "undercuts")]))   // 미답변
        _ = try store.publish(author: "wiki-maintainer", title: "답변: 개념: X", body: "이래서", extras: LedgerPublishExtras(cites: [.init(id: q.id, rel: "answers")]))         // 질문에 답변
        let threads = store.discussionThreads(store.scan())
        #expect(threads.count == 2)
        // 미답변(이의) 먼저
        #expect(threads[0].isOpen && threads[0].kind == .objection)
        // 질문은 답변됨
        let qt = threads.first { $0.kind == .question }!
        #expect(!qt.isOpen && qt.responseCount == 1)
    }
}

@Suite struct TextDiffTests {
    @Test func addRemoveSame() {
        let d = TextDiff.lines("a\nb\nc", "a\nB\nc\nd")
        #expect(d == [.same("a"), .removed("b"), .added("B"), .same("c"), .added("d")])
        let s = TextDiff.stat(d)
        #expect(s.added == 2 && s.removed == 1)
    }
    @Test func identicalNoChange() {
        #expect(TextDiff.stat(TextDiff.lines("x\ny", "x\ny")) == (0, 0))
    }
}

@Suite struct LearningMetricsTests {
    @Test func aggregatesRunsRevisionsRules() throws {
        let t = Date(timeIntervalSince1970: 1_700_000_000)  // 고정일
        let events = [
            Event(writer: "v", subject: "v", rel: "성공", occurred: t, level: .run, extras: Event.Extras(outcome: .ok)),
            Event(writer: "v", subject: "v", rel: "실패", occurred: t, level: .run, extras: Event.Extras(outcome: .fail)),
            Event(writer: "v", subject: "v", rel: "성공", occurred: t, level: .run, extras: Event.Extras(outcome: .ok)),
        ]
        let rule = LedgerObject(id: LedgerID.generate(now: t), published: t, author: "retrospective",
                                title: "회고: 교훈", body: "본문")
        let m = LearningMetrics.byDay(objects: [rule], events: events, days: 100000)
        #expect(m.count == 1)
        #expect(m[0].runsOk == 2 && m[0].runsFail == 1)
        #expect(abs(m[0].successRate - 2.0/3.0) < 0.01)
        #expect(m[0].newRules == 1)
    }
}

@Suite struct ExperienceRuleInjectionTests {
    @Test func roleSpecificFirstThenGeneral() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("expr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = LedgerStore(root: dir)
        _ = try store.publish(author: "retrospective", title: "회고: 일반 교훈", body: "적용 대상: 모두")
        let vRule = try store.publish(author: "retrospective", title: "회고: verifier 교훈",
                                      body: "적용 대상: verifier 는 origin 재방문 실패를 기록하라")
        let rules = store.experienceRules(store.scan(), forRole: "verifier", limit: 5)
        #expect(rules.first?.id == vRule.id)             // 역할 언급 우선
        #expect(rules.count == 2)
        let prompt = store.experienceRulesPrompt(store.scan(), forRole: "verifier")
        #expect(prompt.contains("지난 경험칙") && prompt.contains("verifier 교훈"))
        // 경험칙 없는 역할엔 빈 문자열
        _ = store.experienceRulesPrompt([], forRole: "x")
    }
}

@Suite struct DiscussionTypeDiscussTests {
    @Test func recognizesDiscussTypeAndTitleKind() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("disc2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = LedgerStore(root: dir)
        let page = try store.publish(author: "wiki-maintainer", title: "역할정의: retrospective", body: "역할")
        // 에이전트가 type=discuss 로 낸 수정요청(제목은 수정요청:)
        _ = try store.publish(author: "retrospective", title: "수정요청: 역할정의: retrospective — finally-close", type: "discuss", body: "제안", extras: LedgerPublishExtras(cites: [.init(id: page.id, rel: "supports")]))
        let threads = store.discussionThreads(store.scan())
        #expect(threads.count == 1)
        #expect(threads[0].kind == .editRequest)   // 제목으로 수정요청 인식
        #expect(threads[0].isOpen)                  // 미답변
    }
}
