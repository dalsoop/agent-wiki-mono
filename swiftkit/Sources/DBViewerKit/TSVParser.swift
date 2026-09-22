import Foundation

public enum TSVParserError: Error, Equatable, LocalizedError {
    case raggedRow(line: Int, expected: Int, actual: Int)

    public var errorDescription: String? {
        switch self {
        case let .raggedRow(line, expected, actual):
            "Line \(line) has \(actual) fields; expected \(expected)."
        }
    }
}

public enum TSVParser {
    public static func parse(_ text: String) throws -> QueryResult {
        let trimmed = text.trimmingTrailingNewlines()
        guard !trimmed.isEmpty else {
            return QueryResult(columns: [], rows: [])
        }

        let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingTrailingCarriageReturn() }
        guard let header = lines.first else {
            return QueryResult(columns: [], rows: [])
        }

        let columns = splitRow(header)
        let rows = try lines.dropFirst().enumerated().map { index, line in
            let fields = splitRow(line)
            guard fields.count == columns.count else {
                throw TSVParserError.raggedRow(line: index + 2, expected: columns.count, actual: fields.count)
            }
            return fields
        }

        return QueryResult(columns: columns, rows: rows)
    }

    private static func splitRow(_ row: String) -> [String] {
        row.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
    }
}

private extension String {
    func trimmingTrailingNewlines() -> String {
        var value = self
        while value.last == "\n" || value.last == "\r" {
            value.removeLast()
        }
        return value
    }

    func trimmingTrailingCarriageReturn() -> String {
        var value = self
        if value.last == "\r" {
            value.removeLast()
        }
        return value
    }
}

