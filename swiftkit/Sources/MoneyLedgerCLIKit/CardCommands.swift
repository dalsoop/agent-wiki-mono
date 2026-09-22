import Foundation
import MoneyLedgerKit

/// card 서브커맨드.
enum CardCommands {
    static func run(
        context: LedgerContext, sub: [String], scanner: ArgScanner, json: Bool, output: CLIOutput
    ) async throws {
        let store = try LedgerStore(context: context)
        let action = sub.first ?? "list"
        switch action {
        case "add":
            guard let name = scanner.value("name"), let issuer = scanner.value("issuer") else {
                throw UsageError("card add 는 --name, --issuer 가 필요합니다")
            }
            if scanner.has("if-not-exists") {
                let existing: MoneyCard?
                do {
                    existing = try await store.resolveCard(name)
                } catch {
                    existing = nil
                }
                if let existing {
                    emit(existing, json: json, output: output)
                    return
                }
            }
            var linkedAccountID: String?
            if let accountRef = scanner.value("account") {
                linkedAccountID = try await store.resolveAccount(accountRef).id
            }
            let card = MoneyCard(
                name: name,
                issuer: issuer,
                last4: scanner.value("last4") ?? "",
                linkedAccountID: linkedAccountID,
                billingDay: scanner.value("billing-day").flatMap(Int.init),
                note: scanner.value("note")
            )
            try await store.save(card: card)
            emit(card, json: json, output: output)
        case "list":
            let cards = try await store.cards(includeArchived: scanner.has("all"))
            if json {
                output.okJSON(["cards": cards.map(CLIFormat.cardObject)])
            } else if cards.isEmpty {
                output.out("카드 없음 — card add --name <이름> --issuer <카드사>")
            } else {
                for card in cards {
                    let archived = card.archived ? " [보관]" : ""
                    let vault = card.vaultNoteRef != nil ? " 🔐" : ""
                    let day = card.billingDay.map { " 결제일 \($0)일" } ?? ""
                    output.out(
                        "\(CLIFormat.shortID(card.id))  \(card.name) — \(card.issuer)(\(card.last4))\(day)\(vault)\(archived)"
                    )
                }
            }
        case "show":
            let card = try await store.resolveCard(try ref(sub, action))
            emit(card, json: json, output: output)
        case "update":
            var card = try await store.resolveCard(try ref(sub, action))
            if let name = scanner.value("name") { card.name = name }
            if let issuer = scanner.value("issuer") { card.issuer = issuer }
            if let last4 = scanner.value("last4") { card.last4 = last4 }
            if let accountRef = scanner.value("account") {
                card.linkedAccountID = try await store.resolveAccount(accountRef).id
            }
            if let day = scanner.value("billing-day") { card.billingDay = Int(day) }
            if let note = scanner.value("note") { card.note = note }
            try await store.save(card: card)
            emit(card, json: json, output: output)
        case "archive", "unarchive":
            var card = try await store.resolveCard(try ref(sub, action))
            card.archived = action == "archive"
            try await store.save(card: card)
            emit(card, json: json, output: output)
        case "remove":
            let card = try await store.resolveCard(try ref(sub, action))
            guard scanner.has("purge") else {
                throw UsageError("완전 삭제는 --purge 를 명시하세요 (보통은 archive 로 충분)")
            }
            try await store.deleteCard(id: card.id)
            if json { output.okJSON(["removed": card.id]) } else { output.out("삭제됨: \(card.name)") }
        default:
            throw UsageError("unknown: card \(action)")
        }
    }

    private static func emit(_ card: MoneyCard, json: Bool, output: CLIOutput) {
        if json {
            output.okJSON(["card": CLIFormat.cardObject(card)])
        } else {
            output.out("\(CLIFormat.shortID(card.id))  \(card.name) — \(card.issuer)(\(card.last4))")
        }
    }

    private static func ref(_ sub: [String], _ action: String) throws -> String {
        guard sub.count >= 2 else { throw UsageError("card \(action) <id|이름>") }
        return sub[1]
    }
}
