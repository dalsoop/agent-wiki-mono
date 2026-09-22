import Foundation
import MoneyLedgerKit
import SwiftUI

/// 기존 거래 수정 모달 시트.
public struct TransactionEditSheet: View {
    public let model: LedgerModel
    public let transaction: MoneyTransaction
    @Environment(\.dismiss) private var dismiss

    @State private var date: Date
    @State private var amountText: String
    @State private var isOutflow: Bool
    @State private var descriptionText: String
    @State private var category: String
    @State private var memo: String
    @State private var errorMessage: String?

    public init(model: LedgerModel, transaction: MoneyTransaction) {
        self.model = model
        self.transaction = transaction
        let txDate = LedgerDate.toDate(transaction.date) ?? Date.now
        _date = State(initialValue: txDate)
        _amountText = State(initialValue: String(abs(transaction.amountMinor)))
        _isOutflow = State(initialValue: transaction.amountMinor < 0)
        _descriptionText = State(initialValue: transaction.description)
        _category = State(initialValue: transaction.category ?? "")
        _memo = State(initialValue: transaction.memo ?? "")
    }

    public var body: some View {
        EditorSheet(
            title: model.korean ? "거래 수정" : "Edit transaction",
            korean: model.korean,
            errorMessage: errorMessage,
            onSave: {
                guard let amountValue = Int64(amountText.filter { $0.isNumber }), amountValue > 0 else {
                    errorMessage = model.korean ? "유효한 금액을 입력하세요" : "Valid amount is required"
                    return
                }
                let signedAmount = isOutflow ? -amountValue : amountValue
                var updated = transaction
                updated.date = LedgerDate.format(date)
                updated.amountMinor = signedAmount
                updated.description = descriptionText.trimmingCharacters(in: .whitespaces)
                updated.category = category.isEmpty ? nil : category
                updated.memo = memo.isEmpty ? nil : memo

                Task {
                    if let err = await model.updateTransaction(updated) {
                        errorMessage = err
                    } else {
                        dismiss()
                    }
                }
            },
            onCancel: { dismiss() }
        ) {
            DatePicker(model.korean ? "날짜" : "Date", selection: $date, displayedComponents: .date)
            Picker(model.korean ? "구분" : "Direction", selection: $isOutflow) {
                Text(model.korean ? "출금(지출)" : "Out").tag(true)
                Text(model.korean ? "입금(수입)" : "In").tag(false)
            }
            .pickerStyle(.segmented)
            TextField(model.korean ? "금액 (최소단위)" : "Amount", text: $amountText)
            TextField(model.korean ? "적요" : "Description", text: $descriptionText)
            TextField(model.korean ? "카테고리" : "Category", text: $category)
            TextField(model.korean ? "메모" : "Memo", text: $memo)
        }
    }
}
