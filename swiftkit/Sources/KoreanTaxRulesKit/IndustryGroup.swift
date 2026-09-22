import Foundation

/// 소득세법 시행령의 업종 그룹 — 간편장부 대상자(제208조)·성실신고확인대상자(제133조) 기준표가
/// 같은 세 묶음을 쓴다. 정보통신업(소프트웨어 개발 및 공급업)은 두 번째 그룹이다.
/// raw 값이 JSON 리소스의 그룹 키다.
public enum IndustryGroup: String, Codable, Sendable, CaseIterable {
    /// 농업·임업·어업, 광업, 도매 및 소매업, 부동산매매업 등.
    case agricultureWholesaleRetail
    /// 제조업, 숙박·음식점업, 건설업, 운수·창고업, 정보통신업, 금융·보험업 등.
    case manufacturingConstructionInformation
    /// 부동산임대업, 전문·과학·기술서비스업, 교육·보건·예술·기타 개인서비스업 등.
    case realEstateRentalAndServices
    /// 변호사·회계사·세무사·의사 등 — 수입금액과 무관하게 복식부기 의무.
    case professionalService

    public func label(korean: Bool) -> String {
        switch self {
        case .agricultureWholesaleRetail:
            korean ? "농·임·어업, 광업, 도소매업, 부동산매매업" : "Agriculture, mining, wholesale and retail, real estate trading"
        case .manufacturingConstructionInformation:
            korean
                ? "제조업, 숙박·음식점업, 건설업, 운수업, 정보통신업, 금융·보험업"
                : "Manufacturing, hospitality, construction, transport, information and communication, finance"
        case .realEstateRentalAndServices:
            korean ? "부동산임대업, 전문·과학·기술 및 기타 서비스업" : "Real estate rental, professional and other services"
        case .professionalService:
            korean ? "전문직(변호사·회계사·세무사·의사 등)" : "Licensed professional services"
        }
    }
}
