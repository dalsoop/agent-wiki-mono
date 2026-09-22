import Foundation

/// 증빙 종류. 적격증빙(세금계산서·전자세금계산서·지출증빙용 현금영수증·사업용카드)만 매입세액
/// 공제 후보다. `estimatedSplit` 은 증빙 없는 국내 카드 매입에 10/110 을 걸어둔 추정값 —
/// 증빙 원장 앱이 자동 생성하고, 실제 증빙이 붙기 전까지는 공제 판정이 검토 필요로 남는다.
public enum EvidenceKind: String, Codable, Sendable, CaseIterable {
    case taxInvoice
    case electronicTaxInvoice
    case cashReceiptExpense
    case businessCreditCard
    case simpleReceipt
    case foreignInvoice
    case exportEvidence
    case estimatedSplit

    /// 부가가치세법상 적격증빙인가(세금계산서·전자세금계산서·지출증빙 현금영수증·사업용카드).
    public var isQualified: Bool {
        switch self {
        case .taxInvoice, .electronicTaxInvoice, .cashReceiptExpense, .businessCreditCard: true
        case .simpleReceipt, .foreignInvoice, .exportEvidence, .estimatedSplit: false
        }
    }

    public func label(korean: Bool) -> String {
        switch self {
        case .taxInvoice: korean ? "세금계산서" : "Tax invoice"
        case .electronicTaxInvoice: korean ? "전자세금계산서" : "Electronic tax invoice"
        case .cashReceiptExpense: korean ? "현금영수증(지출증빙용)" : "Cash receipt (expense evidence)"
        case .businessCreditCard: korean ? "사업용 신용카드 매출전표" : "Business credit card slip"
        case .simpleReceipt: korean ? "간이영수증" : "Simple receipt"
        case .foreignInvoice: korean ? "해외 인보이스" : "Foreign invoice"
        case .exportEvidence: korean ? "수출 증빙(PayPal 정산·외화입금)" : "Export evidence (PayPal settlement, FX inflow)"
        case .estimatedSplit: korean ? "추정 분리(증빙 없음)" : "Estimated split (no evidence)"
        }
    }
}
