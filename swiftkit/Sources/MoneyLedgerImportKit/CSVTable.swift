import Foundation
import MoneyLedgerStoreKit
import MoneyLedgerModels

/// RFC 4180 CSV 리더 + 한국 은행 CSV 인코딩 자동판별.
/// 은행 내려받기 파일은 UTF-8(BOM 유무)·CP949(EUC-KR) 가 섞여 온다 — 판별 순서:
/// UTF-8 BOM → UTF-8 strict → CP949. (CP949 판별 선례: pim-mail MimeBodyDecoder)
public struct CSVTable: Sendable, Equatable {
    public let rows: [[String]]
    /// 실제로 적용된 인코딩 이름("utf8" | "cp949") — ImportBatch 기록용.
    public let encodingName: String

    public init(rows: [[String]], encodingName: String) {
        self.rows = rows
        self.encodingName = encodingName
    }

    public enum SourceEncoding: String, Sendable, CaseIterable {
        case auto
        case utf8
        case cp949
    }

    public static func read(data: Data, encoding: SourceEncoding = .auto) throws -> CSVTable {
        let (text, name) = try decodeText(data: data, encoding: encoding)
        return CSVTable(rows: parse(text), encodingName: name)
    }

    public static func read(url: URL, encoding: SourceEncoding = .auto) throws -> CSVTable {
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch { throw CSVTableError.unreadableFile(url.path, String(describing: error)) }
        return try read(data: data, encoding: encoding)
    }

    static func decodeText(data: Data, encoding: SourceEncoding) throws -> (String, String) {
        let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
        let hasBOM = data.count >= 3 && Array(data.prefix(3)) == bom
        let body = hasBOM ? data.dropFirst(3) : data[...]

        func utf8() -> String? { String(data: Data(body), encoding: .utf8) }
        func cp949() -> String? {
            let cfEncoding = CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.EUC_KR.rawValue)
            )
            return String(data: Data(body), encoding: String.Encoding(rawValue: cfEncoding))
        }

        switch encoding {
        case .utf8:
            guard let text = utf8() else { throw CSVTableError.undecodable("utf8") }
            return (text, "utf8")
        case .cp949:
            guard let text = cp949() else { throw CSVTableError.undecodable("cp949") }
            return (text, "cp949")
        case .auto:
            if hasBOM, let text = utf8() { return (text, "utf8") }
            if let text = utf8() { return (text, "utf8") }
            if let text = cp949() { return (text, "cp949") }
            throw CSVTableError.undecodable("auto(utf8→cp949)")
        }
    }

    /// 따옴표 필드(내부 콤마·개행·"" 이스케이프) 지원 최소 파서. 빈 줄은 건너뛴다.
    public static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var field = ""
        var row: [String] = []
        var inQuotes = false
        var index = text.startIndex

        func endField() {
            row.append(field)
            field = ""
        }
        func endRow() {
            endField()
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
            row = []
        }

        while index < text.endIndex {
            let character = text[index]
            if inQuotes {
                if character == "\"" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")
                        index = next
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case "\"":
                    inQuotes = true
                case ",":
                    endField()
                case "\r":
                    break
                // Swift 는 "\r\n" 을 한 글자(grapheme cluster)로 본다 — 별도 케이스 필수.
                case "\n", "\r\n":
                    endRow()
                default:
                    field.append(character)
                }
            }
            index = text.index(after: index)
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }
}

public enum CSVTableError: Error, Equatable, CustomStringConvertible {
    case unreadableFile(String, String)
    case undecodable(String)

    public var description: String {
        switch self {
        case let .unreadableFile(path, reason): "CSV 파일을 읽을 수 없습니다: \(path) (\(reason))"
        case let .undecodable(encoding): "CSV 인코딩 해석 실패(\(encoding)) — --encoding cp949|utf8 로 지정해 보세요"
        }
    }
}
