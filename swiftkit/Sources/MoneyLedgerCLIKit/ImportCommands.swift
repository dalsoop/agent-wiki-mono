import Foundation
import MoneyLedgerKit

/// import(CSV 가져오기) 서브커맨드 — CSVImportService 와 같은 경로(GUI 가져오기와 공용).
enum ImportCommands {
    static func run(
        context: LedgerContext, sub: [String], scanner: ArgScanner, json: Bool, output: CLIOutput
    ) async throws {
        let store = try LedgerStore(context: context)
        let action = sub.first ?? "list"
        switch action {
        case "csv":
            try await csv(store: store, sub: sub, scanner: scanner, json: json, output: output)
        case "list":
            try await list(store: store, json: json, output: output)
        case "show":
            guard sub.count >= 2 else { throw UsageError("import show <배치id>") }
            let batch = try await store.importBatch(idPrefix: sub[1])
            if json { output.okJSON(["batch": batchObject(batch)]) } else {
                output.out("\(batch.id)\n  파일: \(batch.sourceFile)\n  매핑: \(batch.mapping)")
                output.out("  삽입 \(batch.inserted) · 중복 \(batch.duplicates) · 오류 \(batch.errorCount)")
            }
        case "undo":
            try await undo(store: store, sub: sub, scanner: scanner, json: json, output: output)
        default:
            throw UsageError("unknown: import \(action)")
        }
    }

    private static func csv(
        store: LedgerStore, sub: [String], scanner: ArgScanner, json: Bool, output: CLIOutput
    ) async throws {
        guard sub.count >= 2 else { throw UsageError("import csv <파일> --map … (--account|--card)") }
        guard let mapSpec = scanner.value("map") else {
            throw UsageError("--map 이 필요합니다 — 예: --map \"date=거래일자,out=출금액,in=입금액,desc=적요\"")
        }
        let mapping = try ColumnMapping.parse(mapSpec)
        var accountID: String?
        var cardID: String?
        if let accountRef = scanner.value("account") {
            accountID = try await store.resolveAccount(accountRef).id
        }
        if let cardRef = scanner.value("card") { cardID = try await store.resolveCard(cardRef).id }
        // --business: 배치 전체 귀속. 은행 CSV 한 장은 한 사업체 계좌에서 나온다.
        let businessID = try await BusinessArgument.resolveID(store: store, scanner: scanner)
        let encoding = CSVTable.SourceEncoding(rawValue: scanner.value("encoding") ?? "auto") ?? .auto
        let dryRun = scanner.has("dry-run")
        let result = try await CSVImportService().run(
            store: store,
            fileURL: URL(fileURLWithPath: sub[1]),
            request: CSVImportRequest(
                mapping: mapping,
                accountID: accountID,
                cardID: cardID,
                businessID: businessID,
                currency: scanner.value("currency") ?? "KRW",
                encoding: encoding,
                skipRows: scanner.value("skip-rows").flatMap(Int.init) ?? 0,
                dryRun: dryRun
            )
        )
        if json {
            output.okJSON(resultObject(result, dryRun: dryRun, businessID: businessID))
        } else {
            renderResult(result, dryRun: dryRun, output: output)
        }
    }

    private static func resultObject(_ result: ImportResult, dryRun: Bool, businessID: String?) -> [String: Any] {
        var object: [String: Any] = [
            "dryRun": dryRun,
            "totalRows": result.totalRows,
            "inserted": result.inserted,
            "duplicates": result.duplicates,
            "encoding": result.encodingName,
            "errors": result.errors.map { ["line": $0.line, "reason": $0.reason] },
        ]
        if let batchID = result.batchID { object["batchID"] = batchID }
        if let businessID { object["businessID"] = businessID }
        if dryRun { object["preview"] = result.preview.map(CLIFormat.transactionObject) }
        return object
    }

    private static func renderResult(_ result: ImportResult, dryRun: Bool, output: CLIOutput) {
        let prefix = dryRun ? "[dry-run] " : ""
        output.out(
            "\(prefix)총 \(result.totalRows)행 → 삽입 \(result.inserted) · 중복 \(result.duplicates)"
            + " · 오류 \(result.errors.count) (인코딩 \(result.encodingName))"
        )
        for error in result.errors.prefix(10) {
            output.out("  \(error.line)행: \(error.reason)")
        }
        if dryRun {
            for tx in result.preview.prefix(10) {
                let amount = MoneyAmount.format(minor: tx.amountMinor, currency: tx.currency)
                output.out("  \(tx.date)  \(amount)  \(tx.description)")
            }
        }
        if let batchID = result.batchID { output.out("배치: \(batchID)") }
    }

    private static func list(store: LedgerStore, json: Bool, output: CLIOutput) async throws {
        let batches = try await store.importBatches()
        if json {
            output.okJSON(["batches": batches.map(batchObject)])
        } else if batches.isEmpty {
            output.out("가져오기 기록 없음")
        } else {
            for batch in batches {
                output.out(
                    "\(CLIFormat.shortID(batch.id))  \(batch.sourceFile) — 삽입 \(batch.inserted)"
                    + " · 중복 \(batch.duplicates) · 오류 \(batch.errorCount)"
                )
            }
        }
    }

    private static func undo(
        store: LedgerStore, sub: [String], scanner: ArgScanner, json: Bool, output: CLIOutput
    ) async throws {
        guard sub.count >= 2 else { throw UsageError("import undo <배치id> [--dry-run]") }
        let batch = try await store.importBatch(idPrefix: sub[1])
        let count = try await store.transactionCount(inBatch: batch.id)
        if scanner.has("dry-run") {
            if json {
                output.okJSON(["batchID": batch.id, "wouldRemove": count])
            } else {
                output.out("[dry-run] \(batch.id) undo 시 거래 \(count)건 삭제")
            }
            return
        }
        let removed = try await store.undoImportBatch(id: batch.id)
        if json {
            output.okJSON(["batchID": batch.id, "removed": removed])
        } else {
            output.out("undo 완료: 거래 \(removed)건 삭제")
        }
    }

    private static func batchObject(_ batch: ImportBatch) -> [String: Any] {
        [
            "id": batch.id,
            "createdAt": ISO8601DateFormatter().string(from: batch.createdAt),
            "sourceFile": batch.sourceFile,
            "encoding": batch.encoding,
            "mapping": batch.mapping,
            "inserted": batch.inserted,
            "duplicates": batch.duplicates,
            "errorCount": batch.errorCount,
        ]
    }
}
