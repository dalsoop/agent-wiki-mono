import Foundation
import MoneyLedgerKit
import MoneyLedgerReportKit

/// export 커맨드 — 거래 내역 내보내기 (CSV, Excel 호환).
enum ExportCommands {
    static func run(
        context: LedgerContext, sub: [String], scanner: ArgScanner, json: Bool, output: CLIOutput
    ) async throws {
        let format = scanner.value("format") ?? "csv"
        guard format.lowercased() == "csv" else {
            throw UsageError("지원하지 않는 형식입니다: \(format) (csv 지원)")
        }

        let fromDate = scanner.value("from")
        let toDate = scanner.value("to")
        try validateDate(fromDate, flag: "--from")
        try validateDate(toDate, flag: "--to")

        let store = try LedgerStore(context: context)
        let accounts = try await store.accounts(includeArchived: true)
        let cards = try await store.cards(includeArchived: true)
        let transactions = try await store.transactions(
            TransactionQuery(fromDate: fromDate, toDate: toDate)
        )

        let csvData = LedgerExport.csv(transactions: transactions, accounts: accounts, cards: cards)
        guard let outputPath = scanner.value("output") else {
            handleStandardOutput(csvData: csvData, count: transactions.count, json: json, output: output)
            return
        }
        try writeToFile(csvData: csvData, path: outputPath, count: transactions.count, json: json, output: output)
    }

    private static func validateDate(_ date: String?, flag: String) throws {
        guard let d = date else { return }
        guard LedgerDate.isValid(d) else {
            throw UsageError("날짜 형식이 올바르지 않습니다(\(flag) yyyy-MM-dd): \(d)")
        }
    }

    private static func writeToFile(csvData: Data, path: String, count: Int, json: Bool, output: CLIOutput) throws {
        let url = URL(fileURLWithPath: path)
        try csvData.write(to: url)
        switch json {
        case true:
            output.okJSON(["format": "csv", "path": path, "count": count])
        case false:
            output.out("CSV 내보내기 완료: \(path) (\(count)건)")
        }
    }

    private static func handleStandardOutput(csvData: Data, count: Int, json: Bool, output: CLIOutput) {
        switch json {
        case true:
            let csvStr = String(data: csvData.dropFirst(3), encoding: .utf8) ?? ""
            output.okJSON(["format": "csv", "count": count, "csv": csvStr])
        case false:
            guard let str = String(data: csvData, encoding: .utf8) else {
                FileHandle.standardOutput.write(csvData)
                return
            }
            output.out(str)
        }
    }
}
