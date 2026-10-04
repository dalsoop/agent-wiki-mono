import KnowledgeBaseWikiCore
import SwiftUI

/// 드리밍 — 모델 `model.law.dream: LawDreamScreen?`, 묶음 고르기 `model.selectDreamBatch(_:)` → `model.law.batchChanges`,
/// 되돌리기 `model.revertDreamBatch(_:)`, 재개 `model.resumeDreaming()`, 결과 `model.law.actionMessage`·`actionIsError`.
/// 화면의 쓰기는 묶음 되돌리기와 재개뿐이고, 보관된 원장(전신)이면 두 버튼을 숨긴다. 쓰기 게이트·경로 판정은 엔진이 한다.
/// 근거: docs/business-rules.md "드리밍", "공포·개정·폐지·원상회복".
struct LawDreamView: View {
    @Bindable var model: LedgerModel
    @State private var confirmingRevert: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L(.LawNavDream)).font(.title2.weight(.semibold))
                if let dream = model.law.dream {
                    statusSection(dream)
                    if !dream.gaps.isEmpty { setupSection(dream.gaps) }
                    actionResult
                    historySection(dream)
                    if let batch = model.law.selectedBatch {
                        LawDreamBatchSection(
                            model: model, batch: batch, dream: dream,
                            onRevert: { confirmingRevert = batch })
                    }
                } else {
                    ProgressView(L(.LawDreamLoading))
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .sheet(item: Binding(
            get: { confirmingRevert.map(LawDreamRevertRequest.init(batch:)) },
            set: { confirmingRevert = $0?.batch })
        ) { request in
            LawDreamRevertConfirmSheet(
                batch: request.batch, changes: model.law.batchChanges,
                onConfirm: {
                    confirmingRevert = nil
                    model.revertDreamBatch(request.batch)
                },
                onCancel: { confirmingRevert = nil })
        }
        .accessibilityIdentifier("law-screen-dream")
    }

    // MARK: - 상태

    private func statusSection(_ dream: LawDreamScreen) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                LawCourtField(label: L(.LawDreamDevice), value: deviceText(dream))
                LawCourtField(label: L(.LawDreamLastRun), value: dream.lastRunAt.map(LawCourtFormat.date) ?? L(.LawDreamNever))
                LawCourtField(label: L(.LawDreamNextDue), value: dream.nextDueAt.map(LawCourtFormat.date) ?? L(.LawDreamNever))
                LawCourtField(label: L(.LawDreamState), value: dream.paused ? L(.LawDreamPaused) : L(.LawDreamActive))
                if dream.paused, !dream.pausedBy.isEmpty {
                    LawCourtField(label: L(.LawDreamPausedBy), value: dream.pausedBy.map { String($0.prefix(8)) }.joined(separator: ", "))
                }
                LawCourtField(label: L(.LawDreamAI), value: dream.aiLabel ?? L(.LawDreamNotSet))
                LawCourtField(label: L(.LawDreamEndpoint), value: dream.endpointConfigured ? L(.LawDreamConfigured) : L(.LawDreamNotSet))
                if !dream.ledgers.isEmpty {
                    LawCourtField(label: L(.LawDreamLedgers), value: dream.ledgers.joined(separator: ", "))
                }
                if dream.paused, !model.isReadOnlyWorld {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Button(L(.LawDreamResume)) { model.resumeDreaming() }
                            .disabled(!dream.canWrite)
                            .accessibilityIdentifier("law-dream-resume")
                        LawDreamWriteDenials(denials: dream.writeDenials)
                    }
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(L(.LawDreamStatusSection)).font(.headline)
        }
    }

    private func deviceText(_ dream: LawDreamScreen) -> String {
        guard let device = dream.dreamDevice else { return L(.LawDreamNotSet) }
        return "\(device) (\(dream.isDreamDevice ? L(.LawDreamThisDevice) : L(.LawDreamOtherDevice)))"
    }

    private func setupSection(_ gaps: [LawDreamSetupGap]) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(gaps, id: \.self) { gap in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(gapName(gap)).font(.callout.weight(.medium))
                        Text(gap.guidance).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label(L(.LawDreamSetupSection), systemImage: "exclamationmark.triangle").font(.headline)
        }
    }

    private func gapName(_ gap: LawDreamSetupGap) -> String {
        switch gap {
        case .dreamDevice: return L(.LawDreamGapDevice)
        case .ai: return L(.LawDreamGapAI)
        case .storageEndpoint: return L(.LawDreamGapEndpoint)
        }
    }

    /// 되돌리기·재개 결과 — 원장별 줄 그대로.
    @ViewBuilder private var actionResult: some View {
        if let message = model.law.actionMessage, !message.isEmpty {
            GroupBox {
                Text(message)
                    .font(.callout.monospaced())
                    .foregroundStyle(model.law.actionIsError ? .red : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label(
                    model.law.actionIsError ? L(.LawDreamResultError) : L(.LawDreamResult),
                    systemImage: model.law.actionIsError ? "xmark.octagon" : "checkmark.circle"
                )
                .font(.headline)
                .foregroundStyle(model.law.actionIsError ? .red : .primary)
            }
            .accessibilityIdentifier("law-dream-action-result")
        }
    }

    // MARK: - 실행 이력

    @ViewBuilder private func historySection(_ dream: LawDreamScreen) -> some View {
        if dream.runs.isEmpty {
            ContentUnavailableView(
                L(.LawDreamEmptyTitle), systemImage: "moon.zzz", description: Text(L(.LawDreamEmptyDesc)))
        } else {
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(dream.runs) { run in
                        LawDreamRunRow(model: model, run: run)
                        if run.id != dream.runs.last?.id { Divider() }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Text(L(.LawDreamHistorySection)).font(.headline)
            }
        }
    }
}

/// 쓰기 게이트 거부 이유(버튼 옆).
struct LawDreamWriteDenials: View {
    let denials: [String]

    var body: some View {
        if !denials.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(L(.LawDreamWriteDenied)).font(.caption.weight(.semibold))
                ForEach(Array(denials.enumerated()), id: \.offset) { _, denial in Text(denial).font(.caption) }
            }
            .foregroundStyle(.orange)
            .textSelection(.enabled)
            .accessibilityIdentifier("law-dream-write-denials")
        }
    }
}

/// 실행 이력 한 줄 — 묶음 id·적용·버림(이유)·경보·이관. 묶음을 누르면 그 묶음이 바꾼 기록을 읽는다.
struct LawDreamRunRow: View {
    @Bindable var model: LedgerModel
    let run: LawDreamRunEntry

    var body: some View {
        let summary = run.summary
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(LawCourtFormat.date(run.promulgated)).font(.callout.weight(.medium))
                Text(run.world).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(String(run.reportID.prefix(8))) { model.showLawRecord(id: run.reportID) }
                    .buttonStyle(.link)
                    .font(.caption.monospaced())
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(L(.LawDreamBatch)).font(.caption).foregroundStyle(.secondary)
                if let batch = run.batch {
                    Button(batch) { model.selectDreamBatch(model.law.selectedBatch == batch ? nil : batch) }
                        .buttonStyle(.link)
                        .font(.caption.monospaced())
                        .fontWeight(model.law.selectedBatch == batch ? .bold : .regular)
                        .accessibilityIdentifier("law-dream-batch")
                } else {
                    Text(L(.LawDreamNoBatch)).font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 12) {
                Text(L(.LawDreamApplied, summary.appliedCount))
                Text(L(.LawDreamDiscarded, summary.discardedCount))
                Text(L(.LawDreamAlerts, summary.alerts.count)).foregroundStyle(summary.alerts.isEmpty ? .secondary : Color.orange)
                Text(L(.LawDreamMigrations, summary.migrations))
            }
            .font(.caption)
            if !summary.discarded.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L(.LawDreamDiscardedReasons)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(Array(summary.discarded.enumerated()), id: \.offset) { _, item in
                        Text("\(item.proposal) — \(item.reason)").font(.caption).textSelection(.enabled)
                    }
                }
            }
            if !summary.alerts.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L(.LawDreamAlertList)).font(.caption.weight(.semibold)).foregroundStyle(.orange)
                    ForEach(Array(summary.alerts.enumerated()), id: \.offset) { _, alert in
                        Text(alert).font(.caption).textSelection(.enabled)
                    }
                }
            }
        }
    }
}
