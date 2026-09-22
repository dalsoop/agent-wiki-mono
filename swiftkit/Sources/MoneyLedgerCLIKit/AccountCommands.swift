import Foundation
import MoneyLedgerKit

/// account 서브커맨드.
enum AccountCommands {
    static func run(
        context: LedgerContext, sub: [String], scanner: ArgScanner, json: Bool, output: CLIOutput
    ) async throws {
        let store = try LedgerStore(context: context)
        let action = sub.first ?? "list"
        if sub.contains("--help") { return }
        switch action {
        case "add":
            try await handleAdd(store: store, scanner: scanner, json: json, output: output)
        case "list":
            try await handleList(store: store, scanner: scanner, json: json, output: output)
        case "show":
            let account = try await store.resolveAccount(try ref(sub, action))
            emit(account, json: json, output: output)
        case "update":
            try await handleUpdate(store: store, sub: sub, scanner: scanner, json: json, output: output)
        case "archive", "unarchive":
            try await handleArchive(store: store, sub: sub, action: action, json: json, output: output)
        case "remove":
            try await handleRemove(store: store, sub: sub, scanner: scanner, json: json, output: output)
        default:
            throw UsageError("unknown: account \(action)")
        }
    }

    private static func handleAdd(
        store: LedgerStore, scanner: ArgScanner, json: Bool, output: CLIOutput
    ) async throws {
        guard let name = scanner.value("name") else {
            throw UsageError("account add 는 --name 이 필요합니다")
        }
        let type = try scanner.value("type").map(parseType) ?? .checking
        let currency = scanner.value("currency") ?? "KRW"
        let bank = try resolveBank(scanner: scanner, type: type)

        let initialBalance = try scanner.value("initial-balance").map {
            try MoneyAmount.minorUnits(from: $0, currency: currency)
        }

        if scanner.has("if-not-exists") {
            do {
                let existing = try await store.resolveAccount(name)
                emit(existing, json: json, output: output, note: "already-exists")
                return
            } catch {
                FileHandle.standardError.write(Data("[debug] account not found, proceeding with add\n".utf8))
            }
        }
        let account = MoneyAccount(
            name: name,
            bank: bank,
            last4: scanner.value("last4") ?? "",
            currency: currency,
            accountType: type,
            initialBalanceMinor: initialBalance,
            purpose: scanner.value("purpose"),
            note: scanner.value("note")
        )
        try await store.save(account: account)
        emit(account, json: json, output: output)
    }

    private static func resolveBank(scanner: ArgScanner, type: MoneyAccountType) throws -> String {
        if let b = scanner.value("bank"), !b.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return b
        }
        let exemptTypes: [MoneyAccountType] = [.cash, .realEstate, .investment]
        if exemptTypes.contains(type) { return type.label(korean: true) }
        throw UsageError("account add 는 --bank 가 필요합니다 (\(type.rawValue) 유형은 제외)")
    }

    private static func handleList(
        store: LedgerStore, scanner: ArgScanner, json: Bool, output: CLIOutput
    ) async throws {
        let accounts = try await store.accounts(includeArchived: scanner.has("all") || scanner.has("archived"))
        if json {
            output.okJSON(["accounts": accounts.map(CLIFormat.accountObject)])
            return
        }
        renderAccountList(accounts, output: output)
    }

    private static func renderAccountList(_ accounts: [MoneyAccount], output: CLIOutput) {
        for account in accounts {
            let typeLabel = account.accountType.map { " [\($0.label(korean: true))]" } ?? ""
            let initial = account.initialBalanceMinor.map { " (초기: \(MoneyAmount.format(minor: $0, currency: account.currency)))" } ?? ""
            let vault = account.vaultNoteRef.map { " [vault:\($0)]" } ?? ""
            let archived = account.archived ? " [보관됨]" : ""
            output.out(
                "\(CLIFormat.shortID(account.id))  \(account.name)\(typeLabel) — \(account.bank)"
                + "(\(account.last4)) \(account.currency)\(initial)\(vault)\(archived)"
            )
        }
    }

    private static func handleUpdate(
        store: LedgerStore, sub: [String], scanner: ArgScanner, json: Bool, output: CLIOutput
    ) async throws {
        var account = try await store.resolveAccount(try ref(sub, "update"))
        applyIdentityUpdates(&account, scanner: scanner)
        try applyTypeAndBalanceUpdates(&account, scanner: scanner)
        applyMetadataUpdates(&account, scanner: scanner)
        try await store.save(account: account)
        emit(account, json: json, output: output)
    }

    private static func applyIdentityUpdates(_ account: inout MoneyAccount, scanner: ArgScanner) {
        if let name = scanner.value("name") { account.name = name }
        if let bank = scanner.value("bank") { account.bank = bank }
    }

    private static func applyTypeAndBalanceUpdates(_ account: inout MoneyAccount, scanner: ArgScanner) throws {
        try applyTypeUpdates(&account, scanner: scanner)
        try applyBalanceUpdates(&account, scanner: scanner)
    }

    private static func applyTypeUpdates(_ account: inout MoneyAccount, scanner: ArgScanner) throws {
        if let last4 = scanner.value("last4") { account.last4 = last4 }
        if let rawType = scanner.value("type") { account.accountType = try parseType(rawType) }
    }

    private static func applyBalanceUpdates(_ account: inout MoneyAccount, scanner: ArgScanner) throws {
        if let rawInitial = scanner.value("initial-balance") {
            account.initialBalanceMinor = try MoneyAmount.minorUnits(from: rawInitial, currency: account.currency)
        }
    }

    private static func applyMetadataUpdates(_ account: inout MoneyAccount, scanner: ArgScanner) {
        if let purpose = scanner.value("purpose") { account.purpose = purpose }
        if let note = scanner.value("note") { account.note = note }
    }

    private static func handleArchive(
        store: LedgerStore, sub: [String], action: String, json: Bool, output: CLIOutput
    ) async throws {
        var account = try await store.resolveAccount(try ref(sub, action))
        account.archived = action == "archive"
        try await store.save(account: account)
        emit(account, json: json, output: output)
    }

    private static func handleRemove(
        store: LedgerStore, sub: [String], scanner: ArgScanner, json: Bool, output: CLIOutput
    ) async throws {
        let account = try await store.resolveAccount(try ref(sub, "remove"))
        guard scanner.has("purge") else {
            throw UsageError("완전 삭제는 --purge 를 명시하세요 (보통은 archive 로 충분)")
        }
        try await store.deleteAccount(id: account.id)
        if json { output.okJSON(["removed": account.id]) } else { output.out("삭제됨: \(account.name)") }
    }

    static func parseType(_ raw: String) throws -> MoneyAccountType {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
        guard let match = MoneyAccountType.allCases.first(where: {
            $0.rawValue.lowercased() == normalized
        }) else {
            let valid = MoneyAccountType.allCases.map(\.rawValue).joined(separator: ", ")
            throw UsageError("유효하지 않은 계좌 유형: '\(raw)' (사용 가능: \(valid))")
        }
        return match
    }

    private static func emit(_ account: MoneyAccount, json: Bool, output: CLIOutput, note: String? = nil) {
        if json {
            var object = CLIFormat.accountObject(account)
            if let note { object["note_"] = note }
            output.okJSON(["account": object])
        } else {
            let typeLabel = account.accountType.map { " [\($0.label(korean: true))]" } ?? ""
            output.out("\(CLIFormat.shortID(account.id))  \(account.name)\(typeLabel) — \(account.bank)(\(account.last4))")
        }
    }

    private static func ref(_ sub: [String], _ action: String) throws -> String {
        guard sub.count >= 2 else { throw UsageError("account \(action) <id|이름>") }
        return sub[1]
    }
}
