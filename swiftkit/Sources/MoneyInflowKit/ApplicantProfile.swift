import Foundation

// "돈 들어오는 거 찾기" 앱 가족의 공유 코어 — 신청자 상태(내 상황)·소스 모델·매칭 엔진.
// 각 가족 앱(government-program-lookup / loan-lookup / ...)이 같은 프로필과 매칭 규칙으로
// 서로 다른 데이터 원천을 소비한다. 매칭은 결정적(LLM 아님)이어야 한다 — 규칙은 여기 한 곳.

/// 신청자의 비즈니스 유형. 지원사업의 "지원대상" 원문 키워드 매칭에 쓰인다.
/// 복수 선택 가능(예: 청년 창업기업 = [.youth, .startup]).
public enum BusinessType: String, CaseIterable, Codable, Sendable, Identifiable {
    case startup
    case sme
    case soho
    case microSme
    case youth
    case woman
    case midCompany
    case general

    public var id: String { rawValue }

    /// 지원대상 원문에 이 유형이 해당하는지 판정하는 키워드(포함 매칭).
    public var matchKeywords: [String] {
        switch self {
        case .startup:    return ["창업", "스타트업"]
        case .sme:        return ["중소기업"]
        case .soho:       return ["소상공인"]
        case .microSme:   return ["소기업"]
        case .youth:      return ["청년"]
        case .woman:      return ["여성기업", "여성"]
        case .midCompany: return ["중견기업"]
        case .general:    return []
        }
    }

    public var displayName: String {
        switch self {
        case .startup:    return "창업기업 · 예비창업자"
        case .sme:        return "중소기업"
        case .soho:       return "소상공인"
        case .microSme:   return "소기업"
        case .youth:      return "청년"
        case .woman:      return "여성기업"
        case .midCompany: return "중견기업"
        case .general:    return "일반 · 기타 (전체 보기)"
        }
    }
}

/// 대한민국 행정구역. 데이터 원천의 지역 해시태그/키워드와 매칭.
public enum KoreanRegion: String, CaseIterable, Codable, Sendable, Identifiable {
    case nationwide, seoul, busan, daegu, incheon
    case gwangju, daejeon, ulsan, sejong
    case gyeonggi, gangwon, chungbuk, chungnam
    case jeonbuk, jeonnam, gyeongbuk, gyeongnam, jeju

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .nationwide: return "전국"
        case .seoul: return "서울"
        case .busan: return "부산"
        case .daegu: return "대구"
        case .incheon: return "인천"
        case .gwangju: return "광주"
        case .daejeon: return "대전"
        case .ulsan: return "울산"
        case .sejong: return "세종"
        case .gyeonggi: return "경기"
        case .gangwon: return "강원"
        case .chungbuk: return "충북"
        case .chungnam: return "충남"
        case .jeonbuk: return "전북"
        case .jeonnam: return "전남"
        case .gyeongbuk: return "경북"
        case .gyeongnam: return "경남"
        case .jeju: return "제주"
        }
    }

    /// 원문(해시태그·지원대상·사업개요)에서 이 지역 언급을 잡는 키워드.
    /// nationwide 는 빈 배열(=제한 없음)로, 매칭 로직이 따로 처리한다.
    public var matchKeywords: [String] {
        switch self {
        case .nationwide: return []
        case .seoul: return ["서울"]
        case .busan: return ["부산"]
        case .daegu: return ["대구"]
        case .incheon: return ["인천"]
        case .gwangju: return ["광주"]
        case .daejeon: return ["대전"]
        case .ulsan: return ["울산"]
        case .sejong: return ["세종"]
        case .gyeonggi: return ["경기"]
        case .gangwon: return ["강원"]
        case .chungbuk: return ["충북", "충청북도"]
        case .chungnam: return ["충남", "충청남도"]
        case .jeonbuk: return ["전북", "전라북도"]
        case .jeonnam: return ["전남", "전라남도"]
        case .gyeongbuk: return ["경북", "경상북도"]
        case .gyeongnam: return ["경남", "경상남도"]
        case .jeju: return ["제주"]
        }
    }
}

/// 지원 분야(대분류). 데이터 원천의 분야 코드/태그와 매칭.
public enum SupportCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case finance, technology, workforce, export, domesticSales, startup, management, other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .finance: return "금융 · 자금"
        case .technology: return "기술 · R&D"
        case .workforce: return "인력 · 채용"
        case .export: return "수출"
        case .domesticSales: return "내수 · 판로"
        case .startup: return "창업"
        case .management: return "경영 · 사업화"
        case .other: return "기타"
        }
    }

    /// bizinfo 분야 코드(searchLclasId) 매핑 — 앱이 사용.
    public var bizInfoLclasId: String? {
        switch self {
        case .finance: return "01"
        case .technology: return "02"
        case .workforce: return "03"
        case .export: return "04"
        case .domesticSales: return "05"
        case .startup: return "06"
        case .management: return "07"
        case .other: return "09"
        }
    }
}

/// 신청자 상태("지금 내 상황"). 모든 가족 앱이 같은 프로필 한 벌을 공유한다.
public struct ApplicantProfile: Codable, Sendable, Equatable {
    public var businessTypes: Set<BusinessType>
    public var region: KoreanRegion
    public var categories: Set<SupportCategory>

    public init(
        businessTypes: Set<BusinessType> = [],
        region: KoreanRegion = .nationwide,
        categories: Set<SupportCategory> = []
    ) {
        self.businessTypes = businessTypes
        self.region = region
        self.categories = categories
    }

    /// 비어 있는 기본 프로필(아무 것도 고르지 않음 = 제한 없이 전체).
    public static let blank = ApplicantProfile()
}
