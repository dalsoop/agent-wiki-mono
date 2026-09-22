import Foundation
import MoneyLedgerModels

/// 신고·납부 기한 달력(개인 일반과세자). 법정 기한은 `StatutoryDeadlineSchedule`, 이월은 `KoreanHolidays`.
/// `year` 는 **과세연도(귀속)** 다 — 2기 확정 1/25·종소세 5/31 처럼 다음 해에 떨어지는 기한도 그 과세연도 목록에 든다.
public struct KoreanTaxCalendar: Sendable {
    public let holidays: KoreanHolidays
    public let preliminaryNotice: VATPreliminaryNoticeRule

    public init(holidays: KoreanHolidays, preliminaryNotice: VATPreliminaryNoticeRule) {
        self.holidays = holidays
        self.preliminaryNotice = preliminaryNotice
    }

    public static func loadBundled() throws -> KoreanTaxCalendar {
        KoreanTaxCalendar(holidays: try KoreanHolidays.loadBundled(), preliminaryNotice: try VATPreliminaryNoticeRule.loadBundled())
    }

    /// - openedOn: 개업일 "yyyy-MM-dd". nil 이면 과세연도 내내 사업 중으로 본다. 과세연도 뒤 개업이면 빈 목록.
    public func deadlines(year: Int, taxpayer: Taxpayer = Taxpayer(), openedOn: String? = nil) throws -> [TaxDeadline] {
        let opened = try Self.validatedOpening(openedOn)
        let schedule = StatutoryDeadlineSchedule(
            year: year,
            taxpayer: taxpayer,
            openedOn: opened,
            preliminaryNotice: preliminaryNotice.entry(for: year)
        )
        return schedule.all()
            .map { finalize($0, taxYear: year) }
            .sorted { lhs, rhs in
                lhs.dueDate != rhs.dueDate ? lhs.dueDate < rhs.dueDate : lhs.kind.sortOrder < rhs.kind.sortOrder
            }
    }

    /// 공휴일 이월을 얹는다. 표에 없는 연도를 지나면 주말만 반영한 것이라 검토 필요로 낮춘다.
    func finalize(_ statutory: StatutoryDeadline, taxYear: Int) -> TaxDeadline {
        let rollover = holidays.rollover(from: statutory.statutoryDate)
        let dueDate = rollover?.date ?? statutory.statutoryDate
        let rolled = rollover?.rolled ?? false
        let covered = rollover?.holidayTableCovered ?? false
        var note = statutory.note
        if rolled {
            let reasons = (rollover?.reasons ?? []).joined(separator: "·")
            note += " 법정 기한 \(statutory.statutoryDate) 이 \(reasons) 이라 \(dueDate) 로 이월(국세기본법 제5조)."
        }
        if !covered {
            note += " 공휴일 표에 \(KoreanHolidays.year(of: dueDate))년이 없어 주말만 이월했다 — 공휴일 표 갱신 후 재확인."
        }
        return TaxDeadline(
            kind: statutory.kind,
            taxYear: taxYear,
            periodFrom: statutory.periodFrom,
            periodTo: statutory.periodTo,
            statutoryDate: statutory.statutoryDate,
            dueDate: dueDate,
            rolledOver: rolled,
            confidence: covered ? statutory.confidence : .needsReview,
            note: note
        )
    }

    /// "2026.05.06"·"2026/5/6" 같은 표기도 받되 **정규화한 "yyyy-MM-dd"** 로 바꾼다 — 기간 비교가 사전순이라
    /// 구분자가 다르면 조용히 틀린다(실측: "2026/05/06" 이 모든 과세기간 뒤로 밀려 빈 목록이 나왔다).
    static func validatedOpening(_ openedOn: String?) throws -> String {
        guard let openedOn else { return StatutoryDeadlineSchedule.openedBeforeAnyPeriod }
        do {
            return try LedgerDate.normalize(openedOn).date
        } catch {
            throw KoreanTaxCalendarError.invalidOpeningDate(openedOn)
        }
    }
}

public enum KoreanTaxCalendarError: Error, Equatable, CustomStringConvertible {
    case invalidOpeningDate(String)

    public var description: String {
        switch self {
        case let .invalidOpeningDate(raw): "개업일을 해석할 수 없습니다: \(raw) (yyyy-MM-dd)"
        }
    }
}
