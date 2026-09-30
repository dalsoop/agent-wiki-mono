import AppKit
import Foundation
import KnowledgeBaseWikiCore
import StateMirrorKit
import StateRootKit
import SwiftUI

// 정제 뎁스 — 수집→선별→정제→검증→확립
extension LedgerModel {
    // MARK: - 정제 뎁스 (수집 → 선별 → 정제 → 검증 → 확립)

    static let screenRel = "screens"
    static let digestRel = "digests"

    /// 이 계보에 선별 스탬프가 있나.
    private func hasScreenStamp(_ lineageIDs: Set<String>) -> Bool {
        objects.contains { object in
            object.cites.contains { $0.rel == Self.screenRel && lineageIDs.contains($0.id) }
        }
    }

    /// 수집물인가 — 외부 유입(http) 또는 붙여넣기 원문(paste:). 둘 다 '미선별이면 수집함'.
    static func isCaptureOrigin(_ origin: String?) -> Bool {
        guard let origin else { return false }
        return origin.hasPrefix("http") || origin.hasPrefix("paste:")
    }

    /// 수집함 큐 — 수집물(http 유입 + paste 원문) 중 아직 선별 안 된 것.
    var triageQueue: [(document: LedgerDocument, strength: EvidenceStrength)] {
        evidenceDocuments.filter { row in
            guard Self.isCaptureOrigin(row.document.head.origin) else { return false }
            return !hasScreenStamp(Set(row.document.versions.map(\.id)))
        }
    }

    /// 선별된 원자료 — 작업대 좌측 소스 풀. 수집물이 아니거나(내가 쓴 것), 선별된 수집물.
    var screenedPool: [(document: LedgerDocument, strength: EvidenceStrength)] {
        evidenceDocuments.filter { row in
            guard Self.isCaptureOrigin(row.document.head.origin) else { return true }
            return hasScreenStamp(Set(row.document.versions.map(\.id)))
        }
    }

    /// 정제본 — 근거를 digests 로 인용한 내 기록.
    /// 위키 층 — 사서 소유 문서 (개념 페이지·색인).
    /// 위키 층 = 개념·엔티티·색인 지식 타입만. 저자 무관.
    /// ⚠ 예전엔 author=="wiki-maintainer" 로 넣어 그 에이전트가 낸 run·checkpoint·evidence·
    /// note·decision 까지 위키로 샜다(사건성 발행물이 위키에 뜨던 버그). 타입으로 못 박는다.
    var wikiDocuments: [LedgerDocument] {
        documentsRaw.filter { doc in
            ["concept", "entity", "index"].contains(doc.head.effectiveType ?? "")
                && doc.head.retracts == nil
        }
    }

    /// 플레이북 층 — 재현 가능한 작업 절차(walkthrough-recorder 등이 발행하는 type:playbook).
    /// 지식(개념·근거)도 사건기록(run·checkpoint)도 아닌 독립 범주로 구분해 보여준다.
    var playbookDocuments: [LedgerDocument] {
        documentsRaw.filter { $0.head.effectiveType == "playbook" && $0.head.retracts == nil }
    }

    /// 플레이북 템플릿의 실행 표본 — instance-of 로 이 템플릿(개정 계보 전체)을 인용한
    /// playbook-run 들(최신순). 템플릿이 재발행으로 supersede 돼도 옛 실행본이 옛 판을
    /// 인용하므로, head 뿐 아니라 계보의 모든 판 id 로 매칭한다.
    /// 데이터셋: "같은 방법이 반복 통했는지" 를 표본으로 본다.
    func playbookRuns(ofLineage lineageIDs: Set<String>) -> [LedgerObject] {
        objects.filter { obj in
            obj.effectiveType == "playbook-run" && obj.retracts == nil
                && obj.cites.contains { lineageIDs.contains($0.id) && $0.rel == "instance-of" }
        }.sorted { $0.published > $1.published }
    }

    /// 후행 플레이북 — requires 로 이 템플릿(계보 전체)을 인용한 다른 플레이북 템플릿들.
    func playbookDependents(ofLineage lineageIDs: Set<String>) -> [LedgerObject] {
        objects.filter { obj in
            obj.effectiveType == "playbook" && obj.retracts == nil
                && obj.cites.contains { lineageIDs.contains($0.id) && $0.rel == "requires" }
        }.sorted { ($0.title ?? "") < ($1.title ?? "") }
    }

    var digestDocuments: [LedgerDocument] {
        myDocuments.filter { document in
            document.head.cites.contains { $0.rel == Self.digestRel }
        }
    }

    /// 킵 — 선별 스탬프 발행. 판단 기록 규약: 근거 서술 필수.
    func screenIn(_ document: LedgerDocument, rationale: String) {
        guard let store else { return }
        let reason = rationale.trimmingCharacters(in: .whitespaces)
        guard !reason.isEmpty else {
            errorMessage = "선별 사유가 필요합니다 — 판단은 근거와 함께 기록됩니다"
            return
        }
        _ = try? store.publish(
            author: "human", title: "선별: \(document.title.replacingOccurrences(of: "근거: ", with: ""))",
            body: reason,
            cites: [.init(id: document.head.id, rel: Self.screenRel)])
        refresh()
    }

    /// 이 문서와 같은 작업 묶음(batch)의 대화기록 — 판단의 사고 원문 링크.
    func conversationRecord(batch: String?) -> LedgerDocument? {
        guard let batch else { return nil }
        guard let object = objects.first(where: {
            $0.batch == batch && ($0.title?.hasPrefix("근거: 대화기록") == true)
        }) else { return nil }
        return documentsRaw.first { doc in doc.versions.contains { $0.id == object.id } }
    }

    /// 버림 — 철회 발행(사유 본문). 역사에 남는다.
    func discard(_ document: LedgerDocument, reason: String) {
        guard let store else { return }
        _ = try? store.publish(
            author: "human", title: "버림: \(document.title.replacingOccurrences(of: "근거: ", with: ""))",
            body: reason.isEmpty ? "triage discard" : reason,
            retracts: document.head.id)
        refresh()
    }

    /// 정제본 발행 — 선별 원자료들을 digests 로 인용.
    func publishDigest(title: String, body: String, citing evidenceIDs: [String]) {
        guard let store, !evidenceIDs.isEmpty else { return }
        do {
            let object = try store.publish(
                author: "human", title: title, body: body,
                cites: evidenceIDs.map { .init(id: $0, rel: Self.digestRel) })
            refresh()
            area = .review
            selectedDocumentID = object.id
            errorMessage = nil
        } catch {
            errorMessage = "정제본 발행 실패: \(error)"
        }
    }

    /// 확립 게이트 — 재현≥2 · 반박 0 · 24시간 경과 (SwarmVault 5중 게이트의 축약).
    struct Gate {
        let supports: Int
        let contradicts: Int
        let ageHours: Double
        var passed: Bool { supports >= 2 && contradicts == 0 && ageHours >= 24 }
    }

    func gate(of document: LedgerDocument) -> Gate {
        let strength = strength(of: document) ?? EvidenceStrength(
            supportCount: 0, contradictCount: 0, lastReinforcedAt: document.head.published)
        return Gate(
            supports: strength.supportCount,
            contradicts: strength.contradictCount,
            ageHours: Date().timeIntervalSince(document.head.published) / 3_600)
    }

    /// 심사대: 정제본이 인용한 근거별 검증 상태.
    struct ReviewRow: Identifiable {
        let evidence: LedgerObject
        let supports: Int
        let contradicts: Int
        var id: String { evidence.id }
        var status: String { contradicts > 0 ? "반박" : supports > 0 ? "검증됨" : "미검증" }
    }

    func reviewRows(of digest: LedgerDocument) -> [ReviewRow] {
        guard let store else { return [] }
        return digest.head.cites.filter { $0.rel == Self.digestRel }.compactMap { cite in
            guard let evidence = objects.first(where: { $0.id == cite.id }) else { return nil }
            let strength = store.strength(objects, of: evidence)
            return ReviewRow(evidence: evidence,
                             supports: strength.supportCount, contradicts: strength.contradictCount)
        }
    }

    /// 검증 요청 — verifier 를 백그라운드로 소환 (결과는 원장 발행으로 돌아온다).
    func requestVerification(of evidence: LedgerObject) {
        guard let root = rootURL else { return }
        // TODO(commandkit): migrate raw Process() to ProcessCommandRunner — see swiftkit/Documentation/command-kit.md
        let process = Process()
        process.currentDirectoryURL = root
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["claude", "-p",
            "verifier 역할을 수행해라: 원장 객체 \(evidence.id) 의 origin 을 재방문해 본문과 대조하고 규약대로 supports 또는 contradicts 를 발행해라."]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = StateRootKit.path(".local/bin") + ":/opt/homebrew/bin:" + (environment["PATH"] ?? "")
        process.environment = environment
        try? process.run()  // fire-and-forget — 결과는 5초 주기 refresh 로 나타난다
    }

}
