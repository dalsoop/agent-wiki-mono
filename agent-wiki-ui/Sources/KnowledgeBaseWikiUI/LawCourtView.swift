import KnowledgeBaseWikiCore
import SwiftUI

/// 심급 — 모델 `model.law.court: LawCourtScreen?`, 사건·대상 기록으로 `model.showLawRecord(id:)`.
/// 보기 전용: 항소심 대기, 대법원 대기(공지 시각·이의 기간 종료 시각), 닫힌 건(결정 결과·결정한 모델 또는 사용자 증언).
/// 결정·이의 제기는 화면에서 하지 않는다 — 건 id 를 복사해 채팅에서 요청한다. 근거: docs/business-rules.md "심급제".
struct LawCourtView: View {
    @Bindable var model: LedgerModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L(.LawNavCourt)).font(.title2.weight(.semibold))
                if let court = model.law.court {
                    Label(L(.LawCourtChatHint), systemImage: "bubble.left.and.text.bubble.right")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if court.isEmpty {
                        ContentUnavailableView(
                            L(.LawCourtEmptyTitle), systemImage: "building.columns",
                            description: Text(L(.LawCourtEmptyDesc)))
                    } else {
                        openSection(L(.LawCourtAppellateSection, court.appellate.count), cases: court.appellate, supreme: false)
                        openSection(L(.LawCourtSupremeSection, court.supreme.count), cases: court.supreme, supreme: true)
                        closedSection(court.closed)
                    }
                } else {
                    ProgressView(L(.LawCourtLoading))
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .accessibilityIdentifier("law-screen-court")
    }

    private func openSection(_ title: String, cases: [LawCourtCase], supreme: Bool) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if cases.isEmpty {
                    Text(L(.LawCourtSectionEmpty)).foregroundStyle(.secondary)
                }
                ForEach(cases, id: \.id) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        header(id: item.id, kind: item.kind, title: item.title, finalAppeal: item.isFinalAppeal)
                        LawCourtField(label: L(.LawCourtFiled), value: LawCourtFormat.date(item.filed))
                        if supreme {
                            LawCourtField(label: L(.LawCourtNoticed), value: LawCourtFormat.date(item.noticedAt))
                            if let decidable = item.decidableAt {
                                LawCourtField(label: L(.LawCourtDecidable), value: LawCourtFormat.date(decidable))
                            }
                        }
                        links(caseID: item.id, target: item.target, ruling: nil)
                    }
                    if item.id != cases.last?.id { Divider() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(title).font(.headline)
        }
    }

    private func closedSection(_ cases: [LawClosedCase]) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if cases.isEmpty {
                    Text(L(.LawCourtSectionEmpty)).foregroundStyle(.secondary)
                }
                ForEach(cases, id: \.id) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        header(id: item.id, kind: item.kind, title: item.title, finalAppeal: false)
                        LawCourtField(label: L(.LawCourtFiled), value: LawCourtFormat.date(item.filed))
                        LawCourtField(label: L(.LawCourtDecided), value: LawCourtFormat.date(item.decidedAt))
                        LawCourtField(
                            label: L(.LawCourtOutcome),
                            value: LawCourtFormat.decision(item))
                        decider(item)
                        links(caseID: item.id, target: item.target, ruling: item.ruling.id)
                    }
                    if item.id != cases.last?.id { Divider() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(L(.LawCourtClosedSection, cases.count)).font(.headline)
        }
    }

    /// 결정한 모델(항소심) 또는 사용자 증언(대법원).
    @ViewBuilder private func decider(_ item: LawClosedCase) -> some View {
        if item.level == .supreme || !item.testimonies.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(L(.LawCourtTestimony)).font(.caption).foregroundStyle(.secondary)
                ForEach(item.testimonies, id: \.self) { evidence in
                    Button(String(evidence.prefix(8))) { model.showLawRecord(id: evidence) }
                        .buttonStyle(.link)
                        .font(.caption.monospaced())
                }
            }
        }
        if item.level == .appellate {
            let parts = [item.decidingRuntime, item.decidingModel, item.decidingEffort].compactMap { $0 }
            LawCourtField(
                label: L(.LawCourtDecidingModel),
                value: item.decidingModel == nil ? L(.LawCourtNoModel) : parts.joined(separator: ":"))
        }
    }

    private func header(id: String, kind: LawCourtCaseKind, title: String?, finalAppeal: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(kind == .appeal ? L(.LawCourtKindAppeal) : L(.LawCourtKindProposal))
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
            if finalAppeal {
                Text(L(.LawCourtFinalAppeal)).font(.caption.weight(.semibold)).foregroundStyle(.orange)
            }
            Text(title ?? String(id.prefix(8))).font(.body.weight(.medium)).lineLimit(2)
            Spacer()
            Text(String(id.prefix(8))).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            LawCourtCopyButton(text: id)
        }
    }

    private func links(caseID: String, target: String, ruling: String?) -> some View {
        HStack(spacing: 12) {
            Button(L(.LawCourtOpenCase)) { model.showLawRecord(id: caseID) }
            Button(L(.LawCourtOpenTarget)) { model.showLawRecord(id: target) }
            if let ruling {
                Button(L(.LawCourtOpenRuling)) { model.showLawRecord(id: ruling) }
            }
        }
        .buttonStyle(.link)
        .font(.caption)
    }
}

/// 이름 — 값 한 줄.
struct LawCourtField: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.caption).textSelection(.enabled)
        }
    }
}

/// 심급·드리밍·신빙성 화면이 함께 쓰는 표시 형식(시각·심급·결과 이름).
@MainActor
enum LawCourtFormat {
    static func date(_ date: Date) -> String { date.formatted(date: .abbreviated, time: .shortened) }

    /// `<심급> · <결과>`.
    static func decision(_ item: LawClosedCase) -> String {
        let level: String
        switch item.level {
        case .appellate: level = L(.LawCourtLevelAppellate)
        case .supreme: level = L(.LawCourtLevelSupreme)
        }
        let outcome: String
        switch item.outcome {
        case .uphold: outcome = L(.LawCourtOutcomeUphold)
        case .overturn: outcome = L(.LawCourtOutcomeOverturn)
        case .refer: outcome = L(.LawCourtOutcomeRefer)
        case .approve: outcome = L(.LawCourtOutcomeApprove)
        case .reject: outcome = L(.LawCourtOutcomeReject)
        }
        return "\(level) · \(outcome)"
    }
}
