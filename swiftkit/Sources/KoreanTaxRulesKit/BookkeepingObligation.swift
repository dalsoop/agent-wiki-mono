import Foundation
import MoneyLedgerModels

/// 장부 기장 의무 — 간편장부 대상자인가, 복식부기 의무자인가(소득세법 시행령 제208조).
/// 신규 개업 첫해는 간편장부(전문직 제외), 그 뒤는 직전연도 수입금액을 업종 그룹 기준과 비교한다.
/// 그룹 기준 금액은 `Resources/bookkeeping-thresholds.json`(연도 키) 에 있고 값마다 confidence 가 붙는다.
public enum BookkeepingObligation {
    public static let resourceName = "bookkeeping-thresholds"

    public enum Kind: String, Codable, Sendable, CaseIterable {
        case simplifiedLedger
        case doubleEntry

        public func label(korean: Bool) -> String {
            switch self {
            case .simplifiedLedger: korean ? "간편장부 대상자" : "Simplified ledger"
            case .doubleEntry: korean ? "복식부기 의무자" : "Double-entry bookkeeping"
            }
        }
    }

    public struct Judgement: Codable, Sendable, Equatable {
        public let obligation: Kind
        /// 적용한 기준표 연도(요청 연도 이하 최근). 신규·전문직 판정은 요청 연도 그대로.
        public let basisYear: Int
        /// 비교에 쓴 기준 금액. 신규·전문직 판정은 nil.
        public let thresholdMinor: Int64?
        public let confidence: RuleConfidence
        public let note: String
    }

    public static func judge(
        year: Int,
        industryGroup: IndustryGroup,
        priorYearRevenueMinor: Int64?,
        isNewBusiness: Bool
    ) throws -> Judgement {
        if industryGroup == .professionalService {
            return Judgement(
                obligation: .doubleEntry, basisYear: year, thresholdMinor: nil, confidence: .confirmed,
                note: "전문직 사업자는 수입금액·신규 여부와 무관하게 복식부기 의무(소득세법 시행령 제208조 제5항 단서)"
            )
        }
        if isNewBusiness {
            return Judgement(
                obligation: .simplifiedLedger, basisYear: year, thresholdMinor: nil, confidence: .confirmed,
                note: "해당 과세기간에 신규로 사업을 개시한 사업자는 간편장부 대상자(소득세법 시행령 제208조 제5항 제1호)"
            )
        }
        let table = try RevenueThresholdTable.loadBundled(resource: resourceName)
        let resolved = try table.entry(year: year, group: industryGroup, resource: resourceName)
        return compare(priorYearRevenueMinor, against: resolved.entry, basisYear: resolved.basisYear)
    }

    static func compare(_ priorYearRevenueMinor: Int64?, against entry: ThresholdEntry, basisYear: Int) -> Judgement {
        guard let revenue = priorYearRevenueMinor else {
            return Judgement(
                obligation: .simplifiedLedger, basisYear: basisYear, thresholdMinor: entry.thresholdMinor,
                confidence: .needsReview,
                note: "직전연도 수입금액이 입력되지 않았다 — 신규 개업이 아니면 수입금액을 확인해 다시 판정. " + entry.note
            )
        }
        let obligation: Kind = revenue < entry.thresholdMinor ? .simplifiedLedger : .doubleEntry
        return Judgement(
            obligation: obligation, basisYear: basisYear, thresholdMinor: entry.thresholdMinor,
            confidence: entry.confidence,
            note: "직전연도 수입금액 \(MoneyAmount.format(minor: revenue, currency: "KRW")) vs 기준 "
                + "\(MoneyAmount.format(minor: entry.thresholdMinor, currency: "KRW")) (\(basisYear)년 표). " + entry.note
        )
    }
}
