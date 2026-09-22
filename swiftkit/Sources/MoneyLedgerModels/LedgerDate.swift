import Foundation

/// 원장 날짜 공통기 — "yyyy-MM-dd" 문자열이 정본(사전순=날짜순, 시간대 함정 없음).
/// Date 로 나가는 건 달력 연산(다음 결제일 굴리기·D-day)뿐이다.
public enum LedgerDate {
    /// 은행 CSV 에서 흔한 표기들 → "yyyy-MM-dd". "2026.08.04", "2026/8/4", "26-08-04",
    /// "2026-08-04 13:22:01"(시각 붙은 형식)도 받는다. 시각은 별도로 떼어 반환.
    public static func normalize(_ raw: String) throws -> (date: String, time: String?) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LedgerDateError.unparsable(raw) }
        let parts = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
        let datePart = parts[0]
        let timePart = parts.count > 1 ? normalizeTime(parts[1]) : nil

        let separators = CharacterSet(charactersIn: "-./")
        let components = datePart.components(separatedBy: separators)
        guard components.count == 3,
              let rawYear = Int(components[0]),
              let month = Int(components[1]),
              let day = Int(components[2]),
              (1...12).contains(month),
              (1...31).contains(day) else {
            throw LedgerDateError.unparsable(raw)
        }
        let year = rawYear < 100 ? rawYear + 2000 : rawYear
        guard (1900...2200).contains(year) else { throw LedgerDateError.unparsable(raw) }
        return (String(format: "%04d-%02d-%02d", year, month, day), timePart)
    }

    /// "13:22" · "13:22:01" · "132201" → "HH:mm:ss". 해석 불가면 nil(시각은 보조 정보).
    public static func normalizeTime(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let digits = trimmed.replacingOccurrences(of: ":", with: "")
        guard digits.allSatisfy(\.isNumber) else { return nil }
        let padded: String
        switch digits.count {
        case 4: padded = digits + "00"
        case 6: padded = digits
        default: return nil
        }
        let hour = Int(padded.prefix(2)) ?? 99
        let minute = Int(padded.dropFirst(2).prefix(2)) ?? 99
        let second = Int(padded.dropFirst(4)) ?? 99
        guard hour < 24, minute < 60, second < 60 else { return nil }
        return String(format: "%02d:%02d:%02d", hour, minute, second)
    }

    public static func isValid(_ date: String) -> Bool {
        (try? normalize(date)) != nil && date.count == 10
    }

    /// 오늘 "yyyy-MM-dd" (로컬 달력).
    public static func today(now: Date = .now, calendar: Calendar = .current) -> String {
        format(now, calendar: calendar)
    }

    public static func format(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public static func toDate(_ date: String, calendar: Calendar = .current) -> Date? {
        let separators = CharacterSet(charactersIn: "-")
        let components = date.components(separatedBy: separators)
        guard components.count == 3,
              let year = Int(components[0]), let month = Int(components[1]), let day = Int(components[2]) else {
            return nil
        }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    /// 결제 주기만큼 앞으로. oneTime/unknown 은 굴리지 않는다(nil).
    public static func advance(_ date: String, by period: BillingPeriod, calendar: Calendar = .current) -> String? {
        guard let base = toDate(date, calendar: calendar) else { return nil }
        let next: Date?
        switch period {
        case .monthly: next = calendar.date(byAdding: .month, value: 1, to: base)
        case .yearly: next = calendar.date(byAdding: .year, value: 1, to: base)
        case .oneTime, .unknown: next = nil
        }
        return next.map { format($0, calendar: calendar) }
    }

    /// "yyyy-MM" 의 시작·끝 날짜 ("yyyy-MM-01", "yyyy-MM-31" 사전순 비교용 상한).
    public static func monthRange(_ month: String) throws -> (from: String, to: String) {
        let parts = month.components(separatedBy: "-")
        guard parts.count == 2, let year = Int(parts[0]), let m = Int(parts[1]), (1...12).contains(m) else {
            throw LedgerDateError.unparsable(month)
        }
        return (String(format: "%04d-%02d-01", year, m), String(format: "%04d-%02d-99", year, m))
    }
}

public enum LedgerDateError: Error, Equatable, CustomStringConvertible {
    case unparsable(String)

    public var description: String {
        switch self {
        case let .unparsable(raw): "날짜를 해석할 수 없습니다: \(raw) (yyyy-MM-dd)"
        }
    }
}
