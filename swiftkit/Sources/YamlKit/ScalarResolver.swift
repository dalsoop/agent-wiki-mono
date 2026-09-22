import Foundation

/// plain 스칼라 원문을 Swift 값으로 해석한다.
/// - 따옴표 스칼라는 항상 문자열(호출처가 `.scalar(raw:, plain: false)`로 넘긴다).
/// - plain 스칼라만 null/불/정수/실수로 해석한다.
enum ScalarResolver {
    static func resolve(raw: String, plain: Bool) -> Any? {
        if !plain {
            // 따옴표 스칼라 — 원문 그대로 문자열. 단 null 키워드는 문자열로 둔다(사용처 없음).
            return raw
        }
        // plain 스칼라. 빈 문자열·null 키워드 → null.
        switch raw {
        case "", "~", "null", "Null", "NULL":
            return NSNull()
        case "true", "True", "TRUE":
            return true
        case "false", "False", "FALSE":
            return false
        default:
            break
        }
        if let intValue = parseInteger(raw) {
            return intValue
        }
        if let doubleValue = parseDouble(raw) {
            return doubleValue
        }
        return raw
    }

    /// 10진 정수(부호 허용). Int 범위를 벗어나면 nil(문자열로 유지).
    private static func parseInteger(_ raw: String) -> Int? {
        let trimmed: String
        if raw.hasPrefix("+") {
            trimmed = String(raw.dropFirst())
        } else {
            trimmed = raw
        }
        guard !trimmed.isEmpty else { return nil }
        // 0x / 0o / 0b — 사용처 밖이지만 정규 해석.
        if trimmed.hasPrefix("0x"), let v = UInt64(trimmed.dropFirst(2), radix: 16) {
            return Int(exactly: v)
        }
        if trimmed.hasPrefix("0o"), let v = UInt64(trimmed.dropFirst(2), radix: 8) {
            return Int(exactly: v)
        }
        if trimmed.hasPrefix("0b"), let v = UInt64(trimmed.dropFirst(2), radix: 2) {
            return Int(exactly: v)
        }
        guard trimmed.allSatisfy({ $0.isASCII && $0.isNumber || $0 == "-" }), !trimmed.allSatisfy({ $0 == "-" }) else {
            return nil
        }
        return Int(trimmed)
    }

    /// 10진 실수(소수점/지수). 정수형은 여기에 오지 않는다(parseInteger 선행).
    private static func parseDouble(_ raw: String) -> Double? {
        switch raw {
        case ".inf", ".Inf", ".INF", "+.inf":
            return Double.infinity
        case "-.inf", "-.Inf", "-.INF":
            return -Double.infinity
        case ".nan", ".NaN", ".NAN":
            return Double.nan
        default:
            break
        }
        guard raw.contains(".") || raw.contains("e") || raw.contains("E") else { return nil }
        // 숫자/지수 형태인지 확인 — 날짜(`2026-07-10T...`)가 섞이지 않게.
        guard isNumericScalar(raw) else { return nil }
        return Double(raw)
    }

    /// 정수/실수 토큰으로 보이는지(부호·숫자·`.`·지수 `e`/`E` `-` `+` 만으로 구성).
    private static func isNumericScalar(_ raw: String) -> Bool {
        guard let first = raw.first, first == "-" || first == "+" || first.isNumber || first == "." else {
            return false
        }
        return raw.allSatisfy { ch in
            ch.isASCII && (ch.isNumber || ch == "." || ch == "-" || ch == "+" || ch == "e" || ch == "E")
        }
    }
}

/// 실수 직렬화 — round-trip 안정적이고 정수와 구분되는(소수점/지수 포함) 문자열.
enum NumberFormatter {
    static let scalar = ScalarNumberFormatter()
}

struct ScalarNumberFormatter {
    func doubleString(_ value: Double) -> String {
        if value.isNaN { return ".nan" }
        if value.isInfinite { return value > 0 ? ".inf" : "-.inf" }
        let text = value.description
        // Swift `description`은 대부분 최단 round-trip 표현을 낸다.
        if text.contains(".") || text.contains("e") || text.contains("E") {
            return text
        }
        return text + ".0"
    }
}
