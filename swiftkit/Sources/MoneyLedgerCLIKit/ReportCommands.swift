import Foundation
import MoneyLedgerKit

/// report 서브커맨드 — 조회 전용, 전부 --json 지원.
/// monthly · categories 는 `--business <id|상호>` 로 사업체 한 곳만 본다. 손익·계정과목은 범위 밖이다.
enum ReportCommands {
    static func run(
        context: LedgerContext, sub: [String], scanner: ArgScanner, json: Bool, output: CLIOutput
    ) async throws {
        let store = try LedgerStore(context: context)
        let action = sub.first ?? "monthly"
        switch action {
        case "monthly":
            try await monthly(store: store, scanner: scanner, json: json, output: output)
        case "categories":
            try await categories(store: store, scanner: scanner, json: json, output: output)
        case "subs":
            try await subs(store: store, json: json, output: output)
        case "upcoming":
            try await upcoming(store: store, scanner: scanner, json: json, output: output)
        case "net-worth", "networth":
            try await NetWorthCommand.run(context: context, scanner: scanner, json: json, output: output)
        default:
            throw UsageError("unknown: report \(action)")
        }
    }

    /// `--month`(기본 이번 달) + `--business` 를 거래 질의로 푼 것. monthly · categories 공용.
    private struct Scope {
        let month: String
        let business: BusinessProfile?
        let query: TransactionQuery

        var headerObject: [String: Any] {
            var object: [String: Any] = ["month": month]
            if let business { object["businessID"] = business.id }
            return object
        }

        var headerSuffix: String {
            business.map { " · 사업체 \($0.name)" } ?? ""
        }
    }

    private static func scope(store: LedgerStore, scanner: ArgScanner) async throws -> Scope {
        let month = scanner.value("month") ?? String(LedgerDate.today().prefix(7))
        let range = try LedgerDate.monthRange(month)
        let business = try await BusinessArgument.resolve(store: store, scanner: scanner)
        return Scope(
            month: month,
            business: business,
            query: TransactionQuery(fromDate: range.from, toDate: range.to, businessID: business?.id)
        )
    }

    private static func monthly(
        store: LedgerStore, scanner: ArgScanner, json: Bool, output: CLIOutput
    ) async throws {
        let scope = try await scope(store: store, scanner: scanner)
        let flows = Reports.monthlyFlow(transactions: try await store.transactions(scope.query))
        if json {
            var object = scope.headerObject
            object["flows"] = flows.map { flow in
                [
                    "currency": flow.currency,
                    "inflow": CLIFormat.amountObject(minor: flow.inflowMinor, currency: flow.currency),
                    "outflow": CLIFormat.amountObject(minor: flow.outflowMinor, currency: flow.currency),
                    "net": CLIFormat.amountObject(minor: flow.netMinor, currency: flow.currency),
                    "transactionCount": flow.transactionCount,
                ] as [String: Any]
            }
            output.okJSON(object)
        } else if flows.isEmpty {
            output.out("\(scope.month): 거래 없음")
        } else {
            output.out("== \(scope.month) 월간 요약\(scope.headerSuffix)")
            for flow in flows {
                output.out(
                    "  [\(flow.currency)] 입금 \(MoneyAmount.format(minor: flow.inflowMinor, currency: flow.currency))"
                    + " · 출금 \(MoneyAmount.format(minor: flow.outflowMinor, currency: flow.currency))"
                    + " · 순액 \(MoneyAmount.format(minor: flow.netMinor, currency: flow.currency))"
                    + " (\(flow.transactionCount)건)"
                )
            }
        }
    }

    private static func categories(
        store: LedgerStore, scanner: ArgScanner, json: Bool, output: CLIOutput
    ) async throws {
        let scope = try await scope(store: store, scanner: scanner)
        let totals = Reports.categoryTotals(transactions: try await store.transactions(scope.query))
        if json {
            var object = scope.headerObject
            object["categories"] = totals.map { total in
                [
                    "category": total.category,
                    "currency": total.currency,
                    "total": CLIFormat.amountObject(minor: total.totalMinor, currency: total.currency),
                    "transactionCount": total.transactionCount,
                ] as [String: Any]
            }
            output.okJSON(object)
        } else if totals.isEmpty {
            output.out("\(scope.month): 거래 없음")
        } else {
            output.out("== \(scope.month) 카테고리별\(scope.headerSuffix)")
            for total in totals {
                output.out(
                    "  \(total.category) [\(total.currency)]: "
                    + "\(MoneyAmount.format(minor: total.totalMinor, currency: total.currency)) (\(total.transactionCount)건)"
                )
            }
        }
    }

    private static func subs(store: LedgerStore, json: Bool, output: CLIOutput) async throws {
        let subscriptions = try await store.subscriptions()
        let totals = Reports.subscriptionMonthlyTotals(subscriptions: subscriptions)
        if json {
            output.okJSON([
                "monthlyTotals": totals.map { total in
                    [
                        "currency": total.currency,
                        "monthlyEquivalent": total.monthlyEquivalent,
                        "subscriptionCount": total.subscriptionCount,
                    ] as [String: Any]
                },
            ])
        } else if totals.isEmpty {
            output.out("활성 구독 없음")
        } else {
            output.out("== 구독 월환산 합계")
            for total in totals {
                output.out(
                    "  [\(total.currency)] \(String(format: "%.2f", total.monthlyEquivalent))"
                    + " / 월 (\(total.subscriptionCount)개)"
                )
            }
        }
    }

    private static func upcoming(
        store: LedgerStore, scanner: ArgScanner, json: Bool, output: CLIOutput
    ) async throws {
        let days = scanner.value("days").flatMap(Int.init) ?? 30
        let subscriptions = try await store.subscriptions()
        let events = Reports.upcomingBillings(subscriptions: subscriptions, horizonDays: days)
        if json {
            output.okJSON([
                "horizonDays": days,
                "events": events.map { event in
                    [
                        "subscriptionID": event.subscriptionID,
                        "name": event.name,
                        "date": event.date,
                        "daysUntil": event.daysUntil,
                        "amount": CLIFormat.amountObject(minor: event.amountMinor, currency: event.currency),
                    ] as [String: Any]
                },
            ])
        } else if events.isEmpty {
            output.out("\(days)일 내 예정 결제 없음")
        } else {
            output.out("== \(days)일 내 예정 결제")
            for event in events {
                output.out(
                    "  D-\(event.daysUntil)  \(event.date)  \(event.name)  "
                    + MoneyAmount.format(minor: event.amountMinor, currency: event.currency)
                )
            }
        }
    }
}
