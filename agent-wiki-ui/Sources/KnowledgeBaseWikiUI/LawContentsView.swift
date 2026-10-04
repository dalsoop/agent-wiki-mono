import KnowledgeBaseWikiCore
import SwiftUI

/// 목차(ledger 3 원장의 첫 화면) — 모델 `model.law.contents: LawContentsScreen?`, 목차 줄의 기록으로 `model.showLawRecord(id:)`.
/// 맨 위 "판단할 일", 요약(현행 기록·판단 대기·감사 위반), 현행 목차 줄. 표시 모델은 엔진이 배경에서 만들어 `model.law` 에 둔다.
/// 근거: docs/business-rules.md "드리밍"(목차)·"심급제"(대법원 공지·이의 기간)·"사실인정과 4종류"(판단 대기는 위반 아님).
struct LawContentsView: View {
    @Bindable var model: LedgerModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(L(.LawNavContents)).font(.title2.weight(.semibold))
                if let screen = model.law.contents {
                    if screen.isEmptyLedger {
                        LawContentsEmptyState(
                            title: L(.lawContentsEmptyTitle), detail: L(.lawContentsEmptyDesc))
                    } else {
                        LawContentsPendingPanel(model: model, pending: screen.pending)
                        LawContentsSummaryRow(summary: screen.summary)
                        LawContentsLines(model: model, screen: screen)
                    }
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(L(.lawContentsLoading)).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("law-screen-contents")
    }
}

/// 빈 상태 문구.
struct LawContentsEmptyState: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(detail).font(.callout).foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}

/// 맨 위 "판단할 일" — 대법원 대기, 이의 기간 중인 개정안(남은 시간), 열린 드리밍 경보, 자동 드리밍 정지.
private struct LawContentsPendingPanel: View {
    @Bindable var model: LedgerModel
    let pending: LawPendingDecisions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L(.lawContentsPendingTitle), systemImage: "exclamationmark.bubble")
                .font(.headline)
            if pending.isEmpty {
                Text(L(.lawContentsPendingNone)).font(.callout).foregroundStyle(.secondary)
            } else {
                if !pending.supreme.isEmpty {
                    subheading(L(.lawContentsPendingSupreme))
                    ForEach(pending.supreme, id: \.id) { item in
                        LawRecordLink(
                            model: model, id: item.id, text: item.title ?? LawRecordText.shortID(item.target),
                            detail: item.decidableAt.map { L(.lawContentsPendingDecidableAt, LawRecordText.date($0)) })
                    }
                }
                if !pending.objections.isEmpty {
                    subheading(L(.lawContentsPendingObjection))
                    ForEach(pending.objections, id: \.proposal.id) { window in
                        LawRecordLink(
                            model: model, id: window.proposal.id,
                            text: window.proposal.title ?? LawRecordText.shortID(window.proposal.target),
                            detail: L(.lawContentsPendingRemaining, LawRecordText.remaining(window.remaining)))
                    }
                }
                if !pending.alerts.isEmpty {
                    subheading(L(.lawContentsPendingAlerts))
                    ForEach(Array(pending.alerts.enumerated()), id: \.offset) { _, alert in
                        Label(alert, systemImage: "bell")
                            .font(.callout)
                            .textSelection(.enabled)
                    }
                }
                if pending.dreamingPaused {
                    Label(L(.lawContentsPendingPaused), systemImage: "pause.circle")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.orange)
                    ForEach(pending.pausedBy, id: \.self) { id in
                        LawRecordLink(model: model, id: id, text: L(.lawContentsPendingPausedBy))
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (pending.isEmpty ? Color.secondary : Color.orange).opacity(0.08),
            in: RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("law-contents-pending")
    }

    private func subheading(_ text: String) -> some View {
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
    }
}

/// 요약 — 현행 기록 수, 판단 대기 수, 감사 위반 수(판단 대기는 위반 칸에 넣지 않는다).
private struct LawContentsSummaryRow: View {
    let summary: LawLedgerSummary

    var body: some View {
        HStack(spacing: 10) {
            stat(L(.lawContentsSummaryInForce), summary.knowledgeInForce, tint: .primary)
            stat(L(.lawContentsSummaryPending), summary.pendingJudgment, tint: .secondary)
            stat(L(.lawContentsSummaryViolations), summary.violations, tint: summary.violations > 0 ? .red : .secondary)
        }
        .accessibilityIdentifier("law-contents-summary")
    }

    private func stat(_ label: String, _ value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)").font(.title3.weight(.semibold).monospacedDigit()).foregroundStyle(tint)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// 현행 목차 줄. 기록을 가리키는 줄은 눌러서 기록 상세로.
private struct LawContentsLines: View {
    @Bindable var model: LedgerModel
    let screen: LawContentsScreen

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(L(.lawContentsLinesTitle)).font(.headline)
                if screen.isComputed {
                    Text(L(.lawContentsComputed))
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.yellow.opacity(0.2), in: Capsule())
                } else if let promulgated = screen.contentsPromulgated {
                    Text(L(.lawContentsPromulgated, LawRecordText.date(promulgated)))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if screen.lines.isEmpty {
                Text(L(.lawContentsLinesEmpty)).font(.callout).foregroundStyle(.secondary)
            }
            ForEach(screen.lines) { line in
                if let target = line.recordID ?? line.idPrefix {
                    Button {
                        model.showLawRecord(id: target)
                    } label: {
                        Text(line.text)
                            .font(.callout)
                            .foregroundStyle(NamuTheme.internalLink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(line.text)
                        .font(line.text.hasPrefix("#") ? .callout.weight(.semibold) : .callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .accessibilityIdentifier("law-contents-lines")
    }
}
