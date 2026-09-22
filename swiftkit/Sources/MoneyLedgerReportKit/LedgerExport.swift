import Foundation
import MoneyLedgerModels

/// 한국 엑셀 호환(UTF-8 BOM 인코딩) CSV 내보내기 엔진.
/// 컬럼: 일자, 유형, 계좌/카드, 가맹점/적요, 카테고리, 금액, 통화, 메모, 생성일시
public enum LedgerExport {
    private static let csvSpecialChars = CharacterSet(charactersIn: ",\"\n\r")

    public static func csv(
        transactions: [MoneyTransaction],
        accounts: [MoneyAccount] = [],
        cards: [MoneyCard] = []
    ) -> Data {
        let accountMap = Dictionary(accounts.map { ($0.id, "\($0.name)(\($0.bank))") }, uniquingKeysWith: { a, _ in a })
        let cardMap = Dictionary(cards.map { ($0.id, "\($0.name)(\($0.issuer))") }, uniquingKeysWith: { a, _ in a })

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var lines: [String] = []
        lines.append("일자,유형,계좌/카드,가맹점/적요,카테고리,금액,통화,메모,생성일시")

        for tx in transactions {
            let row = [
                escapeCSV(tx.date),
                escapeCSV(resolveKindStr(tx: tx)),
                escapeCSV(resolveInstrumentStr(tx: tx, accountMap: accountMap, cardMap: cardMap)),
                escapeCSV(tx.description),
                escapeCSV(tx.category ?? ""),
                escapeCSV(resolveAmountStr(tx: tx)),
                escapeCSV(tx.currency),
                escapeCSV(tx.memo ?? ""),
                escapeCSV(df.string(from: tx.createdAt))
            ].joined(separator: ",")
            lines.append(row)
        }

        let csvBody = lines.joined(separator: "\r\n") + "\r\n"
        var data = Data([0xEF, 0xBB, 0xBF]) // UTF-8 BOM
        data.append(Data(csvBody.utf8))
        return data
    }

    private static func resolveKindStr(tx: MoneyTransaction) -> String {
        guard let kind = tx.kind else {
            return tx.amountMinor >= 0 ? "수입" : "지출"
        }
        return kind.label(korean: true)
    }

    private static func resolveInstrumentStr(
        tx: MoneyTransaction,
        accountMap: [String: String],
        cardMap: [String: String]
    ) -> String {
        if let accID = tx.accountID, let name = accountMap[accID] {
            return name
        }
        if let cardID = tx.cardID, let name = cardMap[cardID] {
            return name
        }
        return tx.accountID ?? tx.cardID ?? ""
    }

    private static func resolveAmountStr(tx: MoneyTransaction) -> String {
        let exp = MoneyAmount.exponent(of: tx.currency)
        guard exp > 0 else {
            return "\(tx.amountMinor)"
        }
        return String(format: "%.\(exp)f", MoneyAmount.majorUnits(minor: tx.amountMinor, currency: tx.currency))
    }

    public static func csvString(
        transactions: [MoneyTransaction],
        accounts: [MoneyAccount] = [],
        cards: [MoneyCard] = []
    ) -> String {
        let data = csv(transactions: transactions, accounts: accounts, cards: cards)
        let bodyData = data.dropFirst(3)
        return String(data: bodyData, encoding: .utf8) ?? ""
    }

    private static func escapeCSV(_ text: String) -> String {
        guard text.rangeOfCharacter(from: csvSpecialChars) != nil else {
            return text
        }
        let escaped = text.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
