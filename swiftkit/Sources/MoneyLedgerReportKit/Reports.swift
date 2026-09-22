import Foundation
import MoneyLedgerModels

/// 리포트 — 저장 행 위의 순수 함수. 통화별 버킷을 절대 합치지 않는다(환율 없음 원칙).
public enum Reports {
    /// 통화별 월 입금/출금/순액(최소단위).
    public struct MonthlyFlow: Sendable, Equatable, Codable {
        public let currency: String
        public let inflowMinor: Int64
        public let outflowMinor: Int64
        public var netMinor: Int64 { inflowMinor + outflowMinor }
        public let transactionCount: Int
    }

    public static func monthlyFlow(transactions: [MoneyTransaction]) -> [MonthlyFlow] {
        var buckets: [String: (inflow: Int64, outflow: Int64, count: Int)] = [:]
        for tx in transactions {
            // 이체(transfer) 및 카드대금 정산(settlement)은 단순 자금 이동이므로 월간 현금흐름 왜곡 방지를 위해 수입/지출 합산에서 제외
            if tx.kind == .transfer || tx.kind == .settlement { continue }
            var bucket = buckets[tx.currency] ?? (0, 0, 0)
            if tx.amountMinor >= 0 { bucket.inflow += tx.amountMinor } else { bucket.outflow += tx.amountMinor }
            bucket.count += 1
            buckets[tx.currency] = bucket
        }
        return buckets.sorted { $0.key < $1.key }.map { currency, bucket in
            MonthlyFlow(
                currency: currency,
                inflowMinor: bucket.inflow,
                outflowMinor: bucket.outflow,
                transactionCount: bucket.count
            )
        }
    }

    /// 카테고리별 합계(통화별). 카테고리 없는 거래는 "(미분류)" 버킷.
    public struct CategoryTotal: Sendable, Equatable, Codable {
        public let category: String
        public let currency: String
        public let totalMinor: Int64
        public let transactionCount: Int
    }

    public static let uncategorizedLabel = "(미분류)"

    public static func categoryTotals(transactions: [MoneyTransaction]) -> [CategoryTotal] {
        var buckets: [String: [String: (total: Int64, count: Int)]] = [:]
        for tx in transactions {
            // 이체 및 카드대금 정산은 카테고리별 수입/지출 합산에서 제외
            if tx.kind == .transfer || tx.kind == .settlement { continue }
            let category = (tx.category?.isEmpty == false ? tx.category : nil) ?? uncategorizedLabel
            var currencyBucket = buckets[category] ?? [:]
            var bucket = currencyBucket[tx.currency] ?? (0, 0)
            bucket.total += tx.amountMinor
            bucket.count += 1
            currencyBucket[tx.currency] = bucket
            buckets[category] = currencyBucket
        }
        return buckets.flatMap { category, currencyBucket in
            currencyBucket.map { currency, bucket in
                CategoryTotal(
                    category: category,
                    currency: currency,
                    totalMinor: bucket.total,
                    transactionCount: bucket.count
                )
            }
        }
        .sorted { lhs, rhs in
            if lhs.totalMinor != rhs.totalMinor { return lhs.totalMinor < rhs.totalMinor }
            return (lhs.category, lhs.currency) < (rhs.category, rhs.currency)
        }
    }

    /// 계좌 잔액 계산: 기초잔액 + 해당 계좌의 모든 거래(수입/지출/이체 등) 합산.
    public static func accountBalance(account: MoneyAccount, transactions: [MoneyTransaction]) -> Int64 {
        let initial = account.initialBalanceMinor ?? 0
        let cur = MoneyAmount.normalizedCurrency(account.currency)
        let txSum = transactions
            .filter { $0.accountID == account.id && MoneyAmount.normalizedCurrency($0.currency) == cur }
            .map(\.amountMinor)
            .reduce(0, +)
        return initial + txSum
    }

    /// 카드 미결제 잔액(부채): 결제(지출) 및 대금 납부(상환)의 합산.
    public static func cardBalance(cardID: String, transactions: [MoneyTransaction], currency: String = "KRW") -> Int64 {
        let normCur = MoneyAmount.normalizedCurrency(currency)
        let cardSum = transactions
            .filter { $0.cardID == cardID && MoneyAmount.normalizedCurrency($0.currency) == normCur }
            .map(\.amountMinor)
            .reduce(0, +)
        return cardSum < 0 ? abs(cardSum) : 0
    }

    /// 통화별 구독 월환산 합계 — yearly ÷ 12, oneTime/unknown 제외. 유일하게 Double 이 허용되는 파생값.
    public struct SubscriptionMonthly: Sendable, Equatable, Codable {
        public let currency: String
        public let monthlyEquivalent: Double
        public let subscriptionCount: Int
    }

    public static func subscriptionMonthlyTotals(subscriptions: [MoneySubscription]) -> [SubscriptionMonthly] {
        var buckets: [String: (total: Double, count: Int)] = [:]
        for sub in subscriptions where sub.status == .active && !sub.archived {
            let monthly: Double?
            switch sub.period {
            case .monthly: monthly = MoneyAmount.majorUnits(minor: sub.amountMinor, currency: sub.currency)
            case .yearly: monthly = MoneyAmount.majorUnits(minor: sub.amountMinor, currency: sub.currency) / 12.0
            case .oneTime, .unknown: monthly = nil
            }
            guard let monthly else { continue }
            var bucket = buckets[sub.currency] ?? (0, 0)
            bucket.total += monthly
            bucket.count += 1
            buckets[sub.currency] = bucket
        }
        return buckets.sorted { $0.key < $1.key }.map { currency, bucket in
            SubscriptionMonthly(
                currency: currency,
                monthlyEquivalent: bucket.total,
                subscriptionCount: bucket.count
            )
        }
    }

    /// 다가오는 결제 이벤트. 저장된 nextBillingDate 가 과거면 주기만큼 굴려서 계산(저장값 불변).
    public struct UpcomingBilling: Sendable, Equatable, Codable {
        public let subscriptionID: String
        public let name: String
        public let date: String
        public let daysUntil: Int
        public let amountMinor: Int64
        public let currency: String
    }

    public static func upcomingBillings(
        subscriptions: [MoneySubscription],
        from today: String = LedgerDate.today(),
        horizonDays: Int = 30
    ) -> [UpcomingBilling] {
        guard let todayDate = LedgerDate.toDate(today) else { return [] }
        var events: [UpcomingBilling] = []
        for sub in subscriptions where sub.status == .active && !sub.archived {
            guard var next = sub.nextBillingDate, LedgerDate.isValid(next) else { continue }
            // 과거 결제일은 오늘 이후 첫 회차까지 굴린다. 주기 없는 구독은 지난 날짜면 제외.
            var guardCount = 0
            while next < today, guardCount < 600 {
                guard let advanced = LedgerDate.advance(next, by: sub.period) else { break }
                next = advanced
                guardCount += 1
            }
            guard next >= today, let nextDate = LedgerDate.toDate(next) else { continue }
            let days = Calendar.current.dateComponents([.day], from: todayDate, to: nextDate).day ?? 0
            guard days <= horizonDays else { continue }
            events.append(UpcomingBilling(
                subscriptionID: sub.id,
                name: sub.name,
                date: next,
                daysUntil: days,
                amountMinor: sub.amountMinor,
                currency: sub.currency
            ))
        }
        return events.sorted { ($0.date, $0.name) < ($1.date, $1.name) }
    }

    // MARK: - 순자산 리포트

    /// 통화별 순자산 요약.
    public struct NetWorthReport: Sendable, Equatable, Codable {
        public struct GroupBreakdown: Sendable, Equatable, Codable {
            public let type: String
            public let label: String
            public let amountMinor: Int64
            public let percentage: Double

            public init(type: String, label: String, amountMinor: Int64, percentage: Double) {
                self.type = type
                self.label = label
                self.amountMinor = amountMinor
                self.percentage = percentage
            }
        }

        public let currency: String
        public let totalAssetsMinor: Int64
        public let totalLiabilitiesMinor: Int64
        public var netWorthMinor: Int64 { totalAssetsMinor - totalLiabilitiesMinor }
        public let assetGroups: [GroupBreakdown]
        public let liabilityGroups: [GroupBreakdown]

        public init(
            currency: String,
            totalAssetsMinor: Int64,
            totalLiabilitiesMinor: Int64,
            assetGroups: [GroupBreakdown],
            liabilityGroups: [GroupBreakdown]
        ) {
            self.currency = currency
            self.totalAssetsMinor = totalAssetsMinor
            self.totalLiabilitiesMinor = totalLiabilitiesMinor
            self.assetGroups = assetGroups
            self.liabilityGroups = liabilityGroups
        }
    }

    public static func netWorth(
        accounts: [MoneyAccount],
        cards: [MoneyCard] = [],
        transactions: [MoneyTransaction] = []
    ) -> [NetWorthReport] {
        let currencies = collectCurrencies(accounts: accounts, cards: cards, transactions: transactions)
        let reports = currencies.compactMap { currency in
            calculateCurrencyNetWorth(
                currency: currency, accounts: accounts, cards: cards, transactions: transactions
            )
        }
        if reports.isEmpty {
            return [NetWorthReport(
                currency: "KRW", totalAssetsMinor: 0, totalLiabilitiesMinor: 0,
                assetGroups: [], liabilityGroups: []
            )]
        }
        return reports
    }

    private static func collectCurrencies(
        accounts: [MoneyAccount], cards: [MoneyCard], transactions: [MoneyTransaction]
    ) -> [String] {
        var currencies = Set<String>()
        for account in accounts where !account.archived {
            currencies.insert(MoneyAmount.normalizedCurrency(account.currency))
        }
        for _ in cards where !cards.isEmpty {
            currencies.insert("KRW")
        }
        for tx in transactions {
            currencies.insert(MoneyAmount.normalizedCurrency(tx.currency))
        }
        if currencies.isEmpty { currencies.insert("KRW") }
        return currencies.sorted()
    }

    private static func calculateCurrencyNetWorth(
        currency: String, accounts: [MoneyAccount], cards: [MoneyCard], transactions: [MoneyTransaction]
    ) -> NetWorthReport? {
        var assetGroupTotals: [String: (label: String, amount: Int64)] = [:]
        var liabilityGroupTotals: [String: (label: String, amount: Int64)] = [:]

        let currencyAccounts = accounts.filter {
            !$0.archived && MoneyAmount.normalizedCurrency($0.currency) == currency
        }
        aggregateAccountBalances(
            accounts: currencyAccounts, transactions: transactions, currency: currency,
            assetTotals: &assetGroupTotals, liabilityTotals: &liabilityGroupTotals
        )
        aggregateCardLiabilities(
            cards: cards, transactions: transactions, currency: currency,
            liabilityTotals: &liabilityGroupTotals
        )

        let totalAssets = assetGroupTotals.values.map(\.amount).reduce(0, +)
        let totalLiabilities = liabilityGroupTotals.values.map(\.amount).reduce(0, +)

        if totalAssets == 0 && totalLiabilities == 0 && currencyAccounts.isEmpty {
            return nil
        }

        return NetWorthReport(
            currency: currency,
            totalAssetsMinor: totalAssets,
            totalLiabilitiesMinor: totalLiabilities,
            assetGroups: buildBreakdowns(totals: assetGroupTotals, totalAmount: totalAssets),
            liabilityGroups: buildBreakdowns(totals: liabilityGroupTotals, totalAmount: totalLiabilities)
        )
    }

    private static func aggregateAccountBalances(
        accounts: [MoneyAccount], transactions: [MoneyTransaction], currency: String,
        assetTotals: inout [String: (label: String, amount: Int64)],
        liabilityTotals: inout [String: (label: String, amount: Int64)]
    ) {
        for account in accounts {
            let initial = account.initialBalanceMinor ?? 0
            let txSum = transactions
                .filter { $0.accountID == account.id && MoneyAmount.normalizedCurrency($0.currency) == currency }
                .map(\.amountMinor)
                .reduce(0, +)
            let balance = initial + txSum
            let type = account.accountType ?? .checking
            recordBalance(type: type, initial: initial, txSum: txSum, balance: balance, assetTotals: &assetTotals, liabilityTotals: &liabilityTotals)
        }
    }

    private static func recordBalance(
        type: MoneyAccountType, initial: Int64, txSum: Int64, balance: Int64,
        assetTotals: inout [String: (label: String, amount: Int64)],
        liabilityTotals: inout [String: (label: String, amount: Int64)]
    ) {
        guard type != .loan else {
            let debt = (initial > 0) ? max(0, initial - txSum) : abs(balance)
            if debt > 0 {
                var current = liabilityTotals[type.rawValue] ?? (type.label(korean: true), 0)
                current.amount += debt
                liabilityTotals[type.rawValue] = current
            }
            return
        }
        if balance >= 0 {
            var current = assetTotals[type.rawValue] ?? (type.label(korean: true), 0)
            current.amount += balance
            assetTotals[type.rawValue] = current
        } else {
            var current = liabilityTotals["overdraft"] ?? ("마이너스통장", 0)
            current.amount += abs(balance)
            liabilityTotals["overdraft"] = current
        }
    }

    private static func aggregateCardLiabilities(
        cards: [MoneyCard], transactions: [MoneyTransaction], currency: String,
        liabilityTotals: inout [String: (label: String, amount: Int64)]
    ) {
        for card in cards where !card.archived {
            let cardSum = transactions
                .filter { $0.cardID == card.id && MoneyAmount.normalizedCurrency($0.currency) == currency }
                .map(\.amountMinor)
                .reduce(0, +)
            if cardSum < 0 {
                var current = liabilityTotals["card"] ?? ("신용카드", 0)
                current.amount += abs(cardSum)
                liabilityTotals["card"] = current
            }
        }
    }

    private static func buildBreakdowns(
        totals: [String: (label: String, amount: Int64)], totalAmount: Int64
    ) -> [NetWorthReport.GroupBreakdown] {
        totals.map { key, val in
            let pct = totalAmount > 0 ? (Double(val.amount) / Double(totalAmount) * 100.0) : 0.0
            return NetWorthReport.GroupBreakdown(
                type: key, label: val.label, amountMinor: val.amount, percentage: pct
            )
        }.sorted { $0.amountMinor > $1.amountMinor }
    }
}

