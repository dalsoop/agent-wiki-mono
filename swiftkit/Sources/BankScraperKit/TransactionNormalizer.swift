import Foundation

public protocol TransactionParser: Sendable {
    func parse(content: String, accountNumber: String) throws -> [BankTransaction]
}

public struct CSVTransactionParser: TransactionParser {
    public init() {}

    public func parse(content: String, accountNumber: String) throws -> [BankTransaction] {
        var transactions: [BankTransaction] = []
        let lines = content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        
        let dateFormatter = ISO8601DateFormatter()
        
        for line in lines.dropFirst() {
            let columns = line.components(separatedBy: ",")
            if columns.count >= 6 {
                let timestampStr = columns[0].trimmingCharacters(in: .whitespaces)
                guard let timestamp = dateFormatter.date(from: timestampStr) else { continue }
                
                let deposit = Int64(columns[1].trimmingCharacters(in: .whitespaces)) ?? 0
                let withdrawal = Int64(columns[2].trimmingCharacters(in: .whitespaces)) ?? 0
                let balance = Int64(columns[3].trimmingCharacters(in: .whitespaces)) ?? 0
                let desc = columns[4].trimmingCharacters(in: .whitespaces)
                let type = columns[5].trimmingCharacters(in: .whitespaces)
                
                let transaction = BankTransaction(
                    timestamp: timestamp,
                    depositAmount: deposit,
                    withdrawalAmount: withdrawal,
                    balanceAfterTransaction: balance,
                    description: desc,
                    accountNumber: accountNumber,
                    transactionType: type
                )
                transactions.append(transaction)
            }
        }
        
        return transactions
    }
}

public struct TransactionNormalizer: Sendable {
    public init() {}
    
    public func normalize(content: String, format: String, accountNumber: String) throws -> [BankTransaction] {
        let parser: TransactionParser
        switch format.lowercased() {
        case "csv":
            parser = CSVTransactionParser()
        default:
            throw NSError(domain: "BankScraperKit", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unsupported format"])
        }
        
        return try parser.parse(content: content, accountNumber: accountNumber)
    }
}
