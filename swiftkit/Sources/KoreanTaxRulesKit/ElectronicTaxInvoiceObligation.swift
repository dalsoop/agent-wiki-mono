import Foundation
import MoneyLedgerModels

/// 개인사업자 전자세금계산서 의무발급(부가가치세법 제32조 제2항, 시행령 제68조) — 직전연도 사업장별
/// 공급가액 합계(면세 포함)가 기준 이상이면 **다음 해 7/1 부터 그 다음 해 6/30 까지** 의무.
/// 기준은 `Resources/electronic-tax-invoice-thresholds.json` 의 시행일별 항목.
public enum ElectronicTaxInvoiceObligation {
    public static let resourceName = "electronic-tax-invoice-thresholds"

    public struct Judgement: Codable, Sendable, Equatable {
        public let isObligated: Bool
        /// 의무 기간 시작 "yyyy-07-01".
        public let obligationFrom: String
        /// 의무 기간 끝 "yyyy-06-30".
        public let obligationTo: String
        public let thresholdMinor: Int64
        public let thresholdEffectiveFrom: String
        public let confidence: RuleConfidence
        public let note: String
    }

    struct Table: Decodable, Sendable {
        struct Threshold: Decodable, Sendable {
            let effectiveFrom: String
            let thresholdMinor: Int64
            let confidence: RuleConfidence
            let note: String
        }

        let source: String
        let thresholds: [Threshold]

        /// 의무 기간 시작일에 시행 중인 기준(시행일 ≤ 시작일 중 최신).
        func threshold(effectiveOn date: String) -> Threshold? {
            thresholds.filter { $0.effectiveFrom <= date }.max { $0.effectiveFrom < $1.effectiveFrom }
        }
    }

    /// `priorYear` 의 공급가액으로 `priorYear + 1` 7/1 부터의 의무를 판정한다. 공급가액 nil(신규)은 의무 없음.
    public static func judge(priorYear: Int, priorYearSupplyMinor: Int64?) throws -> Judgement {
        let from = String(format: "%04d-07-01", priorYear + 1)
        let to = String(format: "%04d-06-30", priorYear + 2)
        let table = try TaxRuleResource.load(Table.self, resource: resourceName)
        guard let threshold = table.threshold(effectiveOn: from) else {
            throw TaxRuleResourceError.noRuleForYear(resource: resourceName, year: priorYear + 1)
        }
        guard let supply = priorYearSupplyMinor else {
            return Judgement(
                isObligated: false, obligationFrom: from, obligationTo: to,
                thresholdMinor: threshold.thresholdMinor, thresholdEffectiveFrom: threshold.effectiveFrom,
                confidence: threshold.confidence,
                note: "직전연도(\(priorYear)) 공급가액이 없다(신규 개업) — 의무 없음. 이미 의무발급 대상이었다면 계속 대상이니 확인. " + threshold.note
            )
        }
        return Judgement(
            isObligated: supply >= threshold.thresholdMinor, obligationFrom: from, obligationTo: to,
            thresholdMinor: threshold.thresholdMinor, thresholdEffectiveFrom: threshold.effectiveFrom,
            confidence: threshold.confidence,
            note: "직전연도(\(priorYear)) 공급가액 \(MoneyAmount.format(minor: supply, currency: "KRW")) vs 기준 "
                + "\(MoneyAmount.format(minor: threshold.thresholdMinor, currency: "KRW")). " + threshold.note
        )
    }
}
