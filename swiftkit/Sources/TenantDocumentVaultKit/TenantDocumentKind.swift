import Foundation

public enum TenantDocumentKind: String, Codable, Sendable, CaseIterable {
    case businessLicense = "business_license"
    case corporateSealCert = "corporate_seal_cert"
    case bankBook = "bank_book"
    case shareholdersRegister = "shareholders_register"
    case taxCleanCert = "tax_clean_cert"
    case healthInsuranceCert = "health_cert"

    public var defaultValidityDays: Int? {
        switch self {
        case .corporateSealCert, .healthInsuranceCert:
            return 90
        case .taxCleanCert:
            return 30
        case .businessLicense, .bankBook, .shareholdersRegister:
            return nil
        }
    }

    public var displayName: String {
        switch self {
        case .businessLicense:
            return "사업자등록증"
        case .corporateSealCert:
            return "법인인감증명서"
        case .bankBook:
            return "통장사본"
        case .shareholdersRegister:
            return "주주명부"
        case .taxCleanCert:
            return "국세/지방세 납세증명서"
        case .healthInsuranceCert:
            return "건강보험자격득실확인서"
        }
    }
}
