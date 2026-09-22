import Foundation

/// CDP eval 결과에서 credential·개인정보를 마스킹한다.
///
/// Phase D: 본인 사용 전제지만, 로그·히스토리·에이전트 전달 경로에서
/// 평문 credential 이 새어나가는 것을 방지한다.
public enum CDPCredentialFilter {

    public struct Result: Sendable {
        public let value: String
        public let didMask: Bool
    }

    /// 표현식과 결과를 보고 마스킹이 필요하면 적용한다.
    public static func mask(expression: String, result: String) -> Result {
        var masked = result
        var didMask = false

        // 1. password 필드 접근 — .value 가 포함된 password 표현식
        if expressionAccessesPassword(expression) {
            masked = "***"
            didMask = true
            return Result(value: masked, didMask: didMask)
        }

        // 2. document.cookie — 키=값 쌍의 값을 마스킹
        if expression.contains("document.cookie") {
            masked = maskCookieString(result)
            didMask = masked != result
        }

        // 3. 토큰 패턴 — 20자+ 결과에 Bearer/JWT/session/token 값
        if masked.count >= 20 {
            let tokenMasked = maskTokenPatterns(masked)
            if tokenMasked != masked {
                masked = tokenMasked
                didMask = true
            }
        }

        // 4. 한국 주민번호 (XXXXXX-XXXXXXX)
        let rrnMasked = maskKoreanRRN(masked)
        if rrnMasked != masked {
            masked = rrnMasked
            didMask = true
        }

        // 5. 한국 전화번호 (010-XXXX-XXXX, 01X-XXX-XXXX)
        let phoneMasked = maskKoreanPhone(masked)
        if phoneMasked != masked {
            masked = phoneMasked
            didMask = true
        }

        return Result(value: masked, didMask: didMask)
    }

    static func expressionAccessesPassword(_ expr: String) -> Bool {
        // password 접근: [type=password] / 'password' / "password" / #password / getElementById('password')
        let pwPattern = #"(?:\[type=?)?["']?password["']?\]?|getElementById\(["']password["']\)|#password\b"#
        // 값 접근: .value / getAttribute('value') — textContent·innerHTML 은 레이블 오탐
        let valuePattern = #"\.value\b|getAttribute\(["']value"#
        let pw: NSRegularExpression
        let val: NSRegularExpression
        do {
            pw = try NSRegularExpression(pattern: pwPattern, options: [.caseInsensitive])
            val = try NSRegularExpression(pattern: valuePattern, options: [.caseInsensitive])
        } catch {
            return false
        }
        let ns = expr as NSString
        return pw.firstMatch(in: expr, range: NSRange(location: 0, length: ns.length)) != nil
            && val.firstMatch(in: expr, range: NSRange(location: 0, length: ns.length)) != nil
    }

    static func maskCookieString(_ value: String) -> String {
        let pairs = value.split(separator: ";", omittingEmptySubsequences: false)
        let masked = pairs.map { pair -> String in
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                return "\(parts[0])=***"
            }
            return String(pair)
        }
        return masked.joined(separator: ";")
    }

    private static let tokenPattern = try! NSRegularExpression(
        pattern: #"(?:(?:Bearer|JWT)[\s=:]+\S{20,}|eyJ[A-Za-z0-9_-]{17,}|(?:session|token|access_token|refresh_token)[\s=:]+\S{20,})"#,
        options: [.caseInsensitive]
    )

    static func maskTokenPatterns(_ value: String) -> String {
        let range = NSRange(value.startIndex..., in: value)
        return tokenPattern.stringByReplacingMatches(
            in: value, range: range, withTemplate: "***")
    }

    private static let rrnPattern = try! NSRegularExpression(
        pattern: #"\d{6}-[1-4]\d{6}"#
    )

    static func maskKoreanRRN(_ value: String) -> String {
        let range = NSRange(value.startIndex..., in: value)
        return rrnPattern.stringByReplacingMatches(
            in: value, range: range, withTemplate: "******-*******")
    }

    private static let phonePattern = try! NSRegularExpression(
        pattern: #"01[016789]-?\d{3,4}-?\d{4}"#
    )

    static func maskKoreanPhone(_ value: String) -> String {
        let range = NSRange(value.startIndex..., in: value)
        return phonePattern.stringByReplacingMatches(
            in: value, range: range, withTemplate: "0**-****-****")
    }
}
