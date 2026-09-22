import Foundation
import MoneyLedgerKit
import SwiftUI

/// 거래 탭 — 최근 거래 표 + 사업체 필터 + 검색 + 수정/등록 시트.
struct TransactionsTab: View {
    @Bindable var model: LedgerModel
    @State private var showingAdd = false
    @State private var editingTransaction: MoneyTransaction?
    @State private var searchText = ""

    private var filteredTransactions: [MoneyTransaction] {
        let list = model.snapshot.recentTransactions
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else {
            return list
        }
        let q = searchText.lowercased()
        return list.filter { tx in
            tx.description.lowercased().contains(q) ||
            (tx.category?.lowercased().contains(q) ?? false) ||
            (tx.memo?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Table(filteredTransactions) {
                TableColumn(model.korean ? "유형" : "Kind") { tx in
                    let kind = tx.kind ?? (tx.amountMinor < 0 ? .expense : .income)
                    kindBadge(for: kind)
                }
                .width(60)
                TableColumn(model.korean ? "날짜" : "Date", value: \.date)
                    .width(90)
                TableColumn(model.korean ? "금액" : "Amount") { tx in
                    Text(MoneyAmount.format(minor: tx.amountMinor, currency: tx.currency))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(tx.amountMinor < 0 ? .red : .green)
                }
                .width(100)
                TableColumn(model.korean ? "적요" : "Description", value: \.description)
                TableColumn(model.korean ? "카테고리" : "Category") { tx in
                    Text(tx.category ?? "")
                        .foregroundStyle(.secondary)
                }
                .width(90)
                TableColumn(model.korean ? "사업체" : "Business") { tx in
                    Text(model.snapshot.businessName(for: tx.businessID))
                }
                .width(90)
                TableColumn("") { tx in
                    Menu {
                        Button(model.korean ? "수정" : "Edit") {
                            editingTransaction = tx
                        }
                        Divider()
                        Button(model.korean ? "삭제" : "Delete", role: .destructive) {
                            Task { await model.deleteTransaction(tx) }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                .width(40)
            }
            .overlay {
                if filteredTransactions.isEmpty {
                    emptyState
                }
            }
        }
        .sheet(isPresented: $showingAdd) { TransactionEditorSheet(model: model) }
        .sheet(item: $editingTransaction) { tx in
            TransactionEditSheet(model: model, transaction: tx)
        }
    }

    private func kindBadge(for kind: TransactionKind) -> some View {
        Text(kind.label(korean: model.korean))
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(kindColor(for: kind).opacity(0.15))
            )
            .foregroundStyle(kindColor(for: kind))
    }

    private func kindColor(for kind: TransactionKind) -> Color {
        switch kind {
        case .expense: return .red
        case .income: return .green
        case .transfer: return .blue
        case .settlement: return .orange
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(model.korean ? "적요·카테고리·메모 검색" : "Search description, category...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
            .frame(maxWidth: 260)

            if !model.snapshot.businesses.isEmpty {
                BusinessPicker(
                    label: model.korean ? "사업체" : "Business",
                    noneLabel: model.korean ? "(전체)" : "(all)",
                    businesses: model.snapshot.businesses,
                    selection: $model.transactionBusinessFilter
                )
                .frame(maxWidth: 200)
                .onChange(of: model.transactionBusinessFilter) {
                    Task { await model.refresh() }
                }
            }
            Spacer()
            Button {
                showingAdd = true
            } label: {
                Label(model.korean ? "거래 추가" : "Add transaction", systemImage: "plus")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        let isSearching = !searchText.isEmpty
        let filtered = model.transactionBusinessFilter != nil
        let title = isSearching
            ? (model.korean ? "'\(searchText)' 검색 결과 없음" : "No results for '\(searchText)'")
            : (filtered
                ? (model.korean ? "이 사업체의 거래 없음" : "No transactions for this business")
                : (model.korean ? "거래 없음" : "No transactions"))
        let description = isSearching
            ? (model.korean ? "검색어를 변경하거나 지워보세요." : "Try a different search term.")
            : (filtered
                ? (model.korean ? "위 사업체 필터를 '(전체)'로 바꾸세요." : "Switch the filter to '(all)'.")
                : (model.korean ? "위 '거래 추가' 버튼을 눌러 첫 거래를 입력하세요." : "Click 'Add transaction' above."))
        return ContentUnavailableView(title, systemImage: "list.bullet.rectangle", description: Text(description))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor))
    }
}
