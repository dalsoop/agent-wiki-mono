import Foundation
import MoneyLedgerModels

/// 신고·납부 기한 종류(개인 일반과세자 기준).
public enum TaxDeadlineKind: String, Codable, Sendable, CaseIterable {
    case vatFirstHalfFinal
    case vatSecondHalfFinal
    case vatFirstHalfPreliminaryNotice
    case vatSecondHalfPreliminaryNotice
    case comprehensiveIncomeTax
    case sincereReportingIncomeTax
    case withholdingTaxMonthly
    case withholdingTaxHalfYearly

    public var sortOrder: Int { Self.allCases.firstIndex(of: self) ?? Self.allCases.count }

    public func label(korean: Bool) -> String {
        switch self {
        case .vatFirstHalfFinal: korean ? "부가가치세 1기 확정신고·납부" : "VAT first-half final return"
        case .vatSecondHalfFinal: korean ? "부가가치세 2기 확정신고·납부" : "VAT second-half final return"
        case .vatFirstHalfPreliminaryNotice: korean ? "부가가치세 1기 예정고지 납부" : "VAT first-half preliminary notice payment"
        case .vatSecondHalfPreliminaryNotice: korean ? "부가가치세 2기 예정고지 납부" : "VAT second-half preliminary notice payment"
        case .comprehensiveIncomeTax: korean ? "종합소득세 확정신고·납부" : "Comprehensive income tax return"
        case .sincereReportingIncomeTax: korean ? "종합소득세 확정신고·납부(성실신고확인대상)" : "Income tax return (sincere reporting subject)"
        case .withholdingTaxMonthly: korean ? "원천세 신고·납부(매월)" : "Withholding tax (monthly)"
        case .withholdingTaxHalfYearly: korean ? "원천세 신고·납부(반기별)" : "Withholding tax (half-yearly)"
        }
    }
}

/// 기한 한 건. `statutoryDate` 는 법정 기한, `dueDate` 는 토·일·공휴일·근로자의 날 이월(국세기본법 제5조)
/// 을 반영한 실제 기한이다. 이월 근거·소액 생략 등 주의는 `note` 에, 확신도는 `confidence` 에.
public struct TaxDeadline: Codable, Sendable, Equatable {
    public let kind: TaxDeadlineKind
    /// 과세연도(귀속 연도). 기한은 다음 해에 떨어질 수 있다(2기 확정 1/25, 종소세 5/31).
    public let taxYear: Int
    public let periodFrom: String
    public let periodTo: String
    public let statutoryDate: String
    public let dueDate: String
    public let rolledOver: Bool
    public let confidence: RuleConfidence
    public let note: String

    public init(
        kind: TaxDeadlineKind,
        taxYear: Int,
        periodFrom: String,
        periodTo: String,
        statutoryDate: String,
        dueDate: String,
        rolledOver: Bool,
        confidence: RuleConfidence,
        note: String
    ) {
        self.kind = kind
        self.taxYear = taxYear
        self.periodFrom = periodFrom
        self.periodTo = periodTo
        self.statutoryDate = statutoryDate
        self.dueDate = dueDate
        self.rolledOver = rolledOver
        self.confidence = confidence
        self.note = note
    }
}

/// 납세자 속성 — 달력이 갈리는 것만 둔다. 과세유형은 개인 일반과세자로 고정(간이·법인은 이 Kit 범위 밖).
public struct Taxpayer: Codable, Sendable, Equatable {
    public enum Withholding: String, Codable, Sendable, CaseIterable {
        case none
        case monthly
        /// 반기별 납부 승인 사업자(상시고용 20인 이하) — 7/10, 익년 1/10.
        case halfYearly
    }

    public var isSincereReportingSubject: Bool
    public var withholding: Withholding

    public init(isSincereReportingSubject: Bool = false, withholding: Withholding = .none) {
        self.isSincereReportingSubject = isSincereReportingSubject
        self.withholding = withholding
    }
}
