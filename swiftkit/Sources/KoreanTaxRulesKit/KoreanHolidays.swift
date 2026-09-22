import Foundation
import MoneyLedgerModels

/// 한국 공휴일 표 + 국세기본법 제5조 기한 특례(토요일·일요일·공휴일·근로자의 날이면 다음 날).
/// 날짜는 `Resources/korean-holidays.json`(연도 키, 출처 note 포함). 표에 없는 연도는 주말만 이월하고
/// `holidayTableCovered = false` 로 표시해 소비 앱이 검토 필요로 드러내게 한다.
public struct KoreanHolidays: Sendable {
    public static let resourceName = "korean-holidays"

    public enum Kind: String, Codable, Sendable, CaseIterable {
        case publicHoliday
        case substitute
        case election
        /// 관공서 공휴일은 아니지만 국세기본법 제5조가 기한 이월 대상으로 명시한 근로자의 날.
        case laborDay
        case temporary

        public func label(korean: Bool) -> String {
            switch self {
            case .publicHoliday: korean ? "공휴일" : "Public holiday"
            case .substitute: korean ? "대체공휴일" : "Substitute holiday"
            case .election: korean ? "선거일" : "Election day"
            case .laborDay: korean ? "근로자의 날(기한 특례)" : "Labor Day (deadline extension)"
            case .temporary: korean ? "임시공휴일" : "Temporary holiday"
            }
        }
    }

    public struct Entry: Codable, Sendable, Equatable {
        public let date: String
        public let name: String
        public let kind: Kind
        public let confidence: RuleConfidence
        public let note: String?

        public init(date: String, name: String, kind: Kind, confidence: RuleConfidence, note: String? = nil) {
            self.date = date
            self.name = name
            self.kind = kind
            self.confidence = confidence
            self.note = note
        }
    }

    public struct Rollover: Sendable, Equatable {
        public let date: String
        public let rolled: Bool
        /// 이월 경로의 모든 연도가 공휴일 표에 있었는가. false 면 주말만 반영된 것.
        public let holidayTableCovered: Bool
        /// 이월을 일으킨 이유(주말·공휴일 이름) — 사람이 읽는 메모.
        public let reasons: [String]
    }

    public let source: String
    public let entries: [Entry]
    public let coveredYears: Set<Int>

    public init(source: String, entries: [Entry], coveredYears: Set<Int>) {
        self.source = source
        self.entries = entries.sorted { $0.date < $1.date }
        self.coveredYears = coveredYears
    }

    public static func loadBundled() throws -> KoreanHolidays {
        try TaxRuleResource.load(Document.self, resource: resourceName).holidays
    }

    public func covers(year: Int) -> Bool { coveredYears.contains(year) }

    public func holiday(on date: String) -> Entry? {
        entries.first { $0.date == date }
    }

    public func isWeekend(_ date: String) -> Bool {
        guard let day = LedgerDate.toDate(date, calendar: Self.calendar) else { return false }
        let weekday = Self.calendar.component(.weekday, from: day)
        return weekday == 1 || weekday == 7
    }

    /// 토·일·공휴일·근로자의 날이 아니면 영업일.
    public func isBusinessDay(_ date: String) -> Bool {
        !isWeekend(date) && holiday(on: date) == nil
    }

    /// 국세기본법 제5조 이월 — 영업일이 될 때까지 하루씩 민다. 날짜 해석 불가면 nil.
    public func rollover(from date: String) -> Rollover? {
        guard var cursor = LedgerDate.toDate(date, calendar: Self.calendar) else { return nil }
        var current = date
        var reasons: [String] = []
        var covered = true
        var guardCount = 0
        while !isBusinessDay(current), guardCount < 60 {
            reasons.append(holiday(on: current)?.name ?? "주말")
            covered = covered && covers(year: Self.year(of: current))
            guard let next = Self.calendar.date(byAdding: .day, value: 1, to: cursor) else { return nil }
            cursor = next
            current = LedgerDate.format(next, calendar: Self.calendar)
            guardCount += 1
        }
        covered = covered && covers(year: Self.year(of: current))
        return Rollover(date: current, rolled: current != date, holidayTableCovered: covered, reasons: reasons)
    }

    static func year(of date: String) -> Int {
        Int(date.prefix(4)) ?? 0
    }

    /// 요일 계산은 한국 시간대 그레고리력으로 고정 — 로컬 달력·시간대에 흔들리지 않는다.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        return calendar
    }()

    struct Document: Decodable {
        struct Year: Decodable {
            let notes: [String]?
            let entries: [Entry]
        }

        let source: String
        let years: YearKeyed<Year>

        var holidays: KoreanHolidays {
            KoreanHolidays(
                source: source,
                entries: years.byYear.values.flatMap(\.entries),
                coveredYears: Set(years.byYear.keys)
            )
        }
    }
}
