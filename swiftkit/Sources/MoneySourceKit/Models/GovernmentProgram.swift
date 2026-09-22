import Foundation
import MoneyInflowKit
import LocalizationKit

// bizinfo.go.kr 지원사업정보 API 원천 DTO → 공유 MoneySource 계약으로 사상.

/// bizinfo 공고 항목(raw). 모든 필드가 올 수도/비었을 수도 있어 전부 옵셔널.
public struct BizInfoItem: Codable, Sendable {
    public let title: String?            // 공고명
    public let link: String?             // 상세 URL
    public let seq: String?              // 공고 ID
    public let author: String?           // 소관기관명
    public let excInsttNm: String?       // 수행기관명
    public let description: String?      // 사업개요
    public let lcategory: String?        // 지원분야 대분류(금융/기술/…)
    public let pubDate: String?          // 등록일자
    public let reqstDt: String?          // 신청(접수)기간 원문
    public let trgetNm: String?          // 지원대상 원문
    public let hashTags: String?
    public let rceptEngnHmpgUrl: String? // 사업신청 URL

    public init(
        title: String? = nil,
        link: String? = nil,
        seq: String? = nil,
        author: String? = nil,
        excInsttNm: String? = nil,
        description: String? = nil,
        lcategory: String? = nil,
        pubDate: String? = nil,
        reqstDt: String? = nil,
        trgetNm: String? = nil,
        hashTags: String? = nil,
        rceptEngnHmpgUrl: String? = nil
    ) {
        self.title = title
        self.link = link
        self.seq = seq
        self.author = author
        self.excInsttNm = excInsttNm
        self.description = description
        self.lcategory = lcategory
        self.pubDate = pubDate
        self.reqstDt = reqstDt
        self.trgetNm = trgetNm
        self.hashTags = hashTags
        self.rceptEngnHmpgUrl = rceptEngnHmpgUrl
    }
}

/// bizinfo 응답 래퍼: {"jsonArray":{"item":[...]}}.
public struct BizInfoResponse: Decodable, Sendable {
    public struct Wrapper: Decodable, Sendable {
        public let item: [BizInfoItem]?
        public init(item: [BizInfoItem]?) { self.item = item }
    }
    public let jsonArray: Wrapper?

    public init(from decoder: Decoder) throws {
        let outer = try decoder.container(keyedBy: OuterKey.self)
        let wrap = try outer.nestedContainer(keyedBy: WrapperKey.self, forKey: .jsonArray)
        do {
            let arr = try wrap.decode([BizInfoItem].self, forKey: .item)
            self.jsonArray = .init(item: arr)
        } catch {
            do {
                let one = try wrap.decode(BizInfoItem.self, forKey: .item)
                self.jsonArray = .init(item: [one])
            } catch {
                self.jsonArray = .init(item: nil)
            }
        }
    }
    private enum OuterKey: String, CodingKey { case jsonArray }
    private enum WrapperKey: String, CodingKey { case item }
    public init(item: [BizInfoItem]?) { self.jsonArray = .init(item: item) }
}

/// 정부 지원사업 공고. 공유 MoneySource 계약으로 사상돼 매칭 엔진이 그대로 소비한다.
public struct GovernmentProgram: MoneySource, Codable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let providerName: String
    public let summary: String
    public var sourceType: MoneySourceType { .governmentProgram }
    public let categories: Set<SupportCategory>
    public let regions: Set<KoreanRegion>
    public let targetAudienceText: String
    public let period: ApplicationPeriod
    public let detailURL: URL?

    /// 부가 표시 필드.
    public let providerAgency: String   // 소관기관(author)
    public let applyURL: URL?           // 신청 페이지(rceptEngnHmpgUrl)
    public let registrationDate: String?
    public let hashTags: String?

    public init(
        id: String, title: String, providerName: String, summary: String,
        categories: Set<SupportCategory>, regions: Set<KoreanRegion>,
        targetAudienceText: String, period: ApplicationPeriod,
        detailURL: URL?, providerAgency: String, applyURL: URL?,
        registrationDate: String?, hashTags: String?
    ) {
        self.id = id; self.title = title; self.providerName = providerName; self.summary = summary
        self.categories = categories; self.regions = regions
        self.targetAudienceText = targetAudienceText; self.period = period
        self.detailURL = detailURL; self.providerAgency = providerAgency; self.applyURL = applyURL
        self.registrationDate = registrationDate; self.hashTags = hashTags
    }

    public init(from item: BizInfoItem) {
        let trimmed: (String?) -> String? = { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let seq = trimmed(item.seq), !seq.isEmpty {
            self.id = seq
        } else {
            self.id = trimmed(item.title) ?? UUID().uuidString
        }
        self.title = trimmed(item.title) ?? "(제목 없음)"
        let provider = [trimmed(item.excInsttNm), trimmed(item.author)].compactMap { $0 }.filter { !$0.isEmpty }
        self.providerName = provider.first ?? ""
        self.providerAgency = trimmed(item.author) ?? ""
        self.summary = trimmed(item.description) ?? ""
        let catText = [item.lcategory, item.hashTags].compactMap { $0 }.joined(separator: " ")
        self.categories = Self.categories(from: catText)
        let regionText = [item.hashTags, item.trgetNm].compactMap { $0 }.joined(separator: " ")
        self.regions = Self.regions(from: regionText)
        self.targetAudienceText = trimmed(item.trgetNm) ?? ""
        self.period = ApplicationPeriod.parse(item.reqstDt ?? "")
        self.detailURL = (trimmed(item.link).flatMap { URL(string: $0) })
        self.applyURL = (trimmed(item.rceptEngnHmpgUrl).flatMap { URL(string: $0) })
        self.registrationDate = trimmed(item.pubDate)
        self.hashTags = trimmed(item.hashTags)
    }

    public static func from(_ items: [BizInfoItem]) -> [GovernmentProgram] {
        var seen = Set<String>(), out = [GovernmentProgram]()
        for item in items {
            let p = GovernmentProgram(from: item)
            if seen.insert(p.id).inserted { out.append(p) }
        }
        return out
    }

    // MARK: - 원문 → 열거형 사상

    private static let categoryMap: [(String, SupportCategory)] = [
        ("금융", .finance), ("자금", .finance), ("기술", .technology),
        ("인력", .workforce), ("수출", .export), ("내수", .domesticSales),
        ("창업", .startup), ("경영", .management), ("기타", .other),
    ]

    public static func categories(from text: String) -> Set<SupportCategory> {
        var set = Set<SupportCategory>()
        for (kw, cat) in categoryMap where text.contains(kw) { set.insert(cat) }
        return set
    }

    public static func regions(from text: String) -> Set<KoreanRegion> {
        var set = Set<KoreanRegion>()
        for r in KoreanRegion.allCases where r != .nationwide {
            if r.matchKeywords.contains(where: { text.contains($0) }) { set.insert(r) }
        }
        return set
    }
}

// MARK: - 내장 샘플

extension GovernmentProgram {
    public static let sampleRaw: [BizInfoItem] = [
        BizInfoItem(title: "2026 소상공인 정책자금 융자지원", link: BizInfoEndpoints.listingURLString,
                    seq: "S1", author: "중소벤처기업부", excInsttNm: "소상공인시장진흥공단",
                    description: "경영안정 자금 저리 융자(최대 7,000만 원)",
                    lcategory: "금융", pubDate: "20260720", reqstDt: "20260801~20260831",
                    trgetNm: "서울 소상공인 및 일반소상공인", hashTags: "금융,서울,소상공인",
                    rceptEngnHmpgUrl: BizInfoEndpoints.listingURLString),
        BizInfoItem(title: "청년창업사관학교 16기 입교생 모집", link: BizInfoEndpoints.listingURLString,
                    seq: "S2", author: "중소벤처기업부", excInsttNm: "창업진흥원",
                    description: "창업 공간 및 사업화 자금(최대 1억 원) 지원",
                    lcategory: "창업", pubDate: "20260715", reqstDt: "20260805~20260915",
                    trgetNm: "청년(만 39세 이하) 예비·초기 창업기업", hashTags: "창업,전국,청년",
                    rceptEngnHmpgUrl: BizInfoEndpoints.listingURLString),
        BizInfoItem(title: "중소기업 상용화기술개발사업 공고", link: BizInfoEndpoints.listingURLString,
                    seq: "S3", author: "산업통상자원부", excInsttNm: "중소기업기술정보진흥원",
                    description: "기술 R&D 출연금 매칭 지원",
                    lcategory: "기술", pubDate: "20260630", reqstDt: "20260810~20260930",
                    trgetNm: "중소기업(독립성·상시근로자 수 충족)", hashTags: "기술,전국",
                    rceptEngnHmpgUrl: BizInfoEndpoints.listingURLString),
        BizInfoItem(title: "여성기업 해외판로 개척지원", link: BizInfoEndpoints.listingURLString,
                    seq: "S4", author: "여성가족부", excInsttNm: "여성경제인활동지원사업단",
                    description: "해외 바이어 매칭 및 전시회 부스비 지원",
                    lcategory: "내수", pubDate: "20260501", reqstDt: "20260510~20260620",
                    trgetNm: "여성기업", hashTags: "내수,부산,여성",
                    rceptEngnHmpgUrl: nil),
    ]

    public static let sample: [GovernmentProgram] = GovernmentProgram.from(sampleRaw)
}
