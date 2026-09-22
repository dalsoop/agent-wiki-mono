import Foundation
import MoneyLedgerModels

/// 성실신고확인대상 판정(소득세법 제70조의2, 시행령 제133조) — **해당 과세기간** 수입금액을 업종 그룹
/// 기준과 비교한다(간편장부 판정의 '직전연도' 와 다르다). 대상자는 종합소득세 기한이 6/30 으로 늘고
/// 세무대리인의 성실신고확인서가 필요하다. 기준은 `Resources/sincere-reporting-thresholds.json`.
public enum SincereReportingObligation {
    public static let resourceName = "sincere-reporting-thresholds"

    public struct Judgement: Codable, Sendable, Equatable {
        public let isSubject: Bool
        public let basisYear: Int
        public let thresholdMinor: Int64
        public let confidence: RuleConfidence
        public let note: String
    }

    public static func judge(year: Int, industryGroup: IndustryGroup, revenueMinor: Int64) throws -> Judgement {
        let table = try RevenueThresholdTable.loadBundled(resource: resourceName)
        let resolved = try table.entry(year: year, group: industryGroup, resource: resourceName)
        let entry = resolved.entry
        return Judgement(
            isSubject: revenueMinor >= entry.thresholdMinor,
            basisYear: resolved.basisYear,
            thresholdMinor: entry.thresholdMinor,
            confidence: entry.confidence,
            note: "해당 과세기간 수입금액 \(MoneyAmount.format(minor: revenueMinor, currency: "KRW")) vs 기준 "
                + "\(MoneyAmount.format(minor: entry.thresholdMinor, currency: "KRW")) (\(resolved.basisYear)년 표). " + entry.note
        )
    }
}
