import Foundation
import MoneyLedgerKit
import SwiftUI

// GUI 직접 등록 — CLI 와 같은 LedgerStore 경로를 호출한다(4면 계약: GUI 는 별도 로직 금지).

extension LedgerModel {
    /// 저장 실패 시 사용자 표시용 메시지, 성공이면 nil.
    public func saveAccount(_ account: MoneyAccount) async -> String? {
        await mutate { store in try await store.save(account: account) }
    }

    public func saveCard(_ card: MoneyCard) async -> String? {
        await mutate { store in try await store.save(card: card) }
    }

    public func saveSubscription(_ subscription: MoneySubscription) async -> String? {
        await mutate { store in try await store.save(subscription: subscription) }
    }

    public func setSubscriptionStatus(_ subscription: MoneySubscription, _ status: SubscriptionStatus) async {
        var updated = subscription
        updated.status = status
        _ = await mutate { store in try await store.save(subscription: updated) }
    }

    public func setAccountArchived(_ account: MoneyAccount, _ archived: Bool) async {
        var updated = account
        updated.archived = archived
        _ = await mutate { store in try await store.save(account: updated) }
    }

    public func setCardArchived(_ card: MoneyCard, _ archived: Bool) async {
        var updated = card
        updated.archived = archived
        _ = await mutate { store in try await store.save(card: updated) }
    }

    public func deleteTransaction(_ tx: MoneyTransaction) async {
        _ = await mutate { store in try await store.deleteTransaction(id: tx.id) }
    }

    public func updateTransaction(_ tx: MoneyTransaction) async -> String? {
        await mutate { store in try await store.update(transaction: tx) }
    }

    public func saveBudget(_ budget: MoneyBudget) async -> String? {
        await mutate { store in try await store.save(budget: budget) }
    }

    public func deleteBudget(category: String, currency: String = "KRW") async -> String? {
        await mutate { store in try await store.deleteBudget(category: category, currency: currency) }
    }

    public func deleteBudget(id: String) async -> String? {
        await mutate { store in try await store.deleteBudget(id: id) }
    }

    public func applyRecurringExpense(_ sub: MoneySubscription) async -> String? {
        await mutate { store in
            let date: String
            let today = LedgerDate.today()
            if let next = sub.nextBillingDate, next.hasPrefix(snapshot.month) {
                date = next
            } else {
                date = today
            }
            let tx = MoneyTransaction(
                id: UUID().uuidString.lowercased(),
                stamp: .init(date: date),
                amount: .init(amountMinor: -abs(sub.amountMinor), currency: sub.currency),
                parties: .init(accountID: sub.paymentAccountID, cardID: sub.paymentCardID, businessID: sub.businessID),
                narrative: .init(description: sub.name, category: "고정비", memo: "정기구독 고정비 반영"),
                kind: .expense,
                contentHash: ContentHash.transactionHash(
                    date: date,
                    time: nil,
                    amountMinor: -abs(sub.amountMinor),
                    currency: sub.currency,
                    instrumentID: sub.paymentAccountID ?? sub.paymentCardID ?? "",
                    description: sub.name,
                    balanceAfterMinor: nil
                )
            )
            _ = try await store.insert(transaction: tx)
        }
    }

    public func applyAllRecurringExpenses() async -> (applied: Int, error: String?) {
        let unreflected = snapshot.unreflectedSubscriptions
        guard !unreflected.isEmpty else { return (0, nil) }
        var appliedCount = 0
        do {
            let store = try LedgerStore(context: context)
            for sub in unreflected {
                let date: String
                let today = LedgerDate.today()
                if let next = sub.nextBillingDate, next.hasPrefix(snapshot.month) {
                    date = next
                } else {
                    date = today
                }
                let tx = MoneyTransaction(
                    id: UUID().uuidString.lowercased(),
                    stamp: .init(date: date),
                    amount: .init(amountMinor: -abs(sub.amountMinor), currency: sub.currency),
                    parties: .init(accountID: sub.paymentAccountID, cardID: sub.paymentCardID, businessID: sub.businessID),
                    narrative: .init(description: sub.name, category: "고정비", memo: "정기구독 고정비 반영"),
                    kind: .expense,
                    contentHash: ContentHash.transactionHash(
                        date: date,
                        time: nil,
                        amountMinor: -abs(sub.amountMinor),
                        currency: sub.currency,
                        instrumentID: sub.paymentAccountID ?? sub.paymentCardID ?? "",
                        description: sub.name,
                        balanceAfterMinor: nil
                    )
                )
                let outcome = try await store.insert(transaction: tx)
                if !outcome.duplicate {
                    appliedCount += 1
                }
            }
            await refresh()
            return (appliedCount, nil)
        } catch {
            return (appliedCount, String(describing: error))
        }
    }

    public func exportCSVData(fromDate: String? = nil, toDate: String? = nil) async throws -> Data {
        let store = try LedgerStore(context: context)
        let accounts = try await store.accounts(includeArchived: true)
        let cards = try await store.cards(includeArchived: true)
        let transactions = try await store.transactions(TransactionQuery(fromDate: fromDate, toDate: toDate))
        return LedgerExport.csv(transactions: transactions, accounts: accounts, cards: cards)
    }

    public func exportCSV(to url: URL, fromDate: String? = nil, toDate: String? = nil) async -> String? {
        do {
            let data = try await exportCSVData(fromDate: fromDate, toDate: toDate)
            try data.write(to: url)
            return nil
        } catch {
            return String(describing: error)
        }
    }

    public struct AddTransactionOutcome: Sendable {
        public let errorMessage: String?
        public let duplicate: Bool
    }

    public struct AddTransactionRequest: Sendable {
        public struct Amount: Sendable {
            public var text: String
            public var isOutflow: Bool
            public var currency: String
            public init(text: String, isOutflow: Bool, currency: String) {
                self.text = text
                self.isOutflow = isOutflow
                self.currency = currency
            }
        }

        public struct Parties: Sendable {
            public var accountID: String?
            public var cardID: String?
            public var businessID: String?
            public init(accountID: String?, cardID: String?, businessID: String? = nil) {
                self.accountID = accountID
                self.cardID = cardID
                self.businessID = businessID
            }
        }

        public struct Narrative: Sendable {
            public var description: String
            public var category: String?
            public var memo: String?
            public init(description: String, category: String?, memo: String?) {
                self.description = description
                self.category = category
                self.memo = memo
            }
        }

        public var date: String
        public var amount: Amount
        public var parties: Parties
        public var narrative: Narrative
        public var allowDuplicate: Bool

        public init(
            date: String,
            amount: Amount,
            parties: Parties,
            narrative: Narrative,
            allowDuplicate: Bool
        ) {
            self.date = date
            self.amount = amount
            self.parties = parties
            self.narrative = narrative
            self.allowDuplicate = allowDuplicate
        }
    }

    /// CLI `tx add` 와 동일 계약 — 같은 내용이면 중복으로 알리고 저장하지 않는다.
    /// allowDuplicate 는 CLI --allow-duplicate 처럼 해시를 소금쳐 새 행을 만든다.
    public func addTransaction(_ request: AddTransactionRequest) async -> AddTransactionOutcome {
        do {
            let currency = request.amount.currency
            let magnitude = try MoneyAmount.minorUnits(from: request.amount.text, currency: currency)
            let amount = request.amount.isOutflow ? -abs(magnitude) : abs(magnitude)
            let saltID = UUID().uuidString.lowercased()
            let description = request.narrative.description
            let hash = ContentHash.transactionHash(
                date: request.date,
                time: nil,
                amountMinor: amount,
                currency: currency,
                instrumentID: request.parties.accountID ?? request.parties.cardID ?? "",
                description: request.allowDuplicate ? description + "|salt:" + saltID : description,
                balanceAfterMinor: nil
            )
            let category = request.narrative.category
            let memo = request.narrative.memo
            let tx = MoneyTransaction(
                id: saltID,
                stamp: .init(date: request.date),
                amount: .init(amountMinor: amount, currency: currency),
                parties: .init(
                    accountID: request.parties.accountID,
                    cardID: request.parties.cardID,
                    businessID: request.parties.businessID
                ),
                narrative: .init(
                    description: description,
                    category: category.flatMap { $0.isEmpty ? nil : $0 },
                    memo: memo.flatMap { $0.isEmpty ? nil : $0 }
                ),
                contentHash: hash
            )
            let store = try LedgerStore(context: context)
            let outcome = try await store.insert(transaction: tx)
            await refresh()
            return AddTransactionOutcome(errorMessage: nil, duplicate: outcome.duplicate)
        } catch {
            return AddTransactionOutcome(errorMessage: String(describing: error), duplicate: false)
        }
    }

    private func mutate(_ body: (LedgerStore) async throws -> Void) async -> String? {
        do {
            let store = try LedgerStore(context: context)
            try await body(store)
            await refresh()
            return nil
        } catch {
            return String(describing: error)
        }
    }
}

// MARK: - 공통 폼 셸

struct EditorSheet<Content: View>: View {
    let title: String
    let korean: Bool
    let errorMessage: String?
    let onSave: () -> Void
    let onCancel: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.headline).padding()
            Form { content() }
                .formStyle(.grouped)
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }
            HStack {
                Spacer()
                Button(korean ? "취소" : "Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(korean ? "저장" : "Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 420)
    }
}

/// 결제수단 선택 항목(계좌+카드 합본).
enum InstrumentChoice: Hashable {
    case none
    case account(String)
    case card(String)
}

struct InstrumentPicker: View {
    let label: String
    let korean: Bool
    let accounts: [MoneyAccount]
    let cards: [MoneyCard]
    let allowNone: Bool
    @Binding var selection: InstrumentChoice

    var body: some View {
        Picker(label, selection: $selection) {
            if allowNone {
                Text(korean ? "(없음)" : "(none)").tag(InstrumentChoice.none)
            }
            if !accounts.isEmpty {
                Section(korean ? "계좌" : "Accounts") {
                    ForEach(accounts) { account in
                        Text("\(account.name) — \(account.bank)(\(account.last4))")
                            .tag(InstrumentChoice.account(account.id))
                    }
                }
            }
            if !cards.isEmpty {
                Section(korean ? "카드" : "Cards") {
                    ForEach(cards) { card in
                        Text("\(card.name) — \(card.issuer)(\(card.last4))")
                            .tag(InstrumentChoice.card(card.id))
                    }
                }
            }
        }
    }
}

// MARK: - 계좌 등록

struct AccountEditorSheet: View {
    let model: LedgerModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var bank = ""
    @State private var last4 = ""
    @State private var currency = "KRW"
    @State private var purpose = ""
    @State private var note = ""
    @State private var errorMessage: String?

    var body: some View {
        EditorSheet(
            title: model.korean ? "계좌 추가" : "Add account",
            korean: model.korean,
            errorMessage: errorMessage,
            onSave: {
                guard !name.isEmpty, !bank.isEmpty else {
                    errorMessage = model.korean ? "이름·은행은 필수입니다" : "Name and bank are required"
                    return
                }
                Task {
                    let error = await model.saveAccount(MoneyAccount(
                        name: name,
                        bank: bank,
                        last4: last4,
                        currency: currency,
                        purpose: purpose.isEmpty ? nil : purpose,
                        note: note.isEmpty ? nil : note
                    ))
                    if let error { errorMessage = error } else { dismiss() }
                }
            },
            onCancel: { dismiss() }
        ) {
            TextField(model.korean ? "이름 (예: 주거래)" : "Name", text: $name)
            TextField(model.korean ? "은행 (예: 신한)" : "Bank", text: $bank)
            TextField(model.korean ? "끝 4자리" : "Last 4 digits", text: $last4)
            TextField(model.korean ? "통화" : "Currency", text: $currency)
            TextField(model.korean ? "용도 (선택)" : "Purpose (optional)", text: $purpose)
            TextField(model.korean ? "메모 (선택)" : "Note (optional)", text: $note)
        }
    }
}

// MARK: - 카드 등록

struct CardEditorSheet: View {
    let model: LedgerModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var issuer = ""
    @State private var last4 = ""
    @State private var linkedAccount = InstrumentChoice.none
    @State private var billingDayText = ""
    @State private var note = ""
    @State private var errorMessage: String?

    var body: some View {
        EditorSheet(
            title: model.korean ? "카드 추가" : "Add card",
            korean: model.korean,
            errorMessage: errorMessage,
            onSave: {
                guard !name.isEmpty, !issuer.isEmpty else {
                    errorMessage = model.korean ? "이름·카드사는 필수입니다" : "Name and issuer are required"
                    return
                }
                let billingDay = Int(billingDayText)
                if !billingDayText.isEmpty, billingDay == nil || !(1...31).contains(billingDay!) {
                    errorMessage = model.korean ? "결제일은 1~31 사이 숫자입니다" : "Billing day must be 1-31"
                    return
                }
                var linkedAccountID: String?
                if case let .account(id) = linkedAccount { linkedAccountID = id }
                Task {
                    let error = await model.saveCard(MoneyCard(
                        name: name,
                        issuer: issuer,
                        last4: last4,
                        linkedAccountID: linkedAccountID,
                        billingDay: billingDay,
                        note: note.isEmpty ? nil : note
                    ))
                    if let error { errorMessage = error } else { dismiss() }
                }
            },
            onCancel: { dismiss() }
        ) {
            TextField(model.korean ? "이름 (예: 법인카드)" : "Name", text: $name)
            TextField(model.korean ? "카드사 (예: 현대카드)" : "Issuer", text: $issuer)
            TextField(model.korean ? "끝 4자리" : "Last 4 digits", text: $last4)
            InstrumentPicker(
                label: model.korean ? "결제 계좌 (선택)" : "Linked account (optional)",
                korean: model.korean,
                accounts: model.snapshot.accounts,
                cards: [],
                allowNone: true,
                selection: $linkedAccount
            )
            TextField(model.korean ? "매월 결제일 (선택, 1~31)" : "Billing day (optional)", text: $billingDayText)
            TextField(model.korean ? "메모 (선택)" : "Note (optional)", text: $note)
        }
    }
}

// MARK: - 구독 등록

struct SubscriptionEditorSheet: View {
    let model: LedgerModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var amountText = ""
    @State private var currency = "KRW"
    @State private var period = BillingPeriod.monthly
    @State private var hasNextBilling = false
    @State private var nextBilling = Date.now
    @State private var payment = InstrumentChoice.none
    @State private var note = ""
    @State private var errorMessage: String?

    var body: some View {
        EditorSheet(
            title: model.korean ? "구독 추가" : "Add subscription",
            korean: model.korean,
            errorMessage: errorMessage,
            onSave: {
                guard !name.isEmpty else {
                    errorMessage = model.korean ? "이름은 필수입니다" : "Name is required"
                    return
                }
                let amount: Int64
                do {
                    amount = try MoneyAmount.minorUnits(from: amountText, currency: currency)
                } catch {
                    errorMessage = String(describing: error)
                    return
                }
                var cardID: String?
                var accountID: String?
                if case let .card(id) = payment { cardID = id }
                if case let .account(id) = payment { accountID = id }
                Task {
                    let error = await model.saveSubscription(MoneySubscription(
                        name: name,
                        amount: .init(amountMinor: amount, currency: currency, period: period),
                        billing: .init(
                            nextBillingDate: hasNextBilling ? LedgerDate.format(nextBilling) : nil
                        ),
                        links: .init(paymentCardID: cardID, paymentAccountID: accountID),
                        note: note.isEmpty ? nil : note
                    ))
                    if let error { errorMessage = error } else { dismiss() }
                }
            },
            onCancel: { dismiss() }
        ) {
            TextField(model.korean ? "이름 (예: Claude)" : "Name", text: $name)
            TextField(model.korean ? "금액 (예: 15000 / 15.99)" : "Amount", text: $amountText)
            TextField(model.korean ? "통화" : "Currency", text: $currency)
            Picker(model.korean ? "주기" : "Period", selection: $period) {
                ForEach([BillingPeriod.monthly, .yearly, .oneTime], id: \.self) { period in
                    Text(period.label(korean: model.korean)).tag(period)
                }
            }
            Toggle(model.korean ? "다음 결제일 지정" : "Set next billing date", isOn: $hasNextBilling)
            if hasNextBilling {
                DatePicker(
                    model.korean ? "다음 결제일" : "Next billing",
                    selection: $nextBilling,
                    displayedComponents: .date
                )
            }
            InstrumentPicker(
                label: model.korean ? "결제수단 (선택)" : "Payment method (optional)",
                korean: model.korean,
                accounts: model.snapshot.accounts,
                cards: model.snapshot.cards,
                allowNone: true,
                selection: $payment
            )
            TextField(model.korean ? "메모 (선택)" : "Note (optional)", text: $note)
        }
    }
}

// MARK: - 거래 등록

struct TransactionEditorSheet: View {
    let model: LedgerModel
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date.now
    @State private var amountText = ""
    @State private var isOutflow = true
    @State private var currency = "KRW"
    @State private var instrument = InstrumentChoice.none
    @State private var businessID: String?
    @State private var descriptionText = ""
    @State private var category = ""
    @State private var memo = ""
    @State private var allowDuplicate = false
    @State private var errorMessage: String?

    var body: some View {
        EditorSheet(
            title: model.korean ? "거래 추가" : "Add transaction",
            korean: model.korean,
            errorMessage: errorMessage,
            onSave: {
                guard instrument != .none else {
                    errorMessage = model.korean ? "계좌 또는 카드를 선택하세요" : "Pick an account or card"
                    return
                }
                guard !amountText.isEmpty else {
                    errorMessage = model.korean ? "금액을 입력하세요" : "Amount is required"
                    return
                }
                var accountID: String?
                var cardID: String?
                if case let .account(id) = instrument { accountID = id }
                if case let .card(id) = instrument { cardID = id }
                Task {
                    let outcome = await model.addTransaction(LedgerModel.AddTransactionRequest(
                        date: LedgerDate.format(date),
                        amount: .init(text: amountText, isOutflow: isOutflow, currency: currency),
                        parties: .init(accountID: accountID, cardID: cardID, businessID: businessID),
                        narrative: .init(
                            description: descriptionText,
                            category: category,
                            memo: memo
                        ),
                        allowDuplicate: allowDuplicate
                    ))
                    if let error = outcome.errorMessage {
                        errorMessage = error
                    } else if outcome.duplicate {
                        errorMessage = model.korean
                            ? "같은 내용의 거래가 이미 있어 저장하지 않았습니다. 진짜 별건이면 '중복이어도 저장'을 켜세요."
                            : "Identical transaction already exists — enable 'save anyway' if it's a distinct one."
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
            TextField(model.korean ? "금액 (예: 15000)" : "Amount", text: $amountText)
            TextField(model.korean ? "통화" : "Currency", text: $currency)
            InstrumentPicker(
                label: model.korean ? "계좌/카드" : "Account/Card",
                korean: model.korean,
                accounts: model.snapshot.accounts,
                cards: model.snapshot.cards,
                allowNone: false,
                selection: $instrument
            )
            if !model.snapshot.businesses.isEmpty {
                BusinessPicker(
                    label: model.korean ? "사업체 (선택)" : "Business (optional)",
                    noneLabel: model.korean ? "(없음)" : "(none)",
                    businesses: model.snapshot.businesses,
                    selection: $businessID
                )
            }
            TextField(model.korean ? "적요 (예: 스타벅스)" : "Description", text: $descriptionText)
            TextField(model.korean ? "카테고리 (선택)" : "Category (optional)", text: $category)
            TextField(model.korean ? "메모 (선택)" : "Memo (optional)", text: $memo)
            Toggle(model.korean ? "중복이어도 저장" : "Save even if duplicate", isOn: $allowDuplicate)
        }
    }
}
