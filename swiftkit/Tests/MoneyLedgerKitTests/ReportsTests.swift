import XCTest
import MoneyLedgerModels
@testable import MoneyLedgerReportKit

final class ReportsTests: XCTestCase {
    private func tx(_ amount: Int64, currency: String = "KRW", category: String? = nil) -> MoneyTransaction {
        MoneyTransaction(
            date: "2026-08-04", amountMinor: amount, currency: currency,
            description: "t", category: category, contentHash: UUID().uuidString
        )
    }

    func testMonthlyFlowBucketsPerCurrencyNeverMerge() {
        let flows = Reports.monthlyFlow(transactions: [
            tx(3_000_000), tx(-500_000), tx(-1599, currency: "USD"),
        ])
        XCTAssertEqual(flows.count, 2)
        let krw = flows.first { $0.currency == "KRW" }!
        XCTAssertEqual(krw.inflowMinor, 3_000_000)
        XCTAssertEqual(krw.outflowMinor, -500_000)
        XCTAssertEqual(krw.netMinor, 2_500_000)
        let usd = flows.first { $0.currency == "USD" }!
        XCTAssertEqual(usd.outflowMinor, -1599)
    }

    func testCategoryTotals() {
        let totals = Reports.categoryTotals(transactions: [
            tx(-5000, category: "식비"), tx(-12000, category: "식비"), tx(-30000),
        ])
        let food = totals.first { $0.category == "식비" }!
        XCTAssertEqual(food.totalMinor, -17000)
        XCTAssertEqual(food.transactionCount, 2)
        XCTAssertTrue(totals.contains { $0.category == Reports.uncategorizedLabel })
    }

    func testSubscriptionMonthlyEquivalent() {
        let subs = [
            MoneySubscription(name: "Claude", amountMinor: 2000, currency: "USD", period: .monthly),
            MoneySubscription(name: "도메인", amountMinor: 24000, currency: "KRW", period: .yearly),
            MoneySubscription(name: "장비", amountMinor: 990_000, currency: "KRW", period: .oneTime),
        ]
        let totals = Reports.subscriptionMonthlyTotals(subscriptions: subs)
        let krw = totals.first { $0.currency == "KRW" }!
        XCTAssertEqual(krw.monthlyEquivalent, 2000.0, accuracy: 0.001)  // 24,000/12
        XCTAssertEqual(krw.subscriptionCount, 1)  // oneTime 제외
        let usd = totals.first { $0.currency == "USD" }!
        XCTAssertEqual(usd.monthlyEquivalent, 20.0, accuracy: 0.001)
    }

    func testInactiveSubscriptionsExcluded() {
        var cancelled = MoneySubscription(name: "Netflix", amountMinor: 17000)
        cancelled.status = .cancelled
        let totals = Reports.subscriptionMonthlyTotals(subscriptions: [cancelled])
        XCTAssertTrue(totals.isEmpty)
    }

    func testUpcomingBillingsHorizonAndRollForward() {
        let subs = [
            MoneySubscription(
                name: "가까움", amountMinor: 10000, period: .monthly, nextBillingDate: "2026-08-10"
            ),
            MoneySubscription(
                name: "지남-굴림", amountMinor: 20000, period: .monthly, nextBillingDate: "2026-07-20"
            ),
            MoneySubscription(
                name: "멀리", amountMinor: 30000, period: .monthly, nextBillingDate: "2026-09-20"
            ),
        ]
        let events = Reports.upcomingBillings(subscriptions: subs, from: "2026-08-04", horizonDays: 30)
        XCTAssertEqual(events.map(\.name), ["가까움", "지남-굴림"])
        // 7/20 결제일은 8/20 로 굴러야 한다
        XCTAssertEqual(events.first { $0.name == "지남-굴림" }?.date, "2026-08-20")
        XCTAssertEqual(events.first { $0.name == "가까움" }?.daysUntil, 6)
    }

    func testUpcomingDayZeroIncluded() {
        let subs = [
            MoneySubscription(name: "오늘", amountMinor: 5000, period: .monthly, nextBillingDate: "2026-08-04"),
        ]
        let events = Reports.upcomingBillings(subscriptions: subs, from: "2026-08-04", horizonDays: 30)
        XCTAssertEqual(events.first?.daysUntil, 0)
    }
}
