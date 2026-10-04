import KnowledgeBaseWikiCore
import SwiftUI

/// 기록 상세(출처 패널) — 모델 `model.law.recordDetail: LawRecordDetail?`(선택 id `model.law.selectedRecordID`), 닫기 `model.closeLawRecord()`.
/// 본문, 작성자·모델 기록, 증언, 현행 사실인정, 4종류, 연혁, 이의·개정안과 결정, 인용 관계. 표시 모델은 엔진이 배경에서 만든다.
/// 근거: docs/business-rules.md "작성자와 모델 기록"·"화자"·"본문 머리 칸"·"관계"·"사실인정과 4종류"·"심급제".
struct LawRecordDetailView: View {
    @Bindable var model: LedgerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button {
                    model.closeLawRecord()
                } label: {
                    Label(L(.lawRecordBack), systemImage: "chevron.backward")
                }
                .buttonStyle(.borderless)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            if let detail = model.law.recordDetail {
                ScrollView {
                    LawRecordDetailContent(model: model, detail: detail)
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L(.LawNavRecordDetail)).font(.title2.weight(.semibold))
                    LawContentsEmptyState(
                        title: L(.lawRecordDetailMissingTitle),
                        detail: L(.lawRecordDetailMissingDesc, model.law.selectedRecordID ?? ""))
                }
                .padding(24)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("law-screen-record-detail")
    }
}

private struct LawRecordDetailContent: View {
    @Bindable var model: LedgerModel
    let detail: LawRecordDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LawRecordDetailHeader(detail: detail)
            Text(detail.record.record.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            LawRecordSection(title: L(.lawRecordProvenanceTitle), isEmpty: false) {
                LawRecordProvenanceFields(provenance: detail.provenance, showsDate: true)
            }
            LawRecordTestimonies(model: model, testimonies: detail.testimonies)
            LawRecordFindingSection(model: model, finding: detail.finding)
            LawRecordSection(title: L(.lawRecordKindTitle), isEmpty: detail.memoryKind == nil) {
                if let kind = detail.memoryKind {
                    Text(LawRecordText.memoryKind(kind)).font(.callout)
                }
            }
            LawRecordHistorySection(model: model, history: detail.history, currentID: detail.record.id)
            LawRecordDisputeSection(model: model, disputes: detail.disputes)
            LawRecordCitationSection(model: model, title: L(.lawRecordCitesTitle), links: detail.cites)
            LawRecordCitationSection(model: model, title: L(.lawRecordCitedByTitle), links: detail.citedBy)
        }
    }
}

private struct LawRecordDetailHeader: View {
    let detail: LawRecordDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(detail.record.record.title ?? LawRecordText.shortID(detail.record.id))
                .font(.title2.weight(.semibold))
                .textSelection(.enabled)
            HStack(spacing: 8) {
                Text(detail.record.id).font(.caption.monospaced()).textSelection(.enabled)
                if let type = detail.record.record.type {
                    Text(type).font(.caption.weight(.semibold))
                }
                Text(detail.world).font(.caption)
                Text(L(detail.isInForce ? .lawRecordInForce : .lawRecordNotInForce))
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background((detail.isInForce ? Color.green : Color.secondary).opacity(0.15), in: Capsule())
            }
            .foregroundStyle(.secondary)
        }
    }
}

/// 작성자·작성자 종류·기기·실행 도구·버전·모델·추론 강도·화자(·공포일). 값이 없는 칸은 그리지 않는다.
struct LawRecordProvenanceFields: View {
    let provenance: LawProvenance
    let showsDate: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            LawRecordField(label: L(.lawRecordAuthor), value: provenance.author)
            LawRecordField(label: L(.lawRecordAuthorKind), value: provenance.authorKind)
            LawRecordField(label: L(.lawRecordDevice), value: provenance.device)
            LawRecordField(label: L(.lawRecordRuntime), value: provenance.runtime)
            LawRecordField(label: L(.lawRecordRuntimeVersion), value: provenance.runtimeVersion)
            LawRecordField(label: L(.lawRecordModel), value: provenance.model)
            LawRecordField(label: L(.lawRecordEffort), value: provenance.effort)
            LawRecordField(label: L(.lawRecordSpeaker), value: provenance.speaker)
            if showsDate {
                LawRecordField(label: L(.lawRecordPromulgated), value: LawRecordText.date(provenance.promulgated))
            }
        }
    }
}

private struct LawRecordTestimonies: View {
    @Bindable var model: LedgerModel
    let testimonies: [LawTestimonyView]

    var body: some View {
        LawRecordSection(title: L(.lawRecordTestimonyTitle), isEmpty: testimonies.isEmpty) {
            ForEach(Array(testimonies.enumerated()), id: \.offset) { _, testimony in
                VStack(alignment: .leading, spacing: 4) {
                    LawRecordLink(model: model, id: testimony.evidenceID, text: testimony.world ?? "")
                    if !testimony.found {
                        Text(L(.lawRecordTestimonyNotFound)).font(.caption).foregroundStyle(.orange)
                    }
                    if let quote = testimony.quote, !quote.isEmpty {
                        Text(quote)
                            .font(.callout.italic())
                            .textSelection(.enabled)
                            .padding(.leading, 8)
                            .overlay(alignment: .leading) {
                                Rectangle().fill(.secondary.opacity(0.4)).frame(width: 2)
                            }
                    }
                    LawRecordField(label: L(.lawRecordTestimonySession), value: testimony.session)
                    LawRecordField(label: L(.lawRecordTestimonyUtteranceAt), value: testimony.utteranceAt)
                    LawRecordField(label: L(.lawRecordRuntime), value: testimony.runtime)
                    LawRecordField(label: L(.lawRecordDevice), value: testimony.device)
                    LawRecordField(label: L(.lawRecordSpeaker), value: testimony.speaker)
                    if testimony.exhibitMissing {
                        Label(L(.lawRecordExhibitMissing), systemImage: "icloud.slash")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

private struct LawRecordFindingSection: View {
    @Bindable var model: LedgerModel
    let finding: LawFindingView?

    var body: some View {
        LawRecordSection(title: L(.lawRecordFindingTitle), isEmpty: finding == nil) {
            if let finding {
                LawRecordLink(model: model, id: finding.id, text: finding.subject ?? "")
                LawRecordField(label: L(.lawRecordFindingSubject), value: finding.subject)
                LawRecordField(label: L(.lawRecordFindingCertainty), value: finding.certainty)
                LawRecordField(label: L(.lawRecordFindingDomain), value: finding.domain)
                LawRecordField(label: L(.lawRecordFindingFrom), value: finding.effectiveFrom)
                LawRecordField(label: L(.lawRecordFindingUntil), value: finding.effectiveUntil)
                LawRecordField(label: L(.lawRecordFindingReason), value: finding.reason)
                LawRecordField(label: L(.lawRecordFindingJudgedBy), value: finding.provenance.author)
                LawRecordField(label: L(.lawRecordModel), value: finding.provenance.model)
            }
        }
    }
}

/// 연혁 — 주 사슬의 판(현행 표시)과 그 판이 병합한 갈래.
private struct LawRecordHistorySection: View {
    @Bindable var model: LedgerModel
    let history: [LawHistoryEntry]
    let currentID: String

    var body: some View {
        LawRecordSection(title: L(.lawRecordHistoryTitle), isEmpty: history.isEmpty) {
            ForEach(history, id: \.record.id) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: entry.record.id == currentID ? "circle.inset.filled" : "circle")
                            .font(.caption)
                            .foregroundStyle(entry.isInForce ? .green : .secondary)
                        LawRecordLink(
                            model: model, id: entry.record.id,
                            text: entry.record.record.title ?? "",
                            detail: [
                                LawRecordText.date(entry.record.record.promulgated), entry.record.record.author,
                                entry.isInForce ? L(.lawRecordInForce) : nil,
                            ].compactMap { $0 }.joined(separator: " · "))
                    }
                    ForEach(entry.mergedBranches, id: \.id) { branch in
                        LawRecordLink(
                            model: model, id: branch.id,
                            text: L(.lawRecordHistoryMerged, branch.record.title ?? ""),
                            detail: LawRecordText.date(branch.record.promulgated))
                            .padding(.leading, 22)
                    }
                }
            }
        }
    }
}

/// 이 기록을 다툰 이의·개정안과 그 결정.
private struct LawRecordDisputeSection: View {
    @Bindable var model: LedgerModel
    let disputes: [LawDisputeView]

    var body: some View {
        LawRecordSection(title: L(.lawRecordDisputeTitle), isEmpty: disputes.isEmpty) {
            ForEach(disputes, id: \.caseRecord.id) { dispute in
                VStack(alignment: .leading, spacing: 3) {
                    LawRecordLink(
                        model: model, id: dispute.caseRecord.id,
                        text: dispute.caseRecord.record.title ?? "",
                        detail: [LawRecordText.caseKind(dispute.kind), status(dispute)].joined(separator: " · "))
                    ForEach(dispute.rulings, id: \.id) { ruling in
                        LawRecordLink(
                            model: model, id: ruling.id,
                            text: L(.lawRecordDisputeRuling, ruling.record.title ?? ""),
                            detail: [
                                LawRecordText.date(ruling.record.promulgated), ruling.record.author, ruling.record.model,
                            ].compactMap { $0 }.joined(separator: " · "))
                            .padding(.leading, 16)
                    }
                }
            }
        }
    }

    private func status(_ dispute: LawDisputeView) -> String {
        if let closed = dispute.closed {
            return L(
                .lawRecordDisputeClosed, LawRecordText.level(closed.level.rawValue),
                LawRecordText.outcome(closed.outcome.rawValue), LawRecordText.date(closed.decidedAt))
        }
        if let level = dispute.openLevel {
            return L(.lawRecordDisputeOpen, LawRecordText.level(level.rawValue))
        }
        return L(.lawRecordDisputeUnknown)
    }
}

/// 인용 관계 한 갈래(인용한 것 또는 인용된 것).
private struct LawRecordCitationSection: View {
    @Bindable var model: LedgerModel
    let title: String
    let links: [LawCitationLink]

    var body: some View {
        LawRecordSection(title: title, isEmpty: links.isEmpty) {
            ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                LawRecordLink(
                    model: model, id: link.id, text: link.title ?? "",
                    detail: [link.rel, place(link)].compactMap { $0 }.joined(separator: " · "))
            }
        }
    }

    private func place(_ link: LawCitationLink) -> String? {
        guard let world = link.world else { return L(.lawRecordCitationNotFound) }
        return link.isPredecessor ? L(.lawRecordCitationPredecessor, world) : world
    }
}
