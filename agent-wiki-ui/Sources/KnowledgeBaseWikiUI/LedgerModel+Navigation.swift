import AppKit
import Foundation
import KnowledgeBaseWikiCore
import StateMirrorKit
import SwiftUI

// 항해 히스토리 — 뒤로/앞으로 + 브레드크럼
extension LedgerModel {
    // MARK: - 항해 히스토리 (브라우저식 뒤로/앞으로 + 현재 위치)

    struct NavSpot: Equatable {
        let area: LedgerArea
        let documentID: String?
        let agentName: String?
    }


    private var currentSpot: NavSpot {
        NavSpot(area: area, documentID: selectedDocumentID, agentName: selectedAgentName)
    }

    /// 점프 전에 현재 위치를 기록 — 어디서 왔는지 항상 되짚을 수 있다.
    func recordNavigation() {
        backStack.append(currentSpot)
        if backStack.count > 50 { backStack.removeFirst() }
        forwardStack.removeAll()
    }

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    func goBack() {
        guard let spot = backStack.popLast() else { return }
        forwardStack.append(currentSpot)
        apply(spot)
    }

    func goForward() {
        guard let spot = forwardStack.popLast() else { return }
        backStack.append(currentSpot)
        apply(spot)
    }

    private func apply(_ spot: NavSpot) {
        area = spot.area
        selectedDocumentID = spot.documentID
        selectedAgentName = spot.agentName
    }

    /// 현재 위치 문자열 — "위키 › 개념: X" 식 브레드크럼.
    var breadcrumb: String {
        if destination != .knowledge && destination != .contributors {
            return destination.title
        }
        let areaName: String
        switch area {
        case .myNotes: areaName = "내 기록"
        case .evidence: areaName = "근거"
        case .activity: areaName = "활동"
        case .graph: areaName = "관계도"
        case .events: areaName = "사건"
        case .changes: areaName = "최근 변경"
        case .discuss: areaName = "토론"
        case .learning: areaName = "학습"
        case .triage: areaName = "수집함"
        case .review: areaName = "심사대"
        case .agents: areaName = "에이전트"
        case .wiki: areaName = "위키"
        case .trash: areaName = "휴지통"
        case .structure: areaName = "구조"
        case .settings: areaName = "설정"
        }
        if area == .agents, let name = selectedAgentName { return "\(areaName) › \(name)" }
        if let id = selectedDocumentID,
           let doc = documentByHead[id] { return "\(areaName) › \(doc.title)" }
        return areaName
    }

    func jump(toObject id: String) {
        recordNavigation()
        jumpWithoutRecording(toObject: id)
    }

    private func jumpWithoutRecording(toObject id: String) {
        // 스탬프·철회 발행이면 그 대상 문서로
        if let object = objects.first(where: { $0.id == id }) {
            if let target = object.retracts { return jumpWithoutRecording(toObject: target) }
            if let cite = object.cites.first(where: { $0.rel == Self.screenRel }) {
                return jumpWithoutRecording(toObject: cite.id)
            }
        }
        guard let doc = documentsRaw.first(where: { d in d.versions.contains { $0.id == id } })
            ?? retractedDocuments.first(where: { r in r.document.versions.contains { $0.id == id } })?.document
        else { return }
        let head = doc.head
        if head.author == "wiki-maintainer" || ["concept", "entity", "index"].contains(head.effectiveType ?? "") {
            area = .wiki
        } else if head.author == "human" && head.effectiveType != "evidence" {
            area = .myNotes
        } else {
            area = .evidence
        }
        selectedDocumentID = doc.id
    }

    /// 분류·선별 기록 — screens 스탬프 (구조화 사유 전문).
    func classifications(of document: LedgerDocument) -> [LedgerObject] {
        let lineageIDs = Set(document.versions.map(\.id))
        return objects.filter { object in
            object.cites.contains { $0.rel == Self.screenRel && lineageIDs.contains($0.id) }
        }.sorted { $0.published > $1.published }
    }

    /// 재현·반박 내역 — 인용 객체(메모 포함).
    func reinforcements(of document: LedgerDocument) -> [(object: LedgerObject, rel: String)] {
        let lineageIDs = Set(document.versions.map(\.id))
        var rows: [(LedgerObject, String)] = []
        for object in objects where !lineageIDs.contains(object.id) {
            for cite in object.cites where lineageIDs.contains(cite.id) {
                if EvidenceStrength.supportRels.contains(cite.rel)
                    || EvidenceStrength.contradictRels.contains(cite.rel) {
                    rows.append((object, cite.rel))
                }
            }
        }
        return rows.sorted { $0.0.published > $1.0.published }
    }

}
