import Foundation

/// 신청 · 접수 기간. 한국 공고 날짜 표기 변종을 단일 모델로 정규화한다.
/// 원천별로 표기가 제각각("20250810~20250910", "2025.08.10. ~ 09.10.", "접수기간: ...")이라
/// 파싱은 관대하게, 실패해도 rawText 를 보존한다.
public struct ApplicationPeriod: Codable, Sendable, Equatable {
    public let start: Date?
    public let end: Date?
    public let rawText: String

    public init(start: Date?, end: Date?, rawText: String) {
        self.start = start
        self.end = end
        self.rawText = rawText
    }

    /// date 가 접수 기간 내인가. end 미정이면 **상시/무기한**으로 간주해 항상 true.
    /// (대출·보조금·조세 카탈로그 같은 상시 모집 상품. 시작일만 모르면 마감일 이전까지 true.)
    public func contains(_ date: Date, calendar: Calendar = ApplicationPeriod.gregorian) -> Bool {
        let day = calendar.startOfDay(for: date)
        guard let end else { return true }
        if let start {
            return day >= calendar.startOfDay(for: start) && day <= calendar.startOfDay(for: end)
        }
        return day <= calendar.startOfDay(for: end)
    }

    /// 오늘 접수 중인가.
    public func isAcceptingNow(now: Date = Date()) -> Bool {
        contains(now)
    }

    /// 마감까지 남은 일 수. end 미확정 → nil. 이미 마감 → -1.
    public func daysUntilClose(now: Date = Date(), calendar: Calendar = ApplicationPeriod.gregorian) -> Int? {
        guard let end else { return nil }
        let delta = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: end))
        guard let day = delta.day else { return nil }
        return day >= 0 ? day : -1
    }

    public static let gregorian: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        return c
    }()

    /// 한국 날짜 범위 문자열을 파싱.
    /// 지원 포맷: "20250810~20250910", "2025.08.10~2025.09.10", "2025-08-10 ~ 2025-09-10",
    /// "2025년 08월 10일 ~ 09월 10일"(끝쪽 연도 생략 시 시작 연도 승계), "접수기간 : 2025.08.10.~".
    /// 전체 날짜(yyyy..dd) 토큰을 순서대로 추출해 앞두 개를 start/end 로 삼고,
    /// 끝이 월·일만 있으면 시작 연도를 승계한다. 파싱 불가 시 nil.
    public static func parse(_ text: String) -> ApplicationPeriod {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ApplicationPeriod(start: nil, end: nil, rawText: text)
        }

        // 전체 날짜 토큰(연-월-일). 구분자: . - / _ 년월일 공백 섞임.
        let full = #/\d{4}[.\-/_년 ]\s*(\d{1,2})[.\-/_월 ]\s*(\d{1,2})/#
        // yyyymmdd 묶음(구분자 없음). \b 로 더 긴 숫자열의 일부가 되지 않게 한다.
        let compact = #/\b(\d{4})(\d{2})(\d{2})\b/#

        let cal = gregorian
        func dateFromYMD(_ y: Int, _ m: Int, _ d: Int) -> Date? {
            cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))
        }

        // 1) 전체 날짜 토큰(등장 순) 수집. 첫 토큰 직후 위치도 기억(끝쪽 월·일 승계용).
        var fullMatches: [(y: Int, m: Int, d: Int)] = []
        var firstFullUpperBound: String.Index?
        for m in trimmed.matches(of: full) {
            let whole = trimmed[m.range]
            guard let y = Int(whole.prefix(4)),
                  let mo = Int(m.output.1),
                  let da = Int(m.output.2) else { continue }
            fullMatches.append((y, mo, da))
            if firstFullUpperBound == nil { firstFullUpperBound = m.range.upperBound }
        }

        if fullMatches.count >= 2 {
            let a = fullMatches[0], b = fullMatches[1]
            return ApplicationPeriod(start: dateFromYMD(a.y, a.m, a.d), end: dateFromYMD(b.y, b.m, b.d), rawText: text)
        }

        if fullMatches.count == 1 {
            let a = fullMatches[0]
            // 끝쪽이 월·일만 있는지: 전체 토큰 이후에 등장하는 (월.일) 패턴
            let after = trimmed[(firstFullUpperBound ?? trimmed.endIndex)...]
            let md = #/(\d{1,2})[.\-/_월 ]\s*(\d{1,2})/#
            if let mdm = after.firstMatch(of: md),
               let mm = Int(mdm.output.1),
               let dd = Int(mdm.output.2) {
                return ApplicationPeriod(start: dateFromYMD(a.y, a.m, a.d), end: dateFromYMD(a.y, mm, dd), rawText: text)
            }
            return ApplicationPeriod(start: dateFromYMD(a.y, a.m, a.d), end: dateFromYMD(a.y, a.m, a.d), rawText: text)
        }

        // 2) yyyymmdd 묶음 처리
        var compactMatches: [(y: Int, m: Int, d: Int)] = []
        for m in trimmed.matches(of: compact) {
            guard let y = Int(m.output.1),
                  let mo = Int(m.output.2),
                  let da = Int(m.output.3) else { continue }
            compactMatches.append((y, mo, da))
        }
        if compactMatches.count >= 2 {
            return ApplicationPeriod(start: dateFromYMD(compactMatches[0].y, compactMatches[0].m, compactMatches[0].d),
                                     end: dateFromYMD(compactMatches[1].y, compactMatches[1].m, compactMatches[1].d),
                                     rawText: text)
        }
        if compactMatches.count == 1 {
            return ApplicationPeriod(start: dateFromYMD(compactMatches[0].y, compactMatches[0].m, compactMatches[0].d),
                                     end: dateFromYMD(compactMatches[0].y, compactMatches[0].m, compactMatches[0].d),
                                     rawText: text)
        }

        return ApplicationPeriod(start: nil, end: nil, rawText: text)
    }
}
