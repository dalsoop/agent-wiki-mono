import Foundation
import MoneyLedgerKit
import SwiftUI

/// 이번 달 고정비(정기구독) 관리 뷰.
/// 이번 달 미반영된 고정비 목록 확인 및 [이번 달 고정비 일괄 반영] 버튼 제공.
public struct RecurringExpenseView: View {
    @Bindable var model: LedgerModel
    @State private var isProcessing = false
    @State private var message: String?

    public init(model: LedgerModel) {
        self.model = model
    }

    public var body: some View {
        let unreflected = model.snapshot.unreflectedSubscriptions

        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if unreflected.isEmpty {
                    allReflectedView
                } else {
                    unreflectedListView(unreflected: unreflected)
                }

                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        } label: {
            HStack {
                Label(model.korean ? "이번 달 고정비 (정기구독)" : "Recurring Expenses", systemImage: "repeat.circle.fill")
                    .font(.headline)
                Spacer()
                if !unreflected.isEmpty {
                    Button {
                        batchApply()
                    } label: {
                        if isProcessing {
                            ProgressView().controlSize(.small)
                        } else {
                            Label(
                                model.korean ? "이번 달 고정비 일괄 반영" : "Reflect All",
                                systemImage: "arrow.right.circle.fill"
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isProcessing)
                }
            }
        }
    }

    private var allReflectedView: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(model.korean ? "이번 달 모든 고정비(정기구독)가 원장에 반영되었습니다." : "All recurring expenses are already recorded this month.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private func unreflectedListView(unreflected: [MoneySubscription]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.korean ? "이번 달 원장에 아직 입력되지 않은 정기 결제입니다:" : "Subscriptions not yet recorded in transactions:")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(unreflected) { sub in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(sub.name).font(.callout.bold())
                            Text(sub.period.label(korean: model.korean))
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.12), in: Capsule())
                        }
                        HStack(spacing: 6) {
                            if let instrumentName = resolveInstrumentName(sub: sub) {
                                Text(instrumentName)
                            }
                            if let next = sub.nextBillingDate {
                                Text("(\(next))")
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(MoneyAmount.format(minor: sub.amountMinor, currency: sub.currency))
                        .font(.callout.monospacedDigit().bold())

                    Button(model.korean ? "반영" : "Apply") {
                        applySingle(sub: sub)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isProcessing)
                }
                .padding(8)
                .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func resolveInstrumentName(sub: MoneySubscription) -> String? {
        if let cardID = sub.paymentCardID, let card = model.snapshot.cards.first(where: { $0.id == cardID }) {
            return "\(card.name)(\(card.issuer))"
        }
        if let accID = sub.paymentAccountID, let acc = model.snapshot.accounts.first(where: { $0.id == accID }) {
            return "\(acc.name)(\(acc.bank))"
        }
        return nil
    }

    private func applySingle(sub: MoneySubscription) {
        isProcessing = true
        Task {
            let error = await model.applyRecurringExpense(sub)
            isProcessing = false
            if let error {
                message = "오류: \(error)"
            } else {
                message = "[\(sub.name)] 반영 완료"
            }
        }
    }

    private func batchApply() {
        isProcessing = true
        Task {
            let (applied, error) = await model.applyAllRecurringExpenses()
            isProcessing = false
            if let error {
                message = "일괄 반영 중 오류: \(error)"
            } else {
                message = "\(applied)건의 고정비가 이번 달 원장에 반영되었습니다."
            }
        }
    }
}
