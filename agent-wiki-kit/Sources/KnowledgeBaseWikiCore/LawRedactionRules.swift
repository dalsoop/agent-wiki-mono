import Foundation
import SecretMaskKit

// 세션 발화 가림 규칙 — 공용 비밀 가림 규칙(swiftkit `SecretMaskKit`) + 개인정보 규칙.
// 근거: docs/security.md "R2 와 세션"(적재 전에 비밀값·개인정보를 `***` 로 바꾼다, 발화는 지우지 않는다),
// docs/business-rules.md "화자"(증언 대조는 같은 가림 규칙을 적용한 실제 발화와 글자 단위로 대조한다).
// 적재(`archive`)와 소환의 증언 대조가 이 함수 하나를 쓴다. 규칙을 두 곳에 두지 않는다.

public enum LawRedaction {
    /// 가린 자리에 남기는 글자. 공용 규칙과 같은 값.
    public static let mask = SecretMask.mask

    /// 발화 하나를 가린다. 같은 입력에는 항상 같은 출력이다(증언 대조가 기대는 성질).
    /// 순서: 개인 키 블록 → 공용 비밀 규칙 → 추가 비밀 규칙 → 개인정보 규칙.
    public static func redact(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var current = replace(privateKeyBlock, in: text, template: mask)
        current = SecretMask.command(current)
        for rule in secretRules {
            current = replace(rule.regex, in: current, template: rule.template)
        }
        for rule in personalRules {
            current = replace(rule.regex, in: current, template: mask, where: rule.accept)
        }
        return current
    }

    // MARK: - 규칙

    struct Rule: Sendable {
        let regex: NSRegularExpression
        let template: String
    }

    struct PersonalRule: Sendable {
        let id: String
        let regex: NSRegularExpression
        let accept: @Sendable (String) -> Bool
    }

    static func regex(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            preconditionFailure("가림 규칙 정규식 오류: \(pattern): \(error)")
        }
    }

    /// PEM 개인 키 블록 전체.
    static let privateKeyBlock = regex(
        "-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----[\\s\\S]*?(?:-----END [A-Z0-9 ]*PRIVATE KEY-----|$)")

    /// 공용 규칙이 다루지 않는 비밀 모양.
    static let secretRules: [Rule] = [
        // JSON·설정의 따옴표 값: "password": "…", api_key = '…'
        Rule(
            regex: regex(
                "(?i)([\"']?[A-Za-z0-9_.-]*(?:password|passwd|secret|token|api[_-]?key|access[_-]?key|private[_-]?key)[A-Za-z0-9_.-]*[\"']?\\s*[:=]\\s*)([\"'])[^\"'\\n]*\\2"),
            template: "$1$2***$2"),
        // YAML 모양의 한 줄 값: password: hunter2
        Rule(
            regex: regex(
                "(?im)^(\\s*[A-Za-z0-9_.-]*(?:password|passwd|secret|api[_-]?key|access[_-]?key)[A-Za-z0-9_.-]*\\s*:\\s*)(?!\\*\\*\\*)[^\\s\"']+[ \\t]*$"),
            template: "$1***"),
        // Bearer 토큰(Authorization 머리 없이 나온 것)
        Rule(regex: regex("(?i)\\b(Bearer)\\s+(?!\\*\\*\\*)[A-Za-z0-9._~+/=-]{8,}"), template: "$1 ***"),
        // AWS 접근 키 id
        Rule(regex: regex("\\b(?:AKIA|ASIA)[0-9A-Z]{16}\\b"), template: "***"),
        // GitHub·GitLab·Slack·Google·Anthropic/OpenAI 토큰
        Rule(regex: regex("\\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})\\b"), template: "***"),
        Rule(regex: regex("\\bglpat-[A-Za-z0-9_-]{16,}"), template: "***"),
        Rule(regex: regex("\\bxox[abprs]-[A-Za-z0-9-]{10,}"), template: "***"),
        Rule(regex: regex("\\bAIza[0-9A-Za-z_-]{35}\\b"), template: "***"),
        Rule(regex: regex("\\bsk-[A-Za-z0-9_-]{16,}"), template: "***"),
        // JWT
        Rule(regex: regex("\\beyJ[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}"), template: "***"),
    ]

    /// 개인정보: 주민등록번호 → 카드번호(Luhn) → 전화번호 → 이메일 주소.
    static let personalRules: [PersonalRule] = [
        PersonalRule(
            id: "resident-registration-number",
            regex: regex("(?<![\\d-])\\d{2}(?:0[1-9]|1[0-2])(?:0[1-9]|[12]\\d|3[01])-?[1-8]\\d{6}(?![\\d-])"),
            accept: { _ in true }),
        PersonalRule(
            id: "card-number",
            regex: regex("(?<![\\d-])(?:\\d{4}[ -]?\\d{4}[ -]?\\d{4}[ -]?\\d{4}|\\d{4}[ -]?\\d{6}[ -]?\\d{5})(?![\\d-])"),
            accept: { luhnValid($0) }),
        PersonalRule(
            id: "phone-number",
            regex: regex(
                "(?<![\\d-])(?:\\+82[- ]?(?:0)?1[016789][- ]?\\d{3,4}[- ]?\\d{4}|01[016789]-?\\d{3,4}-?\\d{4}|0(?:2|[3-6][1-5]|70)-\\d{3,4}-\\d{4})(?![\\d-])"),
            accept: { _ in true }),
        PersonalRule(
            id: "email-address",
            regex: regex("(?<![A-Za-z0-9._%+-])(?!git@)[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"),
            accept: { _ in true }),
    ]

    /// 카드번호 검사 숫자(Luhn).
    static func luhnValid(_ raw: String) -> Bool {
        let digits = raw.compactMap(\.wholeNumberValue)
        guard (13...19).contains(digits.count) else { return false }
        var sum = 0
        for (offset, digit) in digits.reversed().enumerated() {
            if offset % 2 == 1 {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += digit
            }
        }
        return sum % 10 == 0
    }

    static func replace(_ regex: NSRegularExpression, in text: String, template: String) -> String {
        regex.stringByReplacingMatches(
            in: text, options: [], range: NSRange(location: 0, length: text.utf16.count), withTemplate: template)
    }

    /// 일치마다 `accept` 를 물어 받아들인 것만 바꾼다(뒤에서부터 바꿔 범위가 밀리지 않게).
    static func replace(
        _ regex: NSRegularExpression, in text: String, template: String, where accept: (String) -> Bool
    ) -> String {
        let source = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: source.length))
        guard !matches.isEmpty else { return text }
        let result = NSMutableString(string: text)
        for match in matches.reversed() where accept(source.substring(with: match.range)) {
            result.replaceCharacters(in: match.range, with: template)
        }
        return result as String
    }
}
