import Foundation

/// 금액 최소단위 변환·표기 공통기. 저장은 항상 Int64 최소단위, 파싱은 Decimal 경유
/// (Double 은 0.1+0.2 문제로 원장에 못 들어온다).
public enum MoneyAmount {
    /// 통화별 소수 자릿수. 원장에서 실제로 쓰는 통화만 명시하고 나머지는 ISO 관례(2).
    public static func exponent(of currency: String) -> Int {
        switch normalizedCurrency(currency) {
        case "KRW", "JPY", "VND": 0
        default: 2
        }
    }

    public static func normalizedCurrency(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if trimmed == "원" || trimmed.isEmpty { return "KRW" }
        return trimmed
    }

    /// "15000" · "15,000" · "-15.99" · "₩1,500,000" → 최소단위.
    /// 은행 CSV 숫자(콤마 그룹핑·통화기호·공백)를 그대로 받는다.
    public static func minorUnits(from raw: String, currency: String) throws -> Int64 {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(of: ",", with: "")
        text = text.replacingOccurrences(of: "₩", with: "")
        text = text.replacingOccurrences(of: "$", with: "")
        text = text.replacingOccurrences(of: " ", with: "")
        // 회계 표기 (1,500) = -1500
        if text.hasPrefix("("), text.hasSuffix(")") {
            text = "-" + text.dropFirst().dropLast()
        }
        guard !text.isEmpty else { throw MoneyAmountError.unparsable(raw) }
        guard let decimal = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
            throw MoneyAmountError.unparsable(raw)
        }
        let scaled = decimal * pow(Decimal(10), exponent(of: currency))
        var rounded = Decimal()
        var mutable = scaled
        NSDecimalRound(&rounded, &mutable, 0, .plain)
        guard rounded == scaled else { throw MoneyAmountError.tooManyFractionDigits(raw) }
        guard let value = Int64(exactly: NSDecimalNumber(decimal: rounded).int64Value),
              NSDecimalNumber(decimal: rounded).stringValue == "\(value)" else {
            throw MoneyAmountError.unparsable(raw)
        }
        return value
    }

    /// 최소단위 → 사람 표기. KRW ₩-15,000 / USD $15.99 / 기타 "CUR 12.34".
    public static func format(minor: Int64, currency: String) -> String {
        let cur = normalizedCurrency(currency)
        let exp = exponent(of: cur)
        let sign = minor < 0 ? "-" : ""
        let magnitude = minor.magnitude
        let grouped: (UInt64) -> String = { value in
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.groupingSeparator = ","
            return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        }
        if exp == 0 {
            let symbol = cur == "KRW" ? "₩" : "\(cur) "
            return "\(sign)\(symbol)\(grouped(magnitude))"
        }
        let divisor = UInt64(pow(10.0, Double(exp)))
        let whole = magnitude / divisor
        let fraction = magnitude % divisor
        let fractionText = String(format: "%0\(exp)llu", fraction)
        let symbol = cur == "USD" ? "$" : "\(cur) "
        return "\(sign)\(symbol)\(grouped(whole)).\(fractionText)"
    }

    /// 리포트 전용 — 최소단위를 주단위 Double 로 (월환산 등 파생값에만 쓴다).
    public static func majorUnits(minor: Int64, currency: String) -> Double {
        Double(minor) / pow(10.0, Double(exponent(of: currency)))
    }
}

public enum MoneyAmountError: Error, Equatable, CustomStringConvertible {
    case unparsable(String)
    case tooManyFractionDigits(String)

    public var description: String {
        switch self {
        case let .unparsable(raw): "금액을 해석할 수 없습니다: \(raw)"
        case let .tooManyFractionDigits(raw): "통화 소수 자릿수를 초과합니다: \(raw)"
        }
    }
}
