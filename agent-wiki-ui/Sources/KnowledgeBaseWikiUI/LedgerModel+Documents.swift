import AppKit
import Foundation
import KnowledgeBaseWikiCore
import StateMirrorKit
import SwiftUI

// 문서 파생 — 근거·내 기록·위키·점프
extension LedgerModel {
    // MARK: - 문서 (사용자 단위)

    /// 근거 목록 (author != human) — 강화·감쇠 포함.
    var evidenceDocuments: [(document: LedgerDocument, strength: EvidenceStrength)] {
        guard let store else { return [] }
        // 근거 = 수집·발행·작성 산물만. 검증 스탬프(supports/contradicts 발행)와
        // run 카드(활동 기록)는 근거가 아니다 — 활동 영역에서 보인다.
        var rows = allDocuments.filter { document in
            let head = document.head
            let isStamp = head.cites.contains {
                EvidenceStrength.supportRels.contains($0.rel) || EvidenceStrength.contradictRels.contains($0.rel)
            }
            let isProcess = head.isProcess
            let isEvidence = head.author != "human"
                || ["evidence", "decision"].contains(head.effectiveType ?? "")
            let isWiki = head.author == "wiki-maintainer" || ["concept", "entity", "index"].contains(head.effectiveType ?? "")
            return isEvidence && !isStamp && !isProcess && !isWiki
        }
            .map { ($0, strengthByHead[$0.head.id] ?? store.strength(objects, of: $0.head)) }
        if sortByStrength {
            rows.sort { $0.1.score > $1.1.score }
        }
        return rows
    }

    /// 근거 영역 표시분 — 수집함(미선별 외부 유입)은 제외, 도메인·태그 필터 적용.
    var shelfDocuments: [(document: LedgerDocument, strength: EvidenceStrength)] {
        var rows = screenedPool
        if let domain = evidenceDomainFilter {
            let map = domainByDocument
            rows = rows.filter { map[$0.document.id] == domain }
        }
        if let tag = evidenceTagFilter {
            rows = rows.filter { $0.document.head.tags.contains(tag) }
        }
        if let knowledge = evidenceKnowledgeFilter {
            rows = rows.filter { knowledgeIndex[$0.document.id] == knowledge }
        }
        return rows
    }

    /// 내 기록 (human 저작, 근거 아님).
    /// 내 기록 = 사람이 쓴 순수 메모만. human 저자여도 절차물(역할정의·체크포인트·토론)과
    /// 지식층 발행물(근거·결정)은 각자의 영역(활동·근거)에서 보인다.
    var myDocuments: [LedgerDocument] {
        allDocuments.filter { document in
            let head = document.head
            return head.author == "human"
                && !head.isProcess
                && !["evidence", "decision", "concept", "entity", "index", "playbook"].contains(head.effectiveType ?? "")
        }
    }

    /// 에이전트 활동 — batch 묶음(없으면 단건) 최신순.
    struct ActivityBatch: Identifiable {
        let id: String
        let actor: String
        let publishedAt: Date
        let objects: [LedgerObject]
    }

    var activityBatches: [ActivityBatch] {
        var byBatch: [String: [LedgerObject]] = [:]
        for object in objects where object.author != "human" {
            byBatch[object.batch ?? object.id, default: []].append(object)
        }
        return byBatch.map { key, members in
            ActivityBatch(
                id: key,
                actor: members.first?.author ?? "?",
                publishedAt: members.map(\.published).max() ?? .distantPast,
                objects: members.sorted { ($0.published, $0.id) < ($1.published, $1.id) })
        }
        .sorted { $0.publishedAt > $1.publishedAt }
    }

    /// run 사슬 — 시작 카드·중간 결정·종료(회고) 를 batch 에서 파생.
    struct RunInfo {
        let start: LedgerObject
        let decisions: [LedgerObject]
        let end: LedgerObject?
        let confidence: Double?
        let abandoned: Bool
    }

    func runInfo(batch: ActivityBatch) -> RunInfo? {
        let runs = batch.objects.filter { $0.effectiveType == "run" }
        guard let start = runs.first else { return nil }
        let end = runs.count > 1 ? runs.last : nil
        let decisions = batch.objects.filter { $0.effectiveType == "decision" }
        var confidence: Double?
        if let end {
            for line in end.body.split(separator: "\n") where line.hasPrefix("확신도:") {
                confidence = Double(line.dropFirst(4).trimmingCharacters(in: .whitespaces))
            }
        }
        // 중단 의심: 종료 없음 + 마지막 발행 30분 경과 + 러너 하트비트도 없음
        let stale = end == nil
            && Date().timeIntervalSince(batch.publishedAt) > 1800
            && runnerStatus == nil
        return RunInfo(start: start, decisions: decisions, end: end,
                       confidence: confidence, abandoned: stale)
    }

    /// 이 문서를 향한 토론 발행물 (이의·질문·수정요청) — 답변·개정이 인용하면 사슬로 이어진다.
    func discussions(of document: LedgerDocument) -> [LedgerObject] {
        let lineageIDs = Set(document.versions.map(\.id))
        return objects.filter { object in
            ["objection", "question", "edit-request"].contains(object.effectiveType ?? "")
                && object.cites.contains { lineageIDs.contains($0.id) }
        }.sorted { ($0.published, $0.id) < ($1.published, $1.id) }
    }

    /// 토론에 대한 응답(이 토론을 인용한 발행물).
    func responses(to discussion: LedgerObject) -> [LedgerObject] {
        objects.filter { object in object.cites.contains { $0.id == discussion.id } }
            .sorted { ($0.published, $0.id) < ($1.published, $1.id) }
    }

    enum DiscussionKind: String, CaseIterable, Identifiable {
        case objection = "이의"
        case question = "질문"
        case editRequest = "수정요청"
        var id: String { rawValue }
    }

    /// 위키 페이지에서 바로 대화 — 발행 + (수정요청/질문이면) 사서 즉시 기동.
    func postDiscussion(on document: LedgerDocument, kind: DiscussionKind, text: String) {
        guard let store = legacyWritableStore() else { return }
        do {
            let rel = kind == .objection ? "undercuts" : "discusses"
            let object = try store.publish(
                author: "human",
                title: "\(kind.rawValue): \(document.title)",
                body: text,
                cites: [.init(id: document.head.id, rel: rel)])
            refresh()
            if kind != .objection {
                runAgent(role: "wiki-maintainer",
                         task: "페이지 '\(document.title)' 에 대한 \(kind.rawValue)(객체 \(object.id))를 읽고 처리하라. 답변·개정은 반드시 그 객체를 cite 하라. 이의·수정요청 처리 규약을 따른다.")
            }
        } catch {
            errorMessage = "발행 실패: \(error)"
        }
    }

    /// 복원 — 철회된 원문을 재발행(restores 로 원본 인용). 역사는 그대로.
    func restore(document: LedgerDocument) {
        guard let store = legacyWritableStore() else { return }
        do {
            let head = document.head
            _ = try store.publish(
                author: "human", title: head.title, type: head.effectiveType,
                body: head.body,
                cites: [.init(id: head.id, rel: "restores")],
                origin: head.origin, tags: head.tags)
            refresh()
            recordNavigation()
            area = .evidence
        } catch {
            errorMessage = "복원 실패: \(error)"
        }
    }

    /// 배치 표시명 — run 카드가 있으면 작업명, 없으면 "저자 — N건 발행".

    func batchTitle(_ batch: ActivityBatch) -> String {
        if let run = runInfo(batch: batch) {
            let title = (run.start.title ?? "").replacingOccurrences(of: "run: ", with: "")
            if !title.isEmpty { return String(title.prefix(46)) }
        }
        return "\(batch.actor) — \(batch.objects.count)건 발행"
    }

    /// 활동을 날짜별로 묶는다 (최신 날짜 우선). publish-test 등 시험 저자는 숨김.
    var activityByDay: [(day: String, batches: [ActivityBatch])] {
        let hidden: Set<String> = ["publish-test"]
        let formatter = DateFormatter()
        formatter.dateFormat = "M월 d일 (E)"
        formatter.locale = Locale(identifier: "ko_KR")
        var groups: [String: [ActivityBatch]] = [:]
        var order: [String] = []
        for batch in activityBatches where !hidden.contains(batch.actor) {
            let key = formatter.string(from: batch.publishedAt)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(batch)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    func rollback(batch: ActivityBatch) {
        do {
            try performRestore(batch: batch.id)
            refresh()
        } catch {
            errorMessage = "되돌리기 실패: \(error)"
        }
    }

    /// 근거 발행(사람) — 발행 후 불변. supports 대상이 있으면 재현으로 연결.
    func publishEvidence(
        title: String,
        body: String,
        origin: String? = nil,
        supports supportsID: String?,
        classification: LedgerClassificationInput,
        aliases: [String]
    ) {
        guard let store = legacyWritableStore() else { return }
        do {
            var cites: [LedgerObject.Cite] = []
            if let supportsID { cites.append(.init(id: supportsID, rel: "supports")) }
            let object = try store.publish(
                author: "human", title: "근거: " + title, body: body,
                cites: cites, origin: origin,
                tags: aliases.map { "alias:" + $0 })
            _ = try store.publishScreening(
                author: "human", target: object, classification: classification)
            refresh()
            area = .evidence
            selectedDocumentID = object.id
            errorMessage = nil
        } catch {
            errorMessage = "근거 발행 실패: \(error)"
        }
    }

    /// 기존 근거에 재현/반박 스탬프 발행.
    func reinforce(_ document: LedgerDocument, contradicts: Bool, note: String) {
        guard let store = legacyWritableStore() else { return }
        do {
            _ = try store.publish(
                author: "human",
                title: (contradicts ? "반박: " : "재현: ") + document.title,
                body: note.isEmpty ? (contradicts ? "contradicts" : "supports") : note,
                cites: [.init(id: document.head.id, rel: contradicts ? "contradicts" : "supports")])
            refresh()
        } catch {
            errorMessage = "발행 실패: \(error)"
        }
    }

    /// 이 근거의 생애 이벤트 (타임라인 시각화용).
    struct LifeEvent: Identifiable {
        let id: String
        let date: Date
        let kind: String  // published | supports | contradicts | revised
    }

    func lifeEvents(of document: LedgerDocument) -> [LifeEvent] {
        var events: [LifeEvent] = document.versions.reversed().enumerated().map { index, version in
            LifeEvent(id: version.id, date: version.published, kind: index == 0 ? "published" : "revised")
        }
        let lineageIDs = Set(document.versions.map(\.id))
        for object in objects where !lineageIDs.contains(object.id) {
            for cite in object.cites where lineageIDs.contains(cite.id) {
                if EvidenceStrength.supportRels.contains(cite.rel) {
                    events.append(LifeEvent(id: object.id, date: object.published, kind: "supports"))
                } else if EvidenceStrength.contradictRels.contains(cite.rel) {
                    events.append(LifeEvent(id: object.id, date: object.published, kind: "contradicts"))
                }
            }
        }
        return events.sorted { $0.date < $1.date }
    }

    /// 문서 → 도메인 (분류 스탬프의 "domain: X" 파싱, 파생 캐시).
    var domainByDocument: [String: String] { domainIndex }
    var kindByDocument: [String: String] { kindIndex }
    var knowledgeByDocument: [String: String] { knowledgeIndex }

    var allDomains: [String] {
        Set(domainByDocument.values).sorted()
    }

    var allObjectTags: [String] {
        Set(objects.flatMap(\.tags)).sorted()
    }

    /// id → 객체 (칩 라벨 해석용).
    var objectsByID: [String: LedgerObject] {
        Dictionary(uniqueKeysWithValues: objects.map { ($0.id, $0) })
    }

    /// 폐기(철회)된 문서들 — 근거 영역 "폐기됨" 필터용.
    var retractedDocuments: [(document: LedgerDocument, retraction: LedgerObject)] {
        var rows: [(LedgerDocument, LedgerObject)] = []
        for retraction in objects where retraction.retracts != nil {
            guard let targetID = retraction.retracts,
                  let doc = documentByHead[targetID] else { continue }
            rows.append((doc, retraction))
        }
        return rows.sorted { $0.1.published > $1.1.published }
    }

    /// 이 문서가 폐기됐다면 그 철회 발행(사유 포함).
    func retraction(of document: LedgerDocument) -> LedgerObject? {
        let ids = Set(document.versions.map(\.id))
        return objects.first { $0.retracts.map(ids.contains) == true }
    }

    /// 어떤 객체 id 든 그 문서를 찾아 적절한 영역으로 점프.
}
