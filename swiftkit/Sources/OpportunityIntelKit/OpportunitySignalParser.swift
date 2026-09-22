import Foundation

/// 기회/공고/딜 텍스트에서 금액, 지원금, 할인율, 코드 식별자 및 특화 태그를 자동 추출하는 파서
public enum OpportunitySignalParser {

    public struct ParsedSignals: Sendable, Equatable {
        public var pricesOrGrants: [String]
        public var discountOrSupportRates: [Int]
        public var codes: [String]
        public var rawPercentages: [String]
        public var tags: [String]

        public init(
            pricesOrGrants: [String] = [],
            discountOrSupportRates: [Int] = [],
            codes: [String] = [],
            rawPercentages: [String] = [],
            tags: [String] = []
        ) {
            self.pricesOrGrants = pricesOrGrants
            self.discountOrSupportRates = discountOrSupportRates
            self.codes = codes
            self.rawPercentages = rawPercentages
            self.tags = tags
        }
    }

    private static func makeRegex(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression? {
        do {
            return try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            FileHandle.standardError.write(Data("[OpportunitySignalParser] regex build failed: \(error)\n".utf8))
            return nil
        }
    }

    // MARK: - 금액 / 정부지원금 정규식 (만원/억원/달러/유로/원)
    private static let priceRegexes: [NSRegularExpression] = [
        makeRegex(#"(?:최대\s*)?(?:[0-9]+(?:\.[0-9]+)?)\s*(?:억|천만|백만|만)\s*원"#, options: [.caseInsensitive]),
        makeRegex(#"₩\s*[0-9]{1,3}(?:,[0-9]{3})+(?:\s*원)?"#),
        makeRegex(#"[0-9]{1,3}(?:,[0-9]{3})+\s*원"#),
        makeRegex(#"\$\s*[0-9]+(?:\.[0-9]+)?(?:\s*\/\s*(?:mo|month|yr|year))?"#, options: [.caseInsensitive]),
        makeRegex(#"€\s*[0-9]+(?:\.[0-9]+)?"#)
    ].compactMap { $0 }

    // MARK: - 할인율 / 정부지원 비율 (%)
    private static let percentageRegex: NSRegularExpression? = {
        makeRegex(#"([0-9]{1,2}|100)\s*%\s*(?:할인|지원|감면|off)?"#, options: [.caseInsensitive])
    }()

    // MARK: - 프로모션 코드 / 공고 접수 식별 번호
    private static let codeRegexes: [NSRegularExpression] = [
        makeRegex(#"(?:코드|쿠폰|프로모|바우처|접수번호|공고번호)\s*[:：]\s*([A-Za-z0-9_\-]{3,20})"#, options: [.caseInsensitive]),
        makeRegex(#"(?:\[|\()(?:코드|쿠폰|code)\s*[:\s]\s*([A-Za-z0-9_\-]{3,20})(?:\]|\))"#, options: [.caseInsensitive])
    ].compactMap { $0 }

    /// 텍스트(제목 + 요약)에서 기회 신호를 일괄 추출한다.
    public static func parse(title: String, body: String) -> ParsedSignals {
        let combined = "\(title)\n\(body)"
        let nsString = combined as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)

        let prices = extractPrices(combined: combined, nsString: nsString, fullRange: fullRange)
        let (rates, rawPercentages) = extractPercentages(combined: combined, nsString: nsString, fullRange: fullRange)
        let codes = extractCodes(combined: combined, nsString: nsString, fullRange: fullRange)
        let tags = extractTags(from: combined)

        return ParsedSignals(
            pricesOrGrants: prices,
            discountOrSupportRates: rates.sorted(by: >),
            codes: codes,
            rawPercentages: rawPercentages,
            tags: tags
        )
    }

    private static func extractPrices(combined: String, nsString: NSString, fullRange: NSRange) -> [String] {
        var prices: [String] = []
        for rx in priceRegexes {
            for m in rx.matches(in: combined, range: fullRange) {
                let s = nsString.substring(with: m.range).trimmingCharacters(in: .whitespacesAndNewlines)
                if !prices.contains(s) { prices.append(s) }
            }
        }
        return prices
    }

    private static func extractPercentages(combined: String, nsString: NSString, fullRange: NSRange) -> ([Int], [String]) {
        guard let pMatches = percentageRegex?.matches(in: combined, range: fullRange) else {
            return ([], [])
        }
        var rates: [Int] = []
        var rawPercentages: [String] = []
        for m in pMatches {
            let raw = nsString.substring(with: m.range).trimmingCharacters(in: .whitespacesAndNewlines)
            if !rawPercentages.contains(raw) { rawPercentages.append(raw) }
            collectPercentageRate(m: m, nsString: nsString, rates: &rates)
        }
        return (rates, rawPercentages)
    }

    private static func collectPercentageRate(m: NSTextCheckingResult, nsString: NSString, rates: inout [Int]) {
        guard m.numberOfRanges >= 2 else { return }
        let numStr = nsString.substring(with: m.range(at: 1))
        guard let num = Int(numStr), (1...100).contains(num) else { return }
        if !rates.contains(num) { rates.append(num) }
    }

    private static func extractCodes(combined: String, nsString: NSString, fullRange: NSRange) -> [String] {
        var codes: [String] = []
        for rx in codeRegexes {
            for m in rx.matches(in: combined, range: fullRange) {
                collectMatchedCode(m: m, nsString: nsString, codes: &codes)
            }
        }
        return codes
    }

    private static func collectMatchedCode(m: NSTextCheckingResult, nsString: NSString, codes: inout [String]) {
        guard m.numberOfRanges >= 2 else { return }
        let code = nsString.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, !codes.contains(code) else { return }
        codes.append(code)
    }

    // MARK: - 정부사업 특화 키워드 태그 추출

    private struct TagPattern {
        let pattern: String
        let tag: String
        let options: NSString.CompareOptions
    }

    private static let generalTagPatterns: [TagPattern] = [
        TagPattern(pattern: #"바우처"#, tag: "바우처", options: .caseInsensitive),
        TagPattern(pattern: #"매칭\s*(?:펀드|지원|투자)"#, tag: "매칭펀드", options: .regularExpression),
        TagPattern(pattern: #"청년\s*창업|청창사"#, tag: "청년창업", options: .regularExpression),
        TagPattern(pattern: #"자부담|자기\s*부담|민간\s*부담"#, tag: "자부담", options: .regularExpression),
        TagPattern(pattern: #"예비\s*창업|예창패"#, tag: "예비창업", options: .regularExpression),
        TagPattern(pattern: #"초기\s*창업|초창패"#, tag: "초기창업", options: .regularExpression),
        TagPattern(pattern: #"\b(?:tips|팁스|프리팁스|포스트팁스)\b"#, tag: "TIPS", options: [.regularExpression, .caseInsensitive]),
        TagPattern(pattern: #"스마트\s*(?:공장|팩토리)"#, tag: "스마트공장", options: .regularExpression),
        TagPattern(pattern: #"사업화(?:\s*지원)?"#, tag: "사업화", options: .regularExpression),
        TagPattern(pattern: #"해외\s*진출|글로벌\s*진출|수출\s*지원"#, tag: "해외진출", options: .regularExpression)
    ]

    public static func extractTags(from text: String) -> [String] {
        var tags: [String] = []
        extractRDAndNonRDTags(from: text, into: &tags)
        for entry in generalTagPatterns {
            if text.range(of: entry.pattern, options: entry.options) != nil {
                tags.append(entry.tag)
            }
        }
        return tags
    }

    private static func extractRDAndNonRDTags(from text: String, into tags: inout [String]) {
        let hasNonRD = text.range(
            of: #"(?:비\s*[-/·]?\s*r&d|비\s*연구\s*개발)"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        if hasNonRD {
            tags.append("비R&D")
        }

        let scrubbedForRD = text.replacingOccurrences(
            of: #"(?:비\s*[-/·]?\s*r&d|비\s*연구\s*개발)"#,
            with: "___",
            options: [.regularExpression, .caseInsensitive]
        )
        let hasRD = scrubbedForRD.range(
            of: #"(?:\br&d\b|알앤디|연구\s*개발)"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        if hasRD {
            tags.append("R&D")
        }
    }
}
