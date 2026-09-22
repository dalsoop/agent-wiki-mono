import Foundation

/// 거래 상대방의 과세 유형.
public enum CounterpartyKind: String, Codable, Sendable, CaseIterable {
    case generalTaxpayer
    case simplifiedTaxpayer
    case taxExemptBusiness
    case foreignBusiness
    case nonBusinessIndividual
    case unknown

    public func label(korean: Bool) -> String {
        switch self {
        case .generalTaxpayer: korean ? "일반과세자" : "General taxpayer"
        case .simplifiedTaxpayer: korean ? "간이과세자" : "Simplified taxpayer"
        case .taxExemptBusiness: korean ? "면세사업자" : "VAT-exempt business"
        case .foreignBusiness: korean ? "해외 사업자" : "Foreign business"
        case .nonBusinessIndividual: korean ? "비사업자(개인)" : "Non-business individual"
        case .unknown: korean ? "미확인" : "Unknown"
        }
    }
}

/// 매입 용도 — 사업 관련성과 법정 불공제 항목.
public enum PurchasePurpose: String, Codable, Sendable, CaseIterable {
    case general
    case entertainment
    case nonBusiness
    case nonBusinessPassengerVehicle
    case taxExemptBusinessUse

    public func label(korean: Bool) -> String {
        switch self {
        case .general: korean ? "사업 일반" : "General business"
        case .entertainment: korean ? "접대비(기업업무추진비)" : "Entertainment"
        case .nonBusiness: korean ? "사업 무관" : "Non-business"
        case .nonBusinessPassengerVehicle: korean ? "비영업용 소형승용차" : "Non-business passenger vehicle"
        case .taxExemptBusinessUse: korean ? "면세사업 관련" : "VAT-exempt business use"
        }
    }
}

/// 매입세액 공제 판정 — 용도 → 상대방 → 증빙 순으로 좁힌다(부가가치세법 제39조 불공제 항목,
/// 제38조 적격증빙). 판정은 세 개의 작은 규칙 함수를 `??` 로 이은 것이라 각 규칙이 따로 검증된다.
public enum InputVATDeductibility {
    public enum Judgement: Codable, Sendable, Equatable {
        case deductible
        case nonDeductible(Reason)
        case needsReview(Reason)

        public var isDeductible: Bool { self == .deductible }

        public var reason: Reason? {
            switch self {
            case .deductible: nil
            case let .nonDeductible(reason), let .needsReview(reason): reason
            }
        }

        public func label(korean: Bool) -> String {
            switch self {
            case .deductible: korean ? "공제" : "Deductible"
            case let .nonDeductible(reason): (korean ? "불공제 — " : "Non-deductible — ") + reason.label(korean: korean)
            case let .needsReview(reason): (korean ? "검토 필요 — " : "Needs review — ") + reason.label(korean: korean)
            }
        }
    }

    public static func judge(
        evidence: EvidenceKind,
        counterpartyKind: CounterpartyKind,
        purpose: PurchasePurpose = .general
    ) -> Judgement {
        purposeJudgement(purpose)
            ?? counterpartyJudgement(counterpartyKind)
            ?? evidenceJudgement(evidence, counterparty: counterpartyKind)
    }

    /// 법정 불공제 용도는 증빙·상대방과 무관하게 불공제.
    static func purposeJudgement(_ purpose: PurchasePurpose) -> Judgement? {
        switch purpose {
        case .general: nil
        case .entertainment: .nonDeductible(.entertainmentExpense)
        case .nonBusiness: .nonDeductible(.nonBusinessUse)
        case .nonBusinessPassengerVehicle: .nonDeductible(.nonBusinessPassengerVehicle)
        case .taxExemptBusinessUse: .nonDeductible(.taxExemptBusinessUse)
        }
    }

    /// 국내 부가세를 거래징수하지 않는 상대방은 공제할 세액 자체가 없다.
    static func counterpartyJudgement(_ counterparty: CounterpartyKind) -> Judgement? {
        switch counterparty {
        case .generalTaxpayer, .simplifiedTaxpayer, .unknown: nil
        case .foreignBusiness: .nonDeductible(.foreignSupplierNoKoreanVAT)
        case .taxExemptBusiness: .nonDeductible(.taxExemptSupplier)
        case .nonBusinessIndividual: .nonDeductible(.nonBusinessSeller)
        }
    }

    static func evidenceJudgement(_ evidence: EvidenceKind, counterparty: CounterpartyKind) -> Judgement {
        switch evidence {
        case .simpleReceipt: .nonDeductible(.inadequateEvidence)
        case .foreignInvoice: .nonDeductible(.foreignSupplierNoKoreanVAT)
        case .exportEvidence: .needsReview(.salesEvidenceOnPurchase)
        case .estimatedSplit: .needsReview(.estimatedSplitNeedsEvidence)
        case .taxInvoice, .electronicTaxInvoice: invoiceJudgement(counterparty: counterparty)
        case .cashReceiptExpense, .businessCreditCard: cardOrReceiptJudgement(counterparty: counterparty)
        }
    }

    /// 세금계산서는 발급 자체가 과세 거래의 증거 — 상대방 미확인이어도 공제. 간이과세자 발급분만 확인.
    static func invoiceJudgement(counterparty: CounterpartyKind) -> Judgement {
        counterparty == .simplifiedTaxpayer ? .needsReview(.simplifiedTaxpayerInvoiceEligibility) : .deductible
    }

    /// 카드·현금영수증은 상대방이 일반과세자일 때만 확정 공제. 간이과세자·미확인은 검토.
    static func cardOrReceiptJudgement(counterparty: CounterpartyKind) -> Judgement {
        switch counterparty {
        case .generalTaxpayer: .deductible
        case .simplifiedTaxpayer: .needsReview(.simplifiedTaxpayerCardSlip)
        case .unknown, .taxExemptBusiness, .foreignBusiness, .nonBusinessIndividual: .needsReview(.unknownCounterparty)
        }
    }
}
