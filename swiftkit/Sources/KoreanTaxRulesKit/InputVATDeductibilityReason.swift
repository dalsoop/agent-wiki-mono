import Foundation

extension InputVATDeductibility {
    /// 불공제·검토 필요 사유. raw 값이 앱 간 교환 문자열이다.
    public enum Reason: String, Codable, Sendable, CaseIterable {
        case entertainmentExpense
        case nonBusinessUse
        case nonBusinessPassengerVehicle
        case taxExemptBusinessUse
        case foreignSupplierNoKoreanVAT
        case taxExemptSupplier
        case nonBusinessSeller
        case inadequateEvidence
        case simplifiedTaxpayerCardSlip
        case simplifiedTaxpayerInvoiceEligibility
        case unknownCounterparty
        case estimatedSplitNeedsEvidence
        case salesEvidenceOnPurchase

        public func label(korean: Bool) -> String {
            switch self {
            case .entertainmentExpense:
                korean ? "접대비(기업업무추진비) 관련 매입세액은 불공제" : "Entertainment expense input VAT is non-deductible"
            case .nonBusinessUse:
                korean ? "사업과 관련 없는 지출" : "Not related to the business"
            case .nonBusinessPassengerVehicle:
                korean ? "비영업용 소형승용차 구입·임차·유지" : "Non-business passenger vehicle purchase, lease, or upkeep"
            case .taxExemptBusinessUse:
                korean ? "면세사업 관련 매입" : "Purchase related to a VAT-exempt business line"
            case .foreignSupplierNoKoreanVAT:
                korean ? "해외 사업자 — 국내 부가세가 과세되지 않아 공제할 세액 없음" : "Foreign supplier — no Korean VAT charged"
            case .taxExemptSupplier:
                korean ? "면세사업자 매입(계산서) — 세액 없음" : "Purchase from a VAT-exempt supplier (no VAT)"
            case .nonBusinessSeller:
                korean ? "비사업자 상대 거래 — 세액 없음" : "Seller is not a registered business (no VAT)"
            case .inadequateEvidence:
                korean ? "간이영수증은 적격증빙이 아님" : "Simple receipt is not qualified evidence"
            case .simplifiedTaxpayerCardSlip:
                korean ? "간이과세자 상대 카드매출전표 — 세금계산서 발급 가능 간이과세자인지 확인" : "Card slip from a simplified taxpayer — verify invoice eligibility"
            case .simplifiedTaxpayerInvoiceEligibility:
                korean ? "간이과세자가 발급한 세금계산서 — 발급 가능 사업자인지 확인" : "Tax invoice issued by a simplified taxpayer — verify eligibility"
            case .unknownCounterparty:
                korean ? "상대 과세유형 미확인" : "Counterparty taxation type unknown"
            case .estimatedSplitNeedsEvidence:
                korean ? "추정 분리 — 실제 증빙(홈택스 사업용카드 자료·세금계산서) 필요" : "Estimated split — needs actual evidence"
            case .salesEvidenceOnPurchase:
                korean ? "수출(매출) 증빙이 매입 판정에 들어옴" : "Sales/export evidence supplied for a purchase"
            }
        }
    }
}
