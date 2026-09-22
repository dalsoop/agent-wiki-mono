import Foundation
import MoneyLedgerStoreKit
import MoneyLedgerModels

/// CSV 컬럼 → 거래 필드 매핑. 값은 헤더 이름(부분일치 허용) 또는 1부터 세는 컬럼 번호.
/// 예: "date=거래일자,in=입금액,out=출금액,desc=적요,time=거래시간,balance=거래후잔액"
///     "date=1,amount=3,desc=4"  (amount = 부호 있는 단일 컬럼)
public struct ColumnMapping: Sendable, Equatable {
    public enum Key: String, Sendable, CaseIterable {
        case date          // 필수
        case time
        case amount        // amount 단독 또는 in/out 쌍 중 하나는 필수
        case inflow = "in"
        case outflow = "out"
        case desc          // 권장(없으면 빈 적요)
        case balance
        case category
        case memo
    }

    public let fields: [Key: String]

    public init(fields: [Key: String]) {
        self.fields = fields
    }

    public var specString: String {
        Key.allCases.compactMap { key in fields[key].map { "\(key.rawValue)=\($0)" } }
            .joined(separator: ",")
    }

    /// "key=value,key=value" 파싱. 값에 콤마가 든 헤더는 지원하지 않는다(은행 헤더에 없음).
    public static func parse(_ spec: String) throws -> ColumnMapping {
        var fields: [Key: String] = [:]
        for pair in spec.split(separator: ",") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2, let key = Key(rawValue: parts[0].trimmingCharacters(in: .whitespaces)) else {
                throw CSVImportError.badMapping(String(pair))
            }
            fields[key] = parts[1].trimmingCharacters(in: .whitespaces)
        }
        guard fields[.date] != nil else { throw CSVImportError.missingMappingKey("date") }
        let hasAmount = fields[.amount] != nil
        let hasSplit = fields[.inflow] != nil || fields[.outflow] != nil
        guard hasAmount || hasSplit else { throw CSVImportError.missingMappingKey("amount 또는 in/out") }
        guard !(hasAmount && hasSplit) else { throw CSVImportError.conflictingAmount }
        return ColumnMapping(fields: fields)
    }

    /// 헤더 행에 맞춰 실제 컬럼 인덱스로 해석한다.
    func resolve(header: [String]) throws -> [Key: Int] {
        var resolved: [Key: Int] = [:]
        for (key, ref) in fields {
            if let number = Int(ref) {
                guard number >= 1, number <= header.count else {
                    throw CSVImportError.columnOutOfRange(key.rawValue, ref, header.count)
                }
                resolved[key] = number - 1
                continue
            }
            let normalizedRef = ref.replacingOccurrences(of: " ", with: "")
            let index = header.firstIndex { column in
                column.replacingOccurrences(of: " ", with: "").contains(normalizedRef)
            }
            guard let index else { throw CSVImportError.columnNotFound(key.rawValue, ref, header) }
            resolved[key] = index
        }
        return resolved
    }
}

/// 가져오기 결과 — dry-run 은 배치를 저장하지 않고 이 요약만 돌려준다.
public struct ImportResult: Sendable, Equatable {
    public struct RowError: Sendable, Equatable {
        public let line: Int
        public let reason: String
    }

    public let batchID: String?
    public let totalRows: Int
    public let inserted: Int
    public let duplicates: Int
    public let errors: [RowError]
    public let encodingName: String
    /// dry-run 미리보기(최대 20건) — 실제 삽입될 거래.
    public let preview: [MoneyTransaction]
}

/// CSV 가져오기 인자 묶음. accountID/cardID 는 파일 전체 결제수단(정확히 하나).
/// businessID 는 배치 전체 귀속 사업체 — 은행 CSV 한 장은 한 사업체 계좌에서 나오므로 파일 단위다.
public struct CSVImportRequest: Sendable {
    public var mapping: ColumnMapping
    public var accountID: String?
    public var cardID: String?
    public var businessID: String?
    public var currency: String
    public var encoding: CSVTable.SourceEncoding
    public var skipRows: Int
    public var dryRun: Bool

    public init(
        mapping: ColumnMapping,
        accountID: String? = nil,
        cardID: String? = nil,
        businessID: String? = nil,
        currency: String = "KRW",
        encoding: CSVTable.SourceEncoding = .auto,
        skipRows: Int = 0,
        dryRun: Bool = false
    ) {
        self.mapping = mapping
        self.accountID = accountID
        self.cardID = cardID
        self.businessID = businessID
        self.currency = currency
        self.encoding = encoding
        self.skipRows = skipRows
        self.dryRun = dryRun
    }
}

/// 은행 CSV → 원장 거래 일괄 삽입. GUI 가져오기 시트와 CLI `import csv` 가 같은 경로를 쓴다.
public struct CSVImportService: Sendable {
    public init() {}

    /// skipRows: 헤더 위에 있는 안내 행 수(은행별로 제목·기간 행이 붙는 경우).
    public func run(
        store: LedgerStore,
        fileURL: URL,
        request: CSVImportRequest
    ) async throws -> ImportResult {
        let table = try CSVTable.read(url: fileURL, encoding: request.encoding)
        return try await run(
            store: store,
            table: table,
            sourceFile: fileURL.path,
            request: request
        )
    }

    public func run(
        store: LedgerStore,
        table: CSVTable,
        sourceFile: String,
        request: CSVImportRequest
    ) async throws -> ImportResult {
        guard (request.accountID == nil) != (request.cardID == nil) else {
            throw CSVImportError.instrumentRequired
        }
        let rows = Array(table.rows.dropFirst(request.skipRows))
        guard let header = rows.first else { throw CSVImportError.emptyFile }
        var parser = try CSVRowParser(
            header: header, request: request, batchID: UUID().uuidString.lowercased()
        )
        var parsed = ParsedRows()
        for (offset, row) in rows.dropFirst().enumerated() {
            do {
                parsed.candidates.append(try parser.parse(row))
            } catch {
                // 1-based 줄 번호, 헤더 다음부터.
                let line = request.skipRows + offset + 2
                parsed.errors.append(.init(line: line, reason: String(describing: error)))
            }
        }
        if request.dryRun {
            return try await preview(store: store, parsed: parsed, encodingName: table.encodingName)
        }
        let batch = ImportBatch(
            id: parser.batchID,
            sourceFile: sourceFile,
            encoding: table.encodingName,
            mapping: request.mapping.specString,
            inserted: 0,
            duplicates: 0,
            errorCount: parsed.errors.count
        )
        return try await commit(store: store, parsed: parsed, batch: batch)
    }

    private struct ParsedRows {
        var candidates: [MoneyTransaction] = []
        var errors: [ImportResult.RowError] = []
        var totalRows: Int { candidates.count + errors.count }
    }

    /// dry-run — 배치를 저장하지 않고 삽입/중복 수만 센다.
    private func preview(
        store: LedgerStore, parsed: ParsedRows, encodingName: String
    ) async throws -> ImportResult {
        var inserted = 0
        var duplicates = 0
        for candidate in parsed.candidates {
            if try await store.transactionByHash(candidate.contentHash) != nil {
                duplicates += 1
            } else {
                inserted += 1
            }
        }
        return ImportResult(
            batchID: nil,
            totalRows: parsed.totalRows,
            inserted: inserted,
            duplicates: duplicates,
            errors: parsed.errors,
            encodingName: encodingName,
            preview: Array(parsed.candidates.prefix(20))
        )
    }

    private func commit(
        store: LedgerStore, parsed: ParsedRows, batch template: ImportBatch
    ) async throws -> ImportResult {
        var inserted = 0
        var duplicates = 0
        for candidate in parsed.candidates {
            let outcome = try await store.insert(transaction: candidate)
            if outcome.duplicate { duplicates += 1 } else { inserted += 1 }
        }
        var batch = template
        batch.inserted = inserted
        batch.duplicates = duplicates
        // 아무것도 못 넣었어도 기록은 남긴다 — "왜 0건이지?"의 1차 근거.
        try await store.save(batch: batch)
        return ImportResult(
            batchID: batch.id,
            totalRows: parsed.totalRows,
            inserted: inserted,
            duplicates: duplicates,
            errors: parsed.errors,
            encodingName: batch.encoding,
            preview: Array(parsed.candidates.prefix(20))
        )
    }
}

/// CSV 한 행 → 거래 후보. 같은 파일 안 동일 내용 행은 occurrence 로 구분한다(해시 계약).
/// 결제수단·귀속 사업체·통화는 요청(파일 단위)에서 오고, 행은 날짜·금액·적요·잔액만 준다.
struct CSVRowParser {
    let columns: [ColumnMapping.Key: Int]
    let request: CSVImportRequest
    let batchID: String
    private var occurrenceByKey: [String: Int] = [:]

    init(header: [String], request: CSVImportRequest, batchID: String) throws {
        columns = try request.mapping.resolve(header: header)
        self.request = request
        self.batchID = batchID
    }

    var instrumentID: String { request.accountID ?? request.cardID ?? "" }

    mutating func parse(_ row: [String]) throws -> MoneyTransaction {
        let cells = CSVRowCells(row: row, columns: columns)
        guard let rawDate = cells[.date] else { throw CSVImportError.rowMissing("date") }
        let (date, inlineTime) = try LedgerDate.normalize(rawDate)
        let time = cells[.time].flatMap(LedgerDate.normalizeTime) ?? inlineTime
        let amountMinor = try amount(cells)
        let description = cells[.desc] ?? ""
        let balance = try cells[.balance].map { try MoneyAmount.minorUnits(from: $0, currency: request.currency) }
        let occurrence = nextOccurrence(for: [
            date, time ?? "", "\(amountMinor)", instrumentID,
            ContentHash.normalizedDescription(description), balance.map { "\($0)" } ?? "",
        ].joined(separator: "|"))
        let hash = ContentHash.transactionHash(
            date: date,
            time: time,
            amountMinor: amountMinor,
            currency: request.currency,
            instrumentID: instrumentID,
            description: description,
            balanceAfterMinor: balance,
            occurrence: occurrence
        )
        return MoneyTransaction(
            stamp: .init(date: date, time: time),
            amount: .init(amountMinor: amountMinor, currency: request.currency, balanceAfterMinor: balance),
            parties: .init(accountID: request.accountID, cardID: request.cardID, businessID: request.businessID),
            narrative: .init(description: description, category: cells[.category], memo: cells[.memo]),
            importBatchID: batchID,
            contentHash: hash
        )
    }

    /// amount 단일 컬럼 또는 in/out 쌍 — 매핑 파서가 둘 중 하나만 허용했다.
    private func amount(_ cells: CSVRowCells) throws -> Int64 {
        if let rawAmount = cells[.amount] {
            return try MoneyAmount.minorUnits(from: rawAmount, currency: request.currency)
        }
        let inflow = try cells[.inflow].map { try MoneyAmount.minorUnits(from: $0, currency: request.currency) } ?? 0
        let outflow = try cells[.outflow].map { try MoneyAmount.minorUnits(from: $0, currency: request.currency) } ?? 0
        guard inflow != 0 || outflow != 0 else { throw CSVImportError.rowMissing("in/out") }
        return inflow - abs(outflow)
    }

    private mutating func nextOccurrence(for key: String) -> Int {
        let occurrence = (occurrenceByKey[key] ?? 0) + 1
        occurrenceByKey[key] = occurrence
        return occurrence
    }
}

/// 한 행의 셀 접근 — 매핑된 컬럼만, 공백 정리, 빈 값은 nil.
struct CSVRowCells {
    let row: [String]
    let columns: [ColumnMapping.Key: Int]

    subscript(key: ColumnMapping.Key) -> String? {
        guard let index = columns[key], index < row.count else { return nil }
        let value = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

public enum CSVImportError: Error, Equatable, CustomStringConvertible {
    case badMapping(String)
    case missingMappingKey(String)
    case conflictingAmount
    case columnNotFound(String, String, [String])
    case columnOutOfRange(String, String, Int)
    case instrumentRequired
    case emptyFile
    case rowMissing(String)

    public var description: String {
        switch self {
        case let .badMapping(pair): "매핑 형식 오류: \(pair) (key=value)"
        case let .missingMappingKey(key): "매핑에 \(key) 가 필요합니다"
        case .conflictingAmount: "amount 와 in/out 은 같이 쓸 수 없습니다"
        case let .columnNotFound(key, ref, header):
            "\(key)=\(ref) 컬럼을 헤더에서 찾지 못했습니다 — 헤더: \(header.joined(separator: " | "))"
        case let .columnOutOfRange(key, ref, count): "\(key)=\(ref) 는 컬럼 수(\(count))를 벗어납니다"
        case .instrumentRequired: "--account 또는 --card 중 정확히 하나를 지정하세요"
        case .emptyFile: "CSV 에 데이터 행이 없습니다"
        case let .rowMissing(field): "행에 \(field) 값이 없습니다"
        }
    }
}
