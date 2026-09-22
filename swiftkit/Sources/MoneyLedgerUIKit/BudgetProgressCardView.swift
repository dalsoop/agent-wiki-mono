import Foundation
import MoneyLedgerKit
import SwiftUI

/// 카테고리별 예산 소진율 게이지 카드 뷰.
/// 카테고리별 예산 한도, 현재 지출, 잔여 금액, 소진율 게이지 바 (초과 시 빨간색 강조 및 경고 배지) 표시.
/// [예산 설정] 간편 시트 연동.
public struct BudgetProgressCardView: View {
    @Bindable var model: LedgerModel
    @State private var showingEditor = false

    public init(model: LedgerModel) {
        self.model = model
    }

    public var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                headerView
                if model.snapshot.budgets.isEmpty {
                    emptyStateView
                } else {
                    budgetListView
                }
            }
            .padding(.vertical, 4)
        } label: {
            cardLabel
        }
        .sheet(isPresented: $showingEditor) {
            BudgetEditorSheet(model: model)
        }
    }

    private var cardLabel: some View {
        HStack {
            Label(model.korean ? "예산 소진율" : "Budget Progress", systemImage: "chart.bar.fill")
                .font(.headline)
            Spacer()
            if model.snapshot.budgetExceededCount > 0 {
                exceededBadge
            }
        }
    }

    private var exceededBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(model.korean ? "초과 \(model.snapshot.budgetExceededCount)건" : "\(model.snapshot.budgetExceededCount) exceeded")
        }
        .font(.caption.bold())
        .foregroundStyle(.red)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.red.opacity(0.12), in: Capsule())
    }

    private var headerView: some View {
        HStack {
            Text(model.korean ? "카테고리별 월간 예산 대비 실제 지출 현황" : "Monthly category spending vs budget limits")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                showingEditor = true
            } label: {
                Label(model.korean ? "예산 설정" : "Set Budgets", systemImage: "slider.horizontal.3")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Text(model.korean ? "설정된 예산이 없습니다." : "No budgets set yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button(model.korean ? "예산 추가하기" : "Add Budget") {
                showingEditor = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var budgetListView: some View {
        VStack(spacing: 12) {
            ForEach(model.snapshot.budgets) { budget in
                BudgetRowView(
                    budget: budget,
                    model: model
                )
            }
        }
    }
}

/// 단일 카테고리 예산 행 및 게이지 바
struct BudgetRowView: View {
    let budget: MoneyBudget
    let model: LedgerModel

    var body: some View {
        let catTotal = model.snapshot.monthCategoryTotals.first {
            $0.category == budget.category && MoneyAmount.normalizedCurrency($0.currency) == MoneyAmount.normalizedCurrency(budget.currency)
        }
        let spentMinor = catTotal.map { $0.totalMinor < 0 ? abs($0.totalMinor) : 0 } ?? 0
        let remainingMinor = budget.amountMinor - spentMinor
        let ratio = budget.amountMinor > 0 ? (Double(spentMinor) / Double(budget.amountMinor)) : 0.0
        let isExceeded = spentMinor > budget.amountMinor
        let pct = ratio * 100.0

        VStack(alignment: .leading, spacing: 6) {
            rowHeader(isExceeded: isExceeded, ratio: ratio, pct: pct)
            gaugeBar(isExceeded: isExceeded, ratio: ratio)
            amountDetails(spentMinor: spentMinor, remainingMinor: remainingMinor, isExceeded: isExceeded)
        }
        .padding(.vertical, 4)
    }

    private func rowHeader(isExceeded: Bool, ratio: Double, pct: Double) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(budget.category)
                .font(.callout.bold())
            if isExceeded {
                statusBadge(text: model.korean ? "초과" : "Exceeded", icon: "exclamationmark.circle.fill", color: .red)
            } else if ratio >= 0.8 {
                warningBadge
            }
            Spacer()
            Text(String(format: "%.1f%%", pct))
                .font(.callout.monospacedDigit().bold())
                .foregroundStyle(isExceeded ? .red : (ratio >= 0.8 ? .orange : .primary))
        }
    }

    private var warningBadge: some View {
        Text(model.korean ? "주의" : "Warning")
            .font(.caption2.bold())
            .foregroundStyle(.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.15), in: Capsule())
    }

    private func statusBadge(text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption2.bold())
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color, in: Capsule())
    }

    private func gaugeBar(isExceeded: Bool, ratio: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.15))
                Capsule()
                    .fill(isExceeded ? Color.red : (ratio >= 0.8 ? Color.orange : Color.accentColor))
                    .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(min(ratio, 1.0)))))
            }
        }
        .frame(height: 8)
    }

    private func amountDetails(spentMinor: Int64, remainingMinor: Int64, isExceeded: Bool) -> some View {
        HStack(spacing: 12) {
            Text((model.korean ? "예산: " : "Limit: ") + MoneyAmount.format(minor: budget.amountMinor, currency: budget.currency))
                .foregroundStyle(.secondary)
            Text((model.korean ? "지출: " : "Spent: ") + MoneyAmount.format(minor: spentMinor, currency: budget.currency))
                .foregroundStyle(isExceeded ? .red : .secondary)
            Spacer()
            Text((model.korean ? "잔여: " : "Left: ") + MoneyAmount.format(minor: remainingMinor, currency: budget.currency))
                .bold()
                .foregroundStyle(isExceeded ? .red : .primary)
        }
        .font(.caption)
    }
}

/// [예산 설정] 간편 시트
struct BudgetEditorSheet: View {
    let model: LedgerModel
    @Environment(\.dismiss) private var dismiss

    @State private var newCategory = ""
    @State private var newAmount = ""
    @State private var newCurrency = "KRW"
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sheetHeader
            Divider()
            formSection
            listSection
            Spacer()
        }
        .frame(width: 460, height: 420)
    }

    private var sheetHeader: some View {
        HStack {
            Text(model.korean ? "예산 설정 및 관리" : "Manage Budgets")
                .font(.headline)
            Spacer()
            Button(model.korean ? "완료" : "Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding([.top, .horizontal])
    }

    private var formSection: some View {
        GroupBox(model.korean ? "예산 추가 / 수정" : "Add / Update Budget") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField(model.korean ? "카테고리 (예: 식비, 교통, 쇼핑)" : "Category", text: $newCategory)
                    TextField(model.korean ? "금액 (예: 500000)" : "Amount", text: $newAmount)
                        .frame(width: 120)
                    TextField(model.korean ? "통화" : "Cur", text: $newCurrency)
                        .frame(width: 60)
                    Button(model.korean ? "저장" : "Save") {
                        saveCurrent()
                    }
                    .buttonStyle(.borderedProminent)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.vertical, 4)
        }
        .padding(.horizontal)
    }

    private var listSection: some View {
        GroupBox(model.korean ? "설정된 예산 목록" : "Existing Budgets") {
            if model.snapshot.budgets.isEmpty {
                Text(model.korean ? "설정된 예산이 없습니다." : "No budgets set yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                budgetItemsList
            }
        }
        .padding(.horizontal)
    }

    private var budgetItemsList: some View {
        List {
            ForEach(model.snapshot.budgets) { b in
                HStack {
                    Text(b.category).bold()
                    Spacer()
                    Text(MoneyAmount.format(minor: b.amountMinor, currency: b.currency))
                    Button(role: .destructive) {
                        Task {
                            _ = await model.deleteBudget(category: b.category, currency: b.currency)
                        }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .listStyle(.plain)
        .frame(height: 160)
    }

    private func saveCurrent() {
        guard !newCategory.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = model.korean ? "카테고리명을 입력하세요" : "Enter category name"
            return
        }
        guard !newAmount.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = model.korean ? "금액을 입력하세요" : "Enter amount"
            return
        }
        do {
            let minor = try MoneyAmount.minorUnits(from: newAmount, currency: newCurrency)
            let b = MoneyBudget(
                category: newCategory.trimmingCharacters(in: .whitespaces),
                amountMinor: minor,
                currency: newCurrency
            )
            Task {
                let err = await model.saveBudget(b)
                if let err {
                    errorMessage = err
                } else {
                    newCategory = ""
                    newAmount = ""
                    errorMessage = nil
                }
            }
        } catch {
            errorMessage = String(describing: error)
        }
    }
}
