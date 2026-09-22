import Foundation
import InteropKit
import MoneyLedgerKit

/// sub(구독) 서브커맨드.
enum SubscriptionCommands {
    static func run(
        context: LedgerContext, sub: [String], scanner: ArgScanner, json: Bool, output: CLIOutput
    ) async throws {
        let store = try LedgerStore(context: context)
        let action = sub.first ?? "list"
        switch action {
        case "add":
            guard let name = scanner.value("name"), let amountRaw = scanner.value("amount") else {
                throw UsageError("sub add 는 --name, --amount 가 필요합니다")
            }
            let currency = scanner.value("currency") ?? "KRW"
            let amount = try MoneyAmount.minorUnits(from: amountRaw, currency: currency)
            let period = try parsePeriod(scanner.value("period") ?? "monthly")
            if let next = scanner.value("next-billing"), !LedgerDate.isValid(next) {
                throw UsageError("--next-billing 은 yyyy-MM-dd 형식입니다: \(next)")
            }
            var paymentCardID: String?
            var paymentAccountID: String?
            if let cardRef = scanner.value("card") { paymentCardID = try await store.resolveCard(cardRef).id }
            if let accountRef = scanner.value("account") {
                paymentAccountID = try await store.resolveAccount(accountRef).id
            }
            var businessID: String?
            if let bizRef = scanner.value("business") {
                businessID = try await store.resolveBusiness(bizRef).id
            }
            let (sourceApp, externalID) = try externalLink(scanner)
            let promoEndsOn = scanner.value("promo-ends")
            if let promoEndsOn, !LedgerDate.isValid(promoEndsOn) {
                throw UsageError("--promo-ends 는 yyyy-MM-dd 형식입니다: \(promoEndsOn)")
            }
            var regularAmountMinor: Int64?
            if let raw = scanner.value("regular-amount") {
                regularAmountMinor = try MoneyAmount.minorUnits(from: raw, currency: currency)
            }
            if regularAmountMinor != nil && promoEndsOn == nil {
                throw UsageError("--regular-amount 는 --promo-ends 와 함께 준다 (언제 오르는지 없이 정가만 두면 못 쓴다)")
            }
            // 같은 외부 구독을 다시 넣으면 새 행을 만들지 않고 갱신한다 —
            // 브리지가 주기적으로 돌면 중복이 쌓이기 때문이다.
            //
            // 갱신 규칙(둘을 섞지 않는다):
            //  · 소스가 소유하는 값(name·amount·period·프로모)은 **덮어쓴다**.
            //    프로모가 끝났으면 안 보내므로 nil 이 되는 게 맞다.
            //  · 사람이 붙인 귀속(card·account·business·note)은 **보존한다**.
            //    브리지는 어느 카드로 결제되는지 모른다.
            if let sourceApp, let externalID,
               var existing = try await store.subscriptions(includeArchived: true).first(where: {
                   $0.sourceApp == sourceApp && $0.externalID == externalID
               }) {
                existing.name = name
                existing.amountMinor = amount
                existing.currency = currency
                existing.period = period
                existing.nextBillingDate = scanner.value("next-billing") ?? existing.nextBillingDate
                existing.paymentCardID = paymentCardID ?? existing.paymentCardID
                existing.paymentAccountID = paymentAccountID ?? existing.paymentAccountID
                existing.businessID = businessID ?? existing.businessID
                existing.promoEndsOn = promoEndsOn
                existing.regularAmountMinor = regularAmountMinor
                existing.note = scanner.value("note") ?? existing.note
                try await store.save(subscription: existing)
                emit(existing, json: json, output: output)
                return
            }
            let subscription = MoneySubscription(
                name: name,
                amount: .init(amountMinor: amount, currency: currency, period: period),
                billing: .init(
                    nextBillingDate: scanner.value("next-billing"),
                    promoEndsOn: promoEndsOn,
                    regularAmountMinor: regularAmountMinor
                ),
                links: .init(
                    paymentCardID: paymentCardID,
                    paymentAccountID: paymentAccountID,
                    businessID: businessID,
                    sourceApp: sourceApp,
                    externalID: externalID
                ),
                note: scanner.value("note")
            )
            try await store.save(subscription: subscription)
            emit(subscription, json: json, output: output)
        case "list":
            let status = try scanner.value("status").map(parseStatus)
            let subscriptions = try await store.subscriptions(
                status: status, includeArchived: scanner.has("all")
            )
            if json {
                output.okJSON(["subscriptions": subscriptions.map(CLIFormat.subscriptionObject)])
            } else if subscriptions.isEmpty {
                output.out("구독 없음 — sub add --name <이름> --amount <금액>")
            } else {
                for subscription in subscriptions {
                    let amount = MoneyAmount.format(
                        minor: subscription.amountMinor, currency: subscription.currency
                    )
                    let next = subscription.nextBillingDate.map { " 다음 \($0)" } ?? ""
                    output.out(
                        "\(CLIFormat.shortID(subscription.id))  \(subscription.name) — \(amount)/"
                        + "\(subscription.period.label(korean: true)) [\(subscription.status.label(korean: true))]\(next)"
                    )
                }
            }
        case "import":
            guard scanner.value("from") == "ai-cli-account-manager" else {
                throw UsageError("sub import 는 --from ai-cli-account-manager 만 지원합니다")
            }
            let importer = AiSubscriptionImporter(
                cliPath: scanner.value("source-cli") ?? HostPlatform.cliBinPath("ai-cli-account-manager")
            )
            let fetched = try await importer.fetch()
            // --match 는 라벨·클라이언트·플랜 부분일치. 개인/사업 원장이 갈려 있으므로
            // 어느 쪽으로 들어갈지는 호출자가 고른다 — 원장이 남의 구독을 떠안지 않게.
            let match = scanner.value("match")
            let rows = match.map { needle in
                fetched.filter {
                    [$0.label, $0.client, $0.plan ?? ""].contains { $0.localizedCaseInsensitiveContains(needle) }
                }
            } ?? fetched
            var businessID: String?
            if let bizRef = scanner.value("business") {
                businessID = try await store.resolveBusiness(bizRef).id
            }
            var cardID: String?
            if let cardRef = scanner.value("card") { cardID = try await store.resolveCard(cardRef).id }
            let existing = try await store.subscriptions(includeArchived: true)
            let dryRun = scanner.has("dry-run")
            var created: [String] = []
            var updated: [String] = []
            for row in rows {
                if var found = existing.first(where: {
                    $0.sourceApp == "ai-cli-account-manager" && $0.externalID == row.externalID
                }) {
                    found.name = row.displayName
                    found.amountMinor = row.monthlyMinor
                    found.currency = row.currency
                    found.nextBillingDate = row.nextBillingDate ?? found.nextBillingDate
                    found.promoEndsOn = row.promoEndsOn
                    found.regularAmountMinor = row.regularMinor
                    // 귀속은 사람 것 — 인자로 준 경우에만 덮는다.
                    found.businessID = businessID ?? found.businessID
                    found.paymentCardID = cardID ?? found.paymentCardID
                    updated.append(found.name)
                    if !dryRun { try await store.save(subscription: found) }
                } else {
                    let fresh = MoneySubscription(
                        name: row.displayName,
                        amount: .init(amountMinor: row.monthlyMinor, currency: row.currency),
                        billing: .init(
                            nextBillingDate: row.nextBillingDate,
                            promoEndsOn: row.promoEndsOn,
                            regularAmountMinor: row.regularMinor
                        ),
                        links: .init(
                            paymentCardID: cardID,
                            businessID: businessID,
                            sourceApp: "ai-cli-account-manager",
                            externalID: row.externalID
                        ),
                        note: row.label
                    )
                    created.append(fresh.name)
                    if !dryRun { try await store.save(subscription: fresh) }
                }
            }
            if json {
                output.okJSON([
                    "dryRun": dryRun, "created": created, "updated": updated,
                    "fetched": fetched.count, "matched": rows.count,
                ])
            } else {
                output.out(
                    (dryRun ? "[dry-run] " : "")
                    + "관측 \(fetched.count) · 대상 \(rows.count) · 신규 \(created.count) · 갱신 \(updated.count)"
                )
                for name in created { output.out("  + \(name)") }
                for name in updated { output.out("  ~ \(name)") }
            }
        case "show":
            emit(try await store.resolveSubscription(try ref(sub, action)), json: json, output: output)
        case "update":
            var subscription = try await store.resolveSubscription(try ref(sub, action))
            if let name = scanner.value("name") { subscription.name = name }
            if let amountRaw = scanner.value("amount") {
                let currency = scanner.value("currency") ?? subscription.currency
                subscription.currency = currency
                subscription.amountMinor = try MoneyAmount.minorUnits(from: amountRaw, currency: currency)
            } else if let currency = scanner.value("currency") {
                subscription.currency = MoneyAmount.normalizedCurrency(currency)
            }
            if let periodRaw = scanner.value("period") { subscription.period = try parsePeriod(periodRaw) }
            if let next = scanner.value("next-billing") {
                guard LedgerDate.isValid(next) else {
                    throw UsageError("--next-billing 은 yyyy-MM-dd 형식입니다: \(next)")
                }
                subscription.nextBillingDate = next
            }
            if let cardRef = scanner.value("card") {
                subscription.paymentCardID = try await store.resolveCard(cardRef).id
            }
            if let accountRef = scanner.value("account") {
                subscription.paymentAccountID = try await store.resolveAccount(accountRef).id
            }
            if let bizRef = scanner.value("business") {
                subscription.businessID = try await store.resolveBusiness(bizRef).id
            }
            if let promoEnds = scanner.value("promo-ends") {
                guard LedgerDate.isValid(promoEnds) else {
                    throw UsageError("--promo-ends 는 yyyy-MM-dd 형식입니다: \(promoEnds)")
                }
                subscription.promoEndsOn = promoEnds
            }
            if let raw = scanner.value("regular-amount") {
                subscription.regularAmountMinor = try MoneyAmount.minorUnits(
                    from: raw, currency: subscription.currency
                )
            }
            if let note = scanner.value("note") { subscription.note = note }
            try await store.save(subscription: subscription)
            emit(subscription, json: json, output: output)
        case "pause", "resume", "cancel":
            var subscription = try await store.resolveSubscription(try ref(sub, action))
            switch action {
            case "pause": subscription.status = .paused
            case "resume": subscription.status = .active
            default: subscription.status = .cancelled
            }
            try await store.save(subscription: subscription)
            emit(subscription, json: json, output: output)
        case "archive", "unarchive":
            var subscription = try await store.resolveSubscription(try ref(sub, action))
            subscription.archived = action == "archive"
            try await store.save(subscription: subscription)
            emit(subscription, json: json, output: output)
        case "remove":
            let subscription = try await store.resolveSubscription(try ref(sub, action))
            guard scanner.has("purge") else {
                throw UsageError("완전 삭제는 --purge 를 명시하세요 (해지는 sub cancel)")
            }
            try await store.deleteSubscription(id: subscription.id)
            if json {
                output.okJSON(["removed": subscription.id])
            } else {
                output.out("삭제됨: \(subscription.name)")
            }
        default:
            throw UsageError("unknown: sub \(action)")
        }
    }

    /// `--source` / `--external-id` 는 짝이다 — 하나만 주면 동일성 키가 안 서고
    /// 다음 수입 때 중복 행이 생긴다.
    private static func externalLink(_ scanner: ArgScanner) throws -> (String?, String?) {
        let source = scanner.value("source")
        let external = scanner.value("external-id")
        switch (source, external) {
        case (nil, nil): return (nil, nil)
        case let (s?, e?): return (s, e)
        default:
            throw UsageError("--source 와 --external-id 는 함께 준다 (외부 앱 링크는 짝이어야 중복을 막는다)")
        }
    }

    private static func emit(_ subscription: MoneySubscription, json: Bool, output: CLIOutput) {
        if json {
            output.okJSON(["subscription": CLIFormat.subscriptionObject(subscription)])
        } else {
            let amount = MoneyAmount.format(minor: subscription.amountMinor, currency: subscription.currency)
            output.out(
                "\(CLIFormat.shortID(subscription.id))  \(subscription.name) — \(amount)/"
                + subscription.period.label(korean: true)
            )
        }
    }

    private static func ref(_ sub: [String], _ action: String) throws -> String {
        guard sub.count >= 2 else { throw UsageError("sub \(action) <id|이름>") }
        return sub[1]
    }

    private static func parsePeriod(_ raw: String) throws -> BillingPeriod {
        switch raw.lowercased() {
        case "monthly", "month": .monthly
        case "yearly", "year", "annual": .yearly
        case "one-time", "onetime", "once": .oneTime
        default: throw UsageError("--period 는 monthly|yearly|one-time 중 하나입니다: \(raw)")
        }
    }

    private static func parseStatus(_ raw: String) throws -> SubscriptionStatus {
        guard let status = SubscriptionStatus(rawValue: raw.lowercased()) else {
            throw UsageError("--status 는 active|paused|cancelled 중 하나입니다: \(raw)")
        }
        return status
    }
}
