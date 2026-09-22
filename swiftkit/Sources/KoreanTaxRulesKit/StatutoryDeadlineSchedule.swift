import Foundation
import MoneyLedgerModels

/// 법정 기한 한 건 — 공휴일 이월 전. `KoreanTaxCalendar` 가 이월을 얹어 `TaxDeadline` 으로 만든다.
struct StatutoryDeadline: Sendable, Equatable {
    let kind: TaxDeadlineKind
    let periodFrom: String
    let periodTo: String
    let statutoryDate: String
    let confidence: RuleConfidence
    let note: String
}

/// 과세연도 하나의 법정 기한 목록(개인 일반과세자). 개업일이 과세기간 안이면 기간 시작을 개업일로
/// 절단하고, 개업일이 기간 끝보다 늦으면 그 기한은 없다. 예정고지는 직전 과세기간이 있어야 생긴다.
struct StatutoryDeadlineSchedule: Sendable {
    let year: Int
    let taxpayer: Taxpayer
    /// 개업일 "yyyy-MM-dd". 모르면 `Self.openedBeforeAnyPeriod` 로 연중 개업 상태 취급.
    let openedOn: String
    let preliminaryNotice: (basisYear: Int, entry: VATPreliminaryNoticeRule.Entry)?

    static let openedBeforeAnyPeriod = "0000-00-00"

    func all() -> [StatutoryDeadline] {
        var result: [StatutoryDeadline] = []
        result.append(contentsOf: [vatPreliminaryNotice(first: true), vatFinal(first: true)].compactMap { $0 })
        result.append(contentsOf: [vatPreliminaryNotice(first: false), vatFinal(first: false)].compactMap { $0 })
        result.append(contentsOf: [incomeTax()].compactMap { $0 })
        result.append(contentsOf: withholding())
        return result
    }

    // MARK: 부가가치세

    func vatFinal(first: Bool) -> StatutoryDeadline? {
        let periodFrom = first ? Self.date(year, 1, 1) : Self.date(year, 7, 1)
        let periodTo = first ? Self.date(year, 6, 30) : Self.date(year, 12, 31)
        guard openedOn <= periodTo else { return nil }
        let truncated = openedOn > periodFrom
        return StatutoryDeadline(
            kind: first ? .vatFirstHalfFinal : .vatSecondHalfFinal,
            periodFrom: max(openedOn, periodFrom),
            periodTo: periodTo,
            statutoryDate: first ? Self.date(year, 7, 25) : Self.date(year + 1, 1, 25),
            confidence: .confirmed,
            note: "과세기간 종료 후 25일 이내 확정신고·납부(부가가치세법 제49조)."
                + (truncated ? " 개업 첫 과세기간은 개업일부터 과세기간 끝까지." : "")
        )
    }

    /// 직전 과세기간 납부세액의 50% 를 고지(부가가치세법 제48조 제3항). 직전 과세기간이 없으면 없다.
    func vatPreliminaryNotice(first: Bool) -> StatutoryDeadline? {
        let previousPeriodEnd = first ? Self.date(year - 1, 12, 31) : Self.date(year, 6, 30)
        guard openedOn <= previousPeriodEnd else { return nil }
        let baseNote = "직전 과세기간 납부세액의 50% 를 예정고지·납부(부가가치세법 제48조 제3항). 실제 고지 여부는 국세청 고지서로 확인."
        let (confidence, noticeNote): (RuleConfidence, String) = if let preliminaryNotice {
            (
                preliminaryNotice.entry.confidence.merged(with: .needsReview),
                " 고지세액 \(MoneyAmount.format(minor: preliminaryNotice.entry.minimumNoticeMinor, currency: "KRW")) 미만이면 생략"
                    + "(\(preliminaryNotice.basisYear)년 표). " + preliminaryNotice.entry.note
            )
        } else {
            (.needsReview, " 소액 생략 기준 표가 없다.")
        }
        return StatutoryDeadline(
            kind: first ? .vatFirstHalfPreliminaryNotice : .vatSecondHalfPreliminaryNotice,
            periodFrom: first ? Self.date(year, 1, 1) : Self.date(year, 7, 1),
            periodTo: first ? Self.date(year, 3, 31) : Self.date(year, 9, 30),
            statutoryDate: first ? Self.date(year, 4, 25) : Self.date(year, 10, 25),
            confidence: confidence,
            note: baseNote + noticeNote
        )
    }

    // MARK: 종합소득세

    func incomeTax() -> StatutoryDeadline? {
        let periodTo = Self.date(year, 12, 31)
        guard openedOn <= periodTo else { return nil }
        let sincere = taxpayer.isSincereReportingSubject
        return StatutoryDeadline(
            kind: sincere ? .sincereReportingIncomeTax : .comprehensiveIncomeTax,
            periodFrom: max(openedOn, Self.date(year, 1, 1)),
            periodTo: periodTo,
            statutoryDate: sincere ? Self.date(year + 1, 6, 30) : Self.date(year + 1, 5, 31),
            confidence: .confirmed,
            note: sincere
                ? "성실신고확인대상자는 다음 해 6월 30일까지(소득세법 제70조의2). 세무대리인 성실신고확인서 첨부."
                : "다음 해 5월 1일~31일 확정신고·납부(소득세법 제70조)."
        )
    }

    // MARK: 원천세

    func withholding() -> [StatutoryDeadline] {
        switch taxpayer.withholding {
        case .none: []
        case .monthly: (1...12).compactMap(withholdingMonthly)
        case .halfYearly: [withholdingHalfYearly(first: true), withholdingHalfYearly(first: false)].compactMap { $0 }
        }
    }

    func withholdingMonthly(month: Int) -> StatutoryDeadline? {
        let periodTo = Self.date(year, month, Self.lastDay(year: year, month: month))
        guard openedOn <= periodTo else { return nil }
        let statutory = month == 12 ? Self.date(year + 1, 1, 10) : Self.date(year, month + 1, 10)
        return StatutoryDeadline(
            kind: .withholdingTaxMonthly,
            periodFrom: max(openedOn, Self.date(year, month, 1)),
            periodTo: periodTo,
            statutoryDate: statutory,
            confidence: .confirmed,
            note: "지급일이 속하는 달의 다음 달 10일까지 신고·납부(소득세법 제128조). 지급 실적이 없으면 신고 대상 아님."
        )
    }

    func withholdingHalfYearly(first: Bool) -> StatutoryDeadline? {
        let periodTo = first ? Self.date(year, 6, 30) : Self.date(year, 12, 31)
        guard openedOn <= periodTo else { return nil }
        return StatutoryDeadline(
            kind: .withholdingTaxHalfYearly,
            periodFrom: max(openedOn, first ? Self.date(year, 1, 1) : Self.date(year, 7, 1)),
            periodTo: periodTo,
            statutoryDate: first ? Self.date(year, 7, 10) : Self.date(year + 1, 1, 10),
            confidence: .confirmed,
            note: "반기별 납부 승인 사업자(상시고용 20인 이하)는 반기 마지막 달의 다음 달 10일까지(소득세법 제128조 제2항)."
        )
    }

    // MARK: 날짜 helpers

    static func date(_ year: Int, _ month: Int, _ day: Int) -> String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func lastDay(year: Int, month: Int) -> Int {
        let calendar = KoreanHolidays.calendar
        let first = calendar.date(from: DateComponents(year: year, month: month, day: 1))
        return first.flatMap { calendar.range(of: .day, in: .month, for: $0)?.count } ?? 31
    }
}
