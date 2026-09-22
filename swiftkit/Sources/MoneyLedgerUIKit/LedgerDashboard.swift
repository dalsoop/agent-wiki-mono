import Foundation
import MoneyLedgerKit
import SwiftUI
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif

// Ledger 공용 GUI — 두 앱(BusinessLedger/PersonalLedger)이 scope 만 다르게 사용한다.
// CLI 타깃에는 절대 링크하지 않는다(dual-entry: PATH CLI 에 AppKit 금지).

/// 대시보드 스냅샷 — GUI 와 StateMirror 가 같은 값을 본다.
public struct LedgerSnapshot: Sendable, Equatable {
    public var accounts: [MoneyAccount] = []
    public var cards: [MoneyCard] = []
    public var subscriptions: [MoneySubscription] = []
    public var recentTransactions: [MoneyTransaction] = []
    public var monthTransactions: [MoneyTransaction] = []
    public var monthFlows: [Reports.MonthlyFlow] = []
    public var monthCategoryTotals: [Reports.CategoryTotal] = []
    public var subscriptionTotals: [Reports.SubscriptionMonthly] = []
    public var upcoming: [Reports.UpcomingBilling] = []
    public var importBatches: [ImportBatch] = []
    public var businesses: [BusinessProfile] = []
    public var businessAttachmentCounts: [String: Int] = [:]
    public var month: String = String(LedgerDate.today().prefix(7))
    public var transactionCount: Int = 0
    public var netWorthReports: [Reports.NetWorthReport] = []
    public var budgets: [MoneyBudget] = []
    public var lastError: String?

    public init() {}

    public var budgetExceededCount: Int {
        var count = 0
        for b in budgets {
            let catTotal = monthCategoryTotals.first {
                $0.category == b.category && MoneyAmount.normalizedCurrency($0.currency) == MoneyAmount.normalizedCurrency(b.currency)
            }
            let spent = catTotal.map { $0.totalMinor < 0 ? abs($0.totalMinor) : 0 } ?? 0
            if spent > b.amountMinor {
                count += 1
            }
        }
        return count
    }

    /// 이번 달 아직 거래로 기록되지 않은 활성 고정비(구독) 목록
    public var unreflectedSubscriptions: [MoneySubscription] {
        subscriptions.filter { sub in
            guard sub.status == .active, !sub.archived else { return false }
            let alreadyReflected = monthTransactions.contains { tx in
                tx.description.localizedCaseInsensitiveContains(sub.name)
            }
            return !alreadyReflected
        }
    }
}

/// 두 앱 공용 앱모델 — 원장 로드·집계·StateMirror 게시 훅.
@MainActor
@Observable
public final class LedgerModel {
    public let context: LedgerContext
    public private(set) var snapshot = LedgerSnapshot()
    /// 모델이 바뀔 때마다 앱 쪽 StateMirrorAdoption.publish 를 부른다(킷은 앱 이름만 안다).
    public var onSnapshotChange: (@MainActor (LedgerSnapshot) -> Void)?
    public var korean = true
    /// 거래 탭 사업체 필터(BusinessProfile.id). nil = 전체. refresh 가 recentTransactions 질의에 태운다.
    public var transactionBusinessFilter: String?

    public init(context: LedgerContext) {
        self.context = context
    }

    public func refresh() async {
        var next = LedgerSnapshot()
        do {
            let store = try LedgerStore(context: context)
            next.accounts = try await store.accounts()
            next.cards = try await store.cards()
            next.subscriptions = try await store.subscriptions()
            let month = String(LedgerDate.today().prefix(7))
            next.month = month
            let range = try LedgerDate.monthRange(month)
            let monthTransactions = try await store.transactions(
                TransactionQuery(fromDate: range.from, toDate: range.to)
            )
            next.monthTransactions = monthTransactions
            next.monthFlows = Reports.monthlyFlow(transactions: monthTransactions)
            next.monthCategoryTotals = Reports.categoryTotals(transactions: monthTransactions)
            next.budgets = try await store.budgets()
            let allTransactions = try await store.transactions(TransactionQuery())
            next.netWorthReports = Reports.netWorth(accounts: next.accounts, cards: next.cards, transactions: allTransactions)
            next.recentTransactions = try await store.transactions(
                TransactionQuery(businessID: transactionBusinessFilter, limit: 50)
            )
            next.subscriptionTotals = Reports.subscriptionMonthlyTotals(subscriptions: next.subscriptions)
            next.upcoming = Reports.upcomingBillings(subscriptions: next.subscriptions)
            next.importBatches = try await store.importBatches()
            next.businesses = try await store.businesses()
            for business in next.businesses {
                next.businessAttachmentCounts[business.id] = try await store.attachments(
                    ownerKind: .business, ownerID: business.id
                ).count
            }
            next.transactionCount = try await store.transactionCount()
        } catch {
            next.lastError = String(describing: error)
        }
        snapshot = next
        onSnapshotChange?(next)
    }
}

/// 메뉴바 팝오버 — 이번 달 요약 + 다가오는 결제.
public struct LedgerMenuView: View {
    @Bindable private var model: LedgerModel
    private let openWindow: () -> Void

    public init(model: LedgerModel, openWindow: @escaping () -> Void) {
        self.model = model
        self.openWindow = openWindow
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            titleRow
            if model.snapshot.monthFlows.isEmpty {
                Text(model.korean ? "이번 달 거래 없음" : "No transactions this month")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.snapshot.monthFlows, id: \.currency) { flow in
                    MenuFlowRow(flow: flow, korean: model.korean)
                }
            }
            if !model.snapshot.upcoming.isEmpty {
                Divider()
                upcomingSection
            }
            Divider()
            footer
        }
        .padding(12)
        .frame(width: 320)
        .task { await model.refresh() }
    }

    private var titleRow: some View {
        HStack {
            Text("\(model.context.scope.appName) — \(model.snapshot.month)")
                .font(.headline)
            Spacer()
            Button {
                Task { await model.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
        }
    }

    private var upcomingSection: some View {
        Group {
            Text(model.korean ? "다가오는 결제" : "Upcoming billing").font(.caption.bold())
            ForEach(model.snapshot.upcoming.prefix(3), id: \.subscriptionID) { event in
                HStack {
                    Text("D-\(event.daysUntil)").font(.caption.monospacedDigit())
                        .foregroundStyle(.orange)
                    Text(event.name).font(.caption)
                    Spacer()
                    Text(MoneyAmount.format(minor: event.amountMinor, currency: event.currency))
                        .font(.caption)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button(model.korean ? "대시보드 열기" : "Open dashboard") { openWindow() }
            Spacer()
            Text(
                (model.korean ? "거래 " : "tx ")
                + "\(model.snapshot.transactionCount)"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

/// 메뉴바 팝오버의 통화별 한 줄 — 입금·출금·순액.
struct MenuFlowRow: View {
    let flow: Reports.MonthlyFlow
    let korean: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("[\(flow.currency)]").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Label(
                    MoneyAmount.format(minor: flow.inflowMinor, currency: flow.currency),
                    systemImage: "arrow.down.circle"
                )
                .foregroundStyle(.green)
                Label(
                    MoneyAmount.format(minor: flow.outflowMinor, currency: flow.currency),
                    systemImage: "arrow.up.circle"
                )
                .foregroundStyle(.red)
            }
            .font(.callout)
            Text(
                (korean ? "순액 " : "net ")
                + MoneyAmount.format(minor: flow.netMinor, currency: flow.currency)
            )
            .font(.callout.bold())
        }
    }
}

/// 메인 창 — 계좌·카드·구독·거래·리포트 탭.
public struct LedgerWindowView: View {
    @Bindable private var model: LedgerModel

    public init(model: LedgerModel) {
        self.model = model
    }

    public var body: some View {
        TabView {
            OverviewTab(model: model)
                .tabItem { Label(model.korean ? "요약" : "Overview", systemImage: "chart.pie") }
            if model.context.scope == .business {
                BusinessTab(model: model)
                    .tabItem { Label(model.korean ? "사업자" : "Business", systemImage: "building.2") }
            }
            AccountsTab(model: model)
                .tabItem { Label(model.korean ? "계좌" : "Accounts", systemImage: "building.columns") }
            CardsTab(model: model)
                .tabItem { Label(model.korean ? "카드" : "Cards", systemImage: "creditcard") }
            SubscriptionsTab(model: model)
                .tabItem { Label(model.korean ? "구독" : "Subs", systemImage: "repeat.circle") }
            TransactionsTab(model: model)
                .tabItem { Label(model.korean ? "거래" : "Transactions", systemImage: "list.bullet.rectangle") }
        }
        .frame(minWidth: 720, minHeight: 480)
        .task { await model.refresh() }
    }
}

struct OverviewTab: View {
    let model: LedgerModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                topActionRow
                monthBox
                BudgetProgressCardView(model: model)
                RecurringExpenseView(model: model)
                subscriptionsBox
                upcomingBox
                if let lastError = model.snapshot.lastError {
                    GroupBox(model.korean ? "오류" : "Error") {
                        Text(lastError).font(.caption).foregroundStyle(.red)
                    }
                }
                footerView
            }
            .padding()
        }
    }

    private var topActionRow: some View {
        HStack {
            Text(model.context.scope.appName + (model.korean ? " 대시보드" : " Dashboard"))
                .font(.title2.bold())
            Spacer()
            Button {
                exportCSVWithSavePanel()
            } label: {
                Label(model.korean ? "CSV 내보내기" : "Export CSV", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
        }
    }

    private var footerView: some View {
        HStack {
            Text(
                model.korean
                ? "입력·가져오기는 CLI 가 정본: \(model.context.scope.slug) help"
                : "Data entry is CLI-first: \(model.context.scope.slug) help"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer()
            Button {
                exportCSVWithSavePanel()
            } label: {
                Label(model.korean ? "CSV 내보내기" : "Export CSV", systemImage: "doc.badge.arrow.up")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
        }
    }

    private func exportCSVWithSavePanel() {
        #if canImport(AppKit)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "\(model.context.scope.slug)-export-\(model.snapshot.month).csv"
        panel.prompt = model.korean ? "내보내기" : "Export"
        panel.message = model.korean ? "원장 거래 내역을 CSV 파일로 저장합니다" : "Save ledger transactions as CSV"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                Task {
                    _ = await model.exportCSV(to: url)
                }
            }
        }
        #endif
    }

    private var monthBox: some View {
        GroupBox(model.korean ? "이번 달 (\(model.snapshot.month))" : "This month (\(model.snapshot.month))") {
            if model.snapshot.monthFlows.isEmpty {
                Text(model.korean ? "거래 없음" : "No transactions").foregroundStyle(.secondary)
            } else {
                MonthFlowGrid(flows: model.snapshot.monthFlows, korean: model.korean)
            }
        }
    }

    private var subscriptionsBox: some View {
        GroupBox(model.korean ? "구독 월환산" : "Subscriptions monthly") {
            if model.snapshot.subscriptionTotals.isEmpty {
                Text(model.korean ? "활성 구독 없음" : "No active subscriptions")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.snapshot.subscriptionTotals, id: \.currency) { total in
                    HStack {
                        Text(total.currency).bold()
                        Text(String(format: "%.2f", total.monthlyEquivalent))
                        Text(model.korean ? "/월 · \(total.subscriptionCount)개" : "/mo · \(total.subscriptionCount)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var upcomingBox: some View {
        GroupBox(model.korean ? "다가오는 결제 (30일)" : "Upcoming (30d)") {
            if model.snapshot.upcoming.isEmpty {
                Text(model.korean ? "예정 결제 없음" : "Nothing upcoming").foregroundStyle(.secondary)
            } else {
                ForEach(model.snapshot.upcoming, id: \.subscriptionID) { event in
                    HStack {
                        Text("D-\(event.daysUntil)").monospacedDigit().foregroundStyle(.orange)
                        Text(event.date).foregroundStyle(.secondary)
                        Text(event.name)
                        Spacer()
                        Text(MoneyAmount.format(minor: event.amountMinor, currency: event.currency))
                    }
                }
            }
        }
    }
}

/// 요약 탭의 통화별 입금/출금/순액/건수 표.
struct MonthFlowGrid: View {
    let flows: [Reports.MonthlyFlow]
    let korean: Bool

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
            GridRow {
                Text("").gridColumnAlignment(.leading)
                Text(korean ? "입금" : "In").font(.caption).foregroundStyle(.secondary)
                Text(korean ? "출금" : "Out").font(.caption).foregroundStyle(.secondary)
                Text(korean ? "순액" : "Net").font(.caption).foregroundStyle(.secondary)
                Text(korean ? "건수" : "Count").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(flows, id: \.currency) { flow in
                GridRow {
                    Text(flow.currency).bold()
                    Text(MoneyAmount.format(minor: flow.inflowMinor, currency: flow.currency))
                        .foregroundStyle(.green)
                    Text(MoneyAmount.format(minor: flow.outflowMinor, currency: flow.currency))
                        .foregroundStyle(.red)
                    Text(MoneyAmount.format(minor: flow.netMinor, currency: flow.currency)).bold()
                    Text("\(flow.transactionCount)")
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// 탭 상단 공통 등록 버튼 줄.
struct EntryHeader: View {
    let addLabel: String
    let action: () -> Void

    var body: some View {
        HStack {
            Spacer()
            Button(action: action) { Label(addLabel, systemImage: "plus") }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct AccountsTab: View {
    let model: LedgerModel
    @State private var showingAdd = false

    var body: some View {
        VStack(spacing: 0) {
            EntryHeader(addLabel: model.korean ? "계좌 추가" : "Add account") { showingAdd = true }
            Table(model.snapshot.accounts) {
                TableColumn(model.korean ? "이름" : "Name", value: \.name)
                TableColumn(model.korean ? "은행" : "Bank", value: \.bank)
                TableColumn(model.korean ? "끝자리" : "Last4", value: \.last4)
                TableColumn(model.korean ? "통화" : "Currency", value: \.currency)
                TableColumn(model.korean ? "용도" : "Purpose") { account in
                    Text(account.purpose ?? "")
                }
                TableColumn("Vault") { account in
                    Image(systemName: account.vaultNoteRef != nil ? "lock.fill" : "lock.open")
                        .foregroundStyle(account.vaultNoteRef != nil ? .green : .secondary)
                }
                .width(50)
                TableColumn("") { account in
                    Menu {
                        Button(model.korean ? "보관 (목록에서 숨김)" : "Archive") {
                            Task { await model.setAccountArchived(account, true) }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                .width(40)
            }
        }
        .sheet(isPresented: $showingAdd) { AccountEditorSheet(model: model) }
        .overlay {
            if model.snapshot.accounts.isEmpty {
                ContentUnavailableView(
                    model.korean ? "계좌 없음" : "No accounts",
                    systemImage: "building.columns",
                    description: Text(
                        model.korean
                        ? "위 '계좌 추가' 버튼 또는 CLI: \(model.context.scope.slug) account add"
                        : "Use 'Add account' above or CLI: \(model.context.scope.slug) account add"
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor))   // 표 헤더·줄무늬까지 가린다
            }
        }
    }
}

struct CardsTab: View {
    let model: LedgerModel
    @State private var showingAdd = false

    var body: some View {
        VStack(spacing: 0) {
            EntryHeader(addLabel: model.korean ? "카드 추가" : "Add card") { showingAdd = true }
            Table(model.snapshot.cards) {
                TableColumn(model.korean ? "이름" : "Name", value: \.name)
                TableColumn(model.korean ? "카드사" : "Issuer", value: \.issuer)
                TableColumn(model.korean ? "끝자리" : "Last4", value: \.last4)
                TableColumn(model.korean ? "결제일" : "Billing day") { card in
                    Text(card.billingDay.map { model.korean ? "\($0)일" : "day \($0)" } ?? "")
                }
                TableColumn("Vault") { card in
                    Image(systemName: card.vaultNoteRef != nil ? "lock.fill" : "lock.open")
                        .foregroundStyle(card.vaultNoteRef != nil ? .green : .secondary)
                }
                .width(50)
                TableColumn("") { card in
                    Menu {
                        Button(model.korean ? "보관 (목록에서 숨김)" : "Archive") {
                            Task { await model.setCardArchived(card, true) }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                .width(40)
            }
        }
        .sheet(isPresented: $showingAdd) { CardEditorSheet(model: model) }
        .overlay {
            if model.snapshot.cards.isEmpty {
                ContentUnavailableView(
                    model.korean ? "카드 없음" : "No cards",
                    systemImage: "creditcard",
                    description: Text(
                        model.korean
                        ? "위 '카드 추가' 버튼 또는 CLI: \(model.context.scope.slug) card add"
                        : "Use 'Add card' above or CLI: \(model.context.scope.slug) card add"
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor))   // 표 헤더·줄무늬까지 가린다
            }
        }
    }
}

struct SubscriptionsTab: View {
    let model: LedgerModel
    @State private var showingAdd = false

    var body: some View {
        VStack(spacing: 0) {
            EntryHeader(addLabel: model.korean ? "구독 추가" : "Add subscription") { showingAdd = true }
            Table(model.snapshot.subscriptions) {
                TableColumn(model.korean ? "이름" : "Name", value: \.name)
                TableColumn(model.korean ? "금액" : "Amount") { sub in
                    Text(MoneyAmount.format(minor: sub.amountMinor, currency: sub.currency))
                }
                TableColumn(model.korean ? "주기" : "Period") { sub in
                    Text(sub.period.label(korean: model.korean))
                }
                TableColumn(model.korean ? "상태" : "Status") { sub in
                    Text(sub.status.label(korean: model.korean))
                }
                TableColumn(model.korean ? "다음 결제" : "Next billing") { sub in
                    Text(sub.nextBillingDate ?? "")
                }
                TableColumn("") { sub in
                    SubscriptionRowMenu(model: model, sub: sub)
                }
                .width(40)
            }
        }
        .sheet(isPresented: $showingAdd) { SubscriptionEditorSheet(model: model) }
        .overlay {
            if model.snapshot.subscriptions.isEmpty {
                ContentUnavailableView(
                    model.korean ? "구독 없음" : "No subscriptions",
                    systemImage: "repeat.circle",
                    description: Text(
                        model.korean
                        ? "위 '구독 추가' 버튼 또는 CLI: \(model.context.scope.slug) sub add"
                        : "Use 'Add subscription' above or CLI: \(model.context.scope.slug) sub add"
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor))   // 표 헤더·줄무늬까지 가린다
            }
        }
    }
}

/// 구독 행 메뉴 — 상태 전이(일시중지·재개·해지).
struct SubscriptionRowMenu: View {
    let model: LedgerModel
    let sub: MoneySubscription

    var body: some View {
        Menu {
            if sub.status == .active {
                Button(model.korean ? "일시중지" : "Pause") {
                    Task { await model.setSubscriptionStatus(sub, .paused) }
                }
            } else if sub.status == .paused {
                Button(model.korean ? "재개" : "Resume") {
                    Task { await model.setSubscriptionStatus(sub, .active) }
                }
            }
            if sub.status != .cancelled {
                Button(model.korean ? "해지" : "Cancel", role: .destructive) {
                    Task { await model.setSubscriptionStatus(sub, .cancelled) }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
