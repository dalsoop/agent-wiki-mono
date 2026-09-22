import Foundation
import KnowledgeBaseWikiCore

public func runTick(store: LedgerStore, root: URL, author: String, arguments: [String]) {
    guard arguments.count >= 2 else { fail(usage) }
    switch arguments[1] {
    case "checkpoint":      tickCheckpoint(store: store, root: root, author: author)
    case "librarian":       tickLibrarian(store: store, root: root)
    case "verifier":        tickVerifier(store: store, root: root, arguments: arguments)
    case "retrospective":   tickRetrospective(root: root)
    case "reaper":          tickReaper(store: store, root: root)
    default:                fail(usage)
    }
}

private func tickCheckpoint(store: LedgerStore, root: URL, author: String) {
    runAgentSync(store: store, root: root)
    LedgerIndex(root: root).sync(objectsDir: root.appendingPathComponent("objects"))
    let objects = store.scan()
    let events = EventLog(root: root).all()
    LedgerGraph(root: root).rebuild(objects: objects, events: events)
    let last = store.latestCheckpoint(objects)
    let newCount = objects.filter { $0.id > (last?.id ?? "") }.count
    if last == nil || newCount > 0 {
        do {
            let object = try store.publishCheckpoint(author: author)
            print("체크포인트 발행: \(object.id.prefix(8))  (\(object.title ?? ""))") // allow:debug
            try? EventLog(root: root).append(Event(
                writer: "tick-checkpoint", subject: object.id,
                rel: "체크포인트",
                extras: Event.Extras(attrs: ["objects": String(objects.count)])))
        } catch { fail("\(error)") }
    } else {
        print("\(nowISO()) 새 발행 없음 — no-op") // allow:debug
    }
}

private func tickLibrarian(store: LedgerStore, root: URL) {
    let cut = Date().addingTimeInterval(-24 * 3600)
    let recent = store.scan().filter { object in
        object.published > cut
            && !["checkpoint", "concept", "entity", "index"].contains(object.effectiveType ?? "")
    }.count

    tickLibrarianClassify(store: store, root: root)

    guard recent > 0 else { print("\(nowISO()) 새 발행 없음 — no-op"); clearStatus(root: root); return } // allow:debug
    print("\(nowISO()) 새 발행 \(recent)건 — 사서 기동") // allow:debug

    tickLibrarianMaintain(root: root, recent: recent)
    tickLibrarianConsistency(root: root)
    clearStatus(root: root)
}

private func tickLibrarianClassify(store: LedgerStore, root: URL) {
    let all = store.scan()
    let classification = LedgerClassification(objects: all)
    let unclassified = store.heads(all).filter {
        $0.effectiveType == "evidence" && $0.retracts == nil
            && classification.domain[$0.id] == nil
    }.prefix(20)
    guard !unclassified.isEmpty else { return }
    writeStatus(root: root, label: "taxonomy-drafter — 미분류 유입 분류 중",
                detail: "\(unclassified.count)건 3축 분류")
    let ids = unclassified.map(\.id).joined(separator: "\n")
    runEngine(role: "taxonomy-drafter", root: root, prompt: """
        taxonomy-drafter 역할(.agents/roles/taxonomy-drafter.md)을 수행해라. 아래 미분류 근거를 \
        show 로 읽고 각각 '분류: <제목요약>' 스탬프(rel=screens)를 발행하라 — 본문에 domain/kind/knowledge \
        세 줄 + 판정 근거 2문장. 확신 없으면 건너뛰고 사유 기록. run 카드 규약 준수.

        \(ids)
        """)
}

private func tickLibrarianMaintain(root: URL, recent: Int) {
    writeStatus(root: root, label: "야간 사서 — 위키 층 정비 중", detail: "최근 24h 발행 \(recent)건 반영")
    runEngine(role: "wiki-maintainer", root: root, prompt: """
        wiki-maintainer 역할을 수행해라(.agents/roles/wiki-maintainer.md). 최근 24시간 발행분을 훑고: \
        ① 영향받는 개념 페이지를 개정(역방향 갱신) ② 없는 주제면 새 개념 페이지 발행 ③ 색인 개정. \
        전부 근거 cite, 인식론 표기 준수. 발행·개정하는 모든 위키 페이지에 --tag 를 단다 \
        (도메인 1개 + 주제 태그 1~3개, kebab-case). 태그 없는 기존 페이지를 개정할 때도 태그를 소급한다. \
        미응답 토론(이의·질문·수정요청) 최우선. 끝나면 발행 id 목록만 보고.
        """)
}

private func tickLibrarianConsistency(root: URL) {
    writeStatus(root: root, label: "consistency-checker — 상충 스캔 중", detail: "오늘 개정 위키 vs 근거 대조")
    runEngine(role: "consistency-checker", root: root, prompt: """
        consistency-checker 역할(.agents/roles/consistency-checker.md)을 수행해라. 오늘 개정된 위키 페이지와 \
        그 인용 근거들 사이의 상충(모순 주장·설정 충돌)을 찾아 contradicts 로 표면화하라. run 카드 규약을 지켜라. \
        상충 없으면 '상충 없음' 요약만 발행.
        """)
}

private func tickVerifier(store: LedgerStore, root: URL, arguments: [String]) {
    let objects = store.scan()
    let ranked = store.heads(objects)
        .filter { !$0.isProcess && $0.retracts == nil && ($0.origin?.hasPrefix("http") ?? false) }
        .map { ($0, store.strength(objects, of: $0)) }
        .sorted { $0.1.freshness < $1.1.freshness }
    guard !ranked.isEmpty else { print("\(nowISO()) 대상 없음"); return } // allow:debug

    let eventLog = EventLog(root: root)
    let candidates = selectVerifierCandidates(ranked: ranked, eventLog: eventLog)

    if arguments.contains("--dry") {
        print("선정 \(candidates.count)건 (전체 후보 \(ranked.count)):") // allow:debug
        for c in candidates { print("  \(c.id.prefix(8))  \((c.title ?? "").prefix(50))") } // allow:debug
        return
    }
    runVerifierEngine(root: root, candidates: candidates, eventLog: eventLog)
}

private func selectVerifierCandidates(
    ranked: [(LedgerObject, LedgerStrength)],
    eventLog: EventLog
) -> [LedgerObject] {
    let recentlySelected = eventLog.subjectsWithEvent(
        rel: "재검증 선정", since: Date().addingTimeInterval(-7 * 86400))
    let rankedIDs = ranked.map(\.0.id)
    let selectedIDs = EventLog.rotatedTargets(
        ranked: rankedIDs, recentlySelected: recentlySelected, limit: 12)
    let byID = Dictionary(uniqueKeysWithValues: ranked.map { ($0.0.id, $0.0) })
    let candidates = selectedIDs.compactMap { byID[$0] }
    for id in selectedIDs {
        try? eventLog.append(Event(writer: "verifier", subject: id, rel: "재검증 선정", level: .step))
    }
    let skipped = recentlySelected.intersection(Set(rankedIDs)).count
    if skipped > 0 { print("순환 선정: 최근 선정 \(skipped)건 뒤로 미룸") } // allow:debug
    return candidates
}

private func runVerifierEngine(root: URL, candidates: [LedgerObject], eventLog: EventLog) {
    let targets = candidates.map(\.id).joined(separator: "\n")
    let history = root.appendingPathComponent(".runs/history")
    do {
        try FileManager.default.createDirectory(at: history, withIntermediateDirectories: true)
    } catch {
        fputs("warning: createDirectory \(history.path): \(error.localizedDescription)\n", stderr)
    }
    let stamp = nowISO().replacingOccurrences(of: ":", with: "").prefix(15)
    let logURL = history.appendingPathComponent("verifier-\(stamp).log")
    writeStatus(root: root, label: "verifier — 근거 재방문 검증 중", detail: "신선도 낮은 근거 \(candidates.count)건 origin 재방문")
    runEngine(role: "verifier", root: root, prompt: """
        너는 verifier 다(.agents/roles/verifier.md). run 카드 규약(AGENTS.md)을 지켜라: \
        ① 'run: 주간 재검증' 발행(batch 발급) ② 아래 각 근거를 show 로 읽고 origin 이 http 면 재방문해 대조 — \
        맞으면 supports(재현), 틀렸으면 contradicts(반박) 를 사유와 함께 발행. 재방문 불가면 건너뛰고 사유 기록. \
        ③ 종료 요약 발행(확신도/어려웠던 점/배운 점).

        대상:
        \(targets)
        """, logURL: logURL)
    clearStatus(root: root)
    print("\(nowISO()) verifier tick 완료 — 로그: \(logURL.path)") // allow:debug
}

private func tickRetrospective(root: URL) {
    let log = EventLog(root: root)
    guard !log.tail(20).isEmpty else { print("\(nowISO()) 사건 없음 — 회고 생략"); return } // allow:debug
    writeStatus(root: root, label: "retrospective — 경험 회고 중", detail: "사건 로그에서 경험칙 추출")
    runEngine(role: "retrospective", root: root, prompt: """
        retrospective 역할(.agents/roles/retrospective.md)을 수행하라. `event tree`·`event tail`·`learn` 으로 \
        최근 작업 성공/실패와 지표를 읽고, 성공↔실패 궤적을 대조해 경험칙을 뽑아 '회고: <교훈>' 으로 \
        발행하라(관찰·경험칙·적용대상, 근거 cite, 인식론 표기). 반복 실패가 뚜렷하면 해당 역할 정의 \
        수정요청도 발행하라. 자기강화 오류 주의: 표본 얇으면 〔불확실〕.
        """)
    clearStatus(root: root)
}

private func tickReaper(store: LedgerStore, root: URL) {
    let statusDir = root.appendingPathComponent(".runs/status")
    let alive = ((try? FileManager.default.contentsOfDirectory(atPath: statusDir.path)) ?? [])
        .contains { $0.hasSuffix(".json") }
    let legacy = FileManager.default.fileExists(atPath: root.appendingPathComponent(".runs/status.json").path)
    guard !alive && !legacy else { print("러너 하트비트 있음 — 개입 안 함"); return } // allow:debug

    var reaped = reapStrandedBatches(store: store, root: root)
    reaped += reapStrandedEvents(root: root)
    if reaped == 0 { print("\(nowISO()) 좌초 run 없음") } // allow:debug
}

private func reapStrandedBatches(store: LedgerStore, root: URL) -> Int {
    let objects = store.scan()
    var byBatch: [String: [LedgerObject]] = [:]
    for object in objects {
        if let batch = object.batch { byBatch[batch, default: []].append(object) }
    }
    var reaped = 0
    for (batch, members) in byBatch {
        let runs = members.filter { $0.effectiveType == "run" }
        guard runs.count == 1, let start = runs.first else { continue }
        guard let last = members.map(\.published).max(),
              Date().timeIntervalSince(last) > 1800 else { continue }
        let title = (start.title ?? "run:").replacingOccurrences(of: "run: ", with: "")
        let body = """
        수습: 이 run 은 종료 기록 없이 멈췄다 — 마지막 발행 \(LedgerObject.iso.string(from: last)), 하트비트 없음.
        run-reaper 가 사슬을 닫는다. 산출물은 batch \(batch) 그대로 유효하며, 원인은 로그
        (.runs/history 또는 대화기록) 참조. 재개가 필요하면 같은 작업을 새 run 으로 시작하라.
        """
        do {
            let object = try store.publish(author: "run-reaper", title: "run: \(title) 중단 확인", type: "run", body: body, extras: LedgerPublishExtras(cites: [.init(id: start.id, rel: "cites")], batch: batch))
            print("중단 확인 발행: \(object.id.prefix(8))  \(title.prefix(40))") // allow:debug
            reaped += 1
        } catch { fail("\(error)") }
    }
    return reaped
}

private func reapStrandedEvents(root: URL) -> Int {
    let eventLog = EventLog(root: root)
    let stranded = eventLog.openRuns(olderThan: Date().addingTimeInterval(-1800))
    var reaped = 0
    for run in stranded {
        try? eventLog.append(Event(
            writer: "run-reaper", subject: run.subject,
            rel: "좌초 수습", level: .run,
            extras: Event.Extras(parent: run.id, outcome: .fail, attrs: ["reaped": "true"])))
        print("좌초 작업 닫음: \(run.subject) (\(run.rel), 시작 \(LedgerObject.iso.string(from: run.occurred)))") // allow:debug
        reaped += 1
    }
    return reaped
}
