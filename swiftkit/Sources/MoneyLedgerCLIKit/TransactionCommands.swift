import Foundation
import MoneyLedgerKit

/// tx(입출금 거래) 서브커맨드. CSV 가져오기는 ImportCommands 가 맡는다.
enum TransactionCommands {
    static func run(
        context: LedgerContext, sub: [String], scanner: ArgScanner, json: Bool, output: CLIOutput
    ) async throws {
        let store = try LedgerStore(context: context)
        let action = sub.first ?? "list"
        // --help/-h 는 LedgerCLI.run 이 분기 전에 arguments.contains("--help") 로 가로챈다 —
        // ArgScanner 가 플래그를 걷어내므로 여기 sub 에는 도움말 요청이 올 수 없다.
        switch action {
        case "add":
            try await add(store: store, scanner: scanner, json: json, output: output)
        case "transfer":
            try await transfer(store: store, scanner: scanner, json: json, output: output)
        case "settle-card":
            try await settleCard(store: store, scanner: scanner, json: json, output: output)
        case "update":
            try await update(store: store, sub: sub, scanner: scanner, json: json, output: output)
        case "list":
            try await list(store: store, scanner: scanner, json: json, output: output)
        case "show":
            let tx = try await store.transaction(idPrefix: try ref(sub, action))
            emit(tx, prefix: "", json: json, output: output)
        case "set-category":
            guard sub.count >= 3 else { throw UsageError("tx set-category <id> <카테고리>") }
            var tx = try await store.transaction(idPrefix: sub[1])
            tx.category = sub[2]
            try await store.update(transaction: tx)
            emit(tx, prefix: "분류됨: ", json: json, output: output)
        case "set-business":
            // 사업체 귀속은 사후 정정이 흔하다(가져온 뒤 사업체별로 가른다). `none` 이면 해제.
            guard sub.count >= 3 else { throw UsageError("tx set-business <id> <사업체|none>") }
            var tx = try await store.transaction(idPrefix: sub[1])
            tx.businessID = try await BusinessArgument.resolveID(store: store, reference: sub[2])
            try await store.update(transaction: tx)
            let prefix = tx.businessID == nil ? "사업체 해제됨: " : "사업체 귀속됨: "
            emit(tx, prefix: prefix, json: json, output: output)
        case "remove":
            try await remove(store: store, sub: sub, scanner: scanner, json: json, output: output)
        default:
            throw UsageError("unknown: tx \(action)")
        }
    }

    private static func add(
        store: LedgerStore, scanner: ArgScanner, json: Bool, output: CLIOutput
    ) async throws {
        guard let rawDate = scanner.value("date"), let rawAmount = scanner.value("amount") else {
            throw UsageError("tx add 는 --date, --amount 가 필요합니다")
        }
        let (date, inlineTime) = try LedgerDate.normalize(rawDate)
        let currency = scanner.value("currency") ?? "KRW"
        var amount = try MoneyAmount.minorUnits(from: rawAmount, currency: currency)
        let kind = try scanner.value("kind").map(parseKind)
        if let kind {
            switch kind {
            case .expense:
                amount = -abs(amount)
            case .income:
                amount = abs(amount)
            case .transfer, .settlement:
                break
            }
        }
        let description = scanner.value("desc") ?? ""
        let parties = try await parties(store: store, scanner: scanner)
        let time = scanner.value("time").flatMap(LedgerDate.normalizeTime) ?? inlineTime
        let balance = try scanner.value("balance").map { try MoneyAmount.minorUnits(from: $0, currency: currency) }

        // --allow-duplicate: 진짜 같은 내용 거래를 한 번 더 기록해야 할 때 새 id 로 해시를 소금친다.
        // 사업체 귀속은 해시에 안 들어간다 — 같은 은행 행은 어느 사업체로 갈라도 같은 거래다.
        let saltID = UUID().uuidString.lowercased()
        let hash = ContentHash.transactionHash(
            date: date,
            time: time,
            amountMinor: amount,
            currency: currency,
            instrumentID: parties.accountID ?? parties.cardID ?? "",
            description: scanner.has("allow-duplicate") ? description + "|salt:" + saltID : description,
            balanceAfterMinor: balance
        )
        let tx = MoneyTransaction(
            id: saltID,
            stamp: .init(date: date, time: time),
            amount: .init(amountMinor: amount, currency: currency, balanceAfterMinor: balance),
            parties: parties,
            narrative: .init(
                description: description,
                category: scanner.value("category"),
                memo: scanner.value("memo")
            ),
            kind: kind,
            contentHash: hash
        )
        let outcome = try await store.insert(transaction: tx)
        if json {
            var object = CLIFormat.transactionObject(outcome.transaction)
            object["duplicate"] = outcome.duplicate
            output.okJSON(["transaction": object])
        } else {
            output.out((outcome.duplicate ? "이미 있음(중복): " : "기록됨: ") + render(outcome.transaction))
        }
    }

    private static func transfer(
        store: LedgerStore, scanner: ArgScanner, json: Bool, output: CLIOutput
    ) async throws {
        guard let fromRef = scanner.value("from"),
              let toRef = scanner.value("to"),
              let rawAmount = scanner.value("amount") else {
            throw UsageError("tx transfer 는 --from <출금계좌>, --to <입금계좌>, --amount <금액> 이 필요합니다")
        }
        let currency = scanner.value("currency") ?? "KRW"
        let amount = try MoneyAmount.minorUnits(from: rawAmount, currency: currency)
        let rawDate = scanner.value("date") ?? LedgerDate.today()
        let (date, _) = try LedgerDate.normalize(rawDate)
        let desc = scanner.value("desc")

        let (withdrawal, deposit) = try await store.createTransfer(
            fromAccountID: fromRef,
            toAccountID: toRef,
            amountMinor: amount,
            currency: currency,
            date: date,
            description: desc
        )
        if json {
            output.okJSON([
                "transfer": [
                    "withdrawal": CLIFormat.transactionObject(withdrawal),
                    "deposit": CLIFormat.transactionObject(deposit)
                ]
            ])
        } else {
            output.out("이체 완료:")
            output.out("  출금: " + render(withdrawal))
            output.out("  입금: " + render(deposit))
        }
    }

    private static func settleCard(
        store: LedgerStore, scanner: ArgScanner, json: Bool, output: CLIOutput
    ) async throws {
        guard let fromRef = scanner.value("from"),
              let cardRef = scanner.value("card"),
              let rawAmount = scanner.value("amount") else {
            throw UsageError("tx settle-card 는 --from <출금계좌>, --card <카드>, --amount <금액> 이 필요합니다")
        }
        let currency = scanner.value("currency") ?? "KRW"
        let amount = try MoneyAmount.minorUnits(from: rawAmount, currency: currency)
        let rawDate = scanner.value("date") ?? LedgerDate.today()
        let (date, _) = try LedgerDate.normalize(rawDate)
        let desc = scanner.value("desc")

        let (withdrawal, settlement) = try await store.settleCard(
            fromAccountID: fromRef,
            cardID: cardRef,
            amountMinor: amount,
            currency: currency,
            date: date,
            description: desc
        )
        if json {
            output.okJSON([
                "settlement": [
                    "withdrawal": CLIFormat.transactionObject(withdrawal),
                    "settlement": CLIFormat.transactionObject(settlement)
                ]
            ])
        } else {
            output.out("카드대금 납부 완료:")
            output.out("  계좌출금: " + render(withdrawal))
            output.out("  카드납부: " + render(settlement))
        }
    }

    private static func update(
        store: LedgerStore, sub: [String], scanner: ArgScanner, json: Bool, output: CLIOutput
    ) async throws {
        let idRef = try ref(sub, "update")
        var tx = try await store.transaction(idPrefix: idRef)
        try applyBasicUpdateFields(tx: &tx, scanner: scanner)
        try applyClassificationUpdateFields(tx: &tx, scanner: scanner)
        try await store.update(transaction: tx)
        emit(tx, prefix: "수정됨: ", json: json, output: output)
    }

    private static func applyBasicUpdateFields(tx: inout MoneyTransaction, scanner: ArgScanner) throws {
        try applyAmountAndDesc(tx: &tx, scanner: scanner)
        try applyDate(tx: &tx, scanner: scanner)
    }

    private static func applyAmountAndDesc(tx: inout MoneyTransaction, scanner: ArgScanner) throws {
        if let rawAmount = scanner.value("amount") {
            tx.amountMinor = try MoneyAmount.minorUnits(from: rawAmount, currency: tx.currency)
        }
        if let desc = scanner.value("desc") {
            tx.description = desc
        }
    }

    private static func applyDate(tx: inout MoneyTransaction, scanner: ArgScanner) throws {
        if let rawDate = scanner.value("date") {
            let (date, time) = try LedgerDate.normalize(rawDate)
            tx.date = date
            if let time { tx.time = time }
        }
    }

    private static func applyClassificationUpdateFields(tx: inout MoneyTransaction, scanner: ArgScanner) throws {
        applyCategoryAndMemo(tx: &tx, scanner: scanner)
        if let rawKind = scanner.value("kind") {
            tx.kind = try parseKind(rawKind)
        }
    }

    private static func applyCategoryAndMemo(tx: inout MoneyTransaction, scanner: ArgScanner) {
        if let category = scanner.value("category") {
            tx.category = category.lowercased() == "none" ? nil : category
        }
        if let memo = scanner.value("memo") {
            tx.memo = memo.lowercased() == "none" ? nil : memo
        }
    }

    /// 결제수단(--account|--card 정확히 하나) + 귀속 사업체(--business, 선택).
    private static func parties(store: LedgerStore, scanner: ArgScanner) async throws -> MoneyTransaction.Parties {
        var accountID: String?
        var cardID: String?
        if let accountRef = scanner.value("account") { accountID = try await store.resolveAccount(accountRef).id }
        if let cardRef = scanner.value("card") { cardID = try await store.resolveCard(cardRef).id }
        guard (accountID == nil) != (cardID == nil) else {
            throw UsageError("--account 또는 --card 중 정확히 하나를 지정하세요")
        }
        let businessID = try await BusinessArgument.resolveID(store: store, scanner: scanner)
        return MoneyTransaction.Parties(accountID: accountID, cardID: cardID, businessID: businessID)
    }

    private static func list(
        store: LedgerStore, scanner: ArgScanner, json: Bool, output: CLIOutput
    ) async throws {
        let query = try await buildTransactionQuery(store: store, scanner: scanner)
        let transactions = try await store.transactions(query)
        if json {
            output.okJSON([
                "transactions": transactions.map(CLIFormat.transactionObject),
                "count": transactions.count,
            ])
        } else if transactions.isEmpty {
            output.out("거래 없음")
        } else {
            for tx in transactions { output.out(render(tx)) }
        }
    }

    private static func buildTransactionQuery(store: LedgerStore, scanner: ArgScanner) async throws -> TransactionQuery {
        var query = TransactionQuery()
        try applyDateRange(to: &query, scanner: scanner)
        try await applyTargetFilters(to: &query, store: store, scanner: scanner)
        query.limit = scanner.value("limit").flatMap(Int.init) ?? 100
        return query
    }

    private static func applyDateRange(to query: inout TransactionQuery, scanner: ArgScanner) throws {
        if let month = scanner.value("month") {
            let range = try LedgerDate.monthRange(month)
            query.fromDate = range.from
            query.toDate = range.to
        }
        try applyFromToRange(to: &query, scanner: scanner)
    }

    private static func applyFromToRange(to query: inout TransactionQuery, scanner: ArgScanner) throws {
        if let from = scanner.value("from") { query.fromDate = try LedgerDate.normalize(from).date }
        if let to = scanner.value("to") { query.toDate = try LedgerDate.normalize(to).date }
    }

    private static func applyTargetFilters(to query: inout TransactionQuery, store: LedgerStore, scanner: ArgScanner) async throws {
        try await applyAccountAndCardFilters(to: &query, store: store, scanner: scanner)
        if let category = scanner.value("category") { query.category = category }
        query.businessID = try await BusinessArgument.resolveID(store: store, scanner: scanner)
    }

    private static func applyAccountAndCardFilters(to query: inout TransactionQuery, store: LedgerStore, scanner: ArgScanner) async throws {
        if let accountRef = scanner.value("account") {
            query.accountID = try await store.resolveAccount(accountRef).id
        }
        if let cardRef = scanner.value("card") { query.cardID = try await store.resolveCard(cardRef).id }
    }

    private static func remove(
        store: LedgerStore, sub: [String], scanner: ArgScanner, json: Bool, output: CLIOutput
    ) async throws {
        let tx = try await store.transaction(idPrefix: try ref(sub, "remove"))
        if scanner.has("dry-run") {
            emitDryRunRemove(tx: tx, json: json, output: output)
            return
        }
        try await store.deleteTransaction(id: tx.id)
        emitFinalRemove(tx: tx, json: json, output: output)
    }

    private static func emitDryRunRemove(tx: MoneyTransaction, json: Bool, output: CLIOutput) {
        if json {
            output.okJSON(["wouldRemove": CLIFormat.transactionObject(tx)])
        } else {
            output.out("삭제 예정: \(render(tx))")
        }
    }

    private static func emitFinalRemove(tx: MoneyTransaction, json: Bool, output: CLIOutput) {
        if json {
            output.okJSON(["removed": tx.id])
        } else {
            output.out("삭제됨: \(render(tx))")
        }
    }

    static func parseKind(_ raw: String) throws -> TransactionKind {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let match = TransactionKind.allCases.first(where: {
            $0.rawValue.lowercased() == normalized
        }) else {
            let valid = TransactionKind.allCases.map(\.rawValue).joined(separator: ", ")
            throw UsageError("유효하지 않은 거래 구분: '\(raw)' (사용 가능: \(valid))")
        }
        return match
    }

    private static func emit(_ tx: MoneyTransaction, prefix: String, json: Bool, output: CLIOutput) {
        if json {
            output.okJSON(["transaction": CLIFormat.transactionObject(tx)])
        } else {
            output.out(prefix + render(tx))
        }
    }

    private static func render(_ tx: MoneyTransaction) -> String {
        let amount = MoneyAmount.format(minor: tx.amountMinor, currency: tx.currency)
        let kind = tx.kind.map { " (\($0.label(korean: true)))" } ?? ""
        let category = tx.category.map { " [\($0)]" } ?? ""
        let business = tx.businessID.map { "  biz:\(CLIFormat.shortID($0))" } ?? ""
        return "\(CLIFormat.shortID(tx.id))  \(tx.date)  \(amount)\(kind)  \(tx.description)\(category)\(business)"
    }

    private static func ref(_ sub: [String], _ action: String) throws -> String {
        guard sub.count >= 2 else { throw UsageError("tx \(action) <id>") }
        return sub[1]
    }
}
