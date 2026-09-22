import Foundation

/// 비밀 마스킹 단일 규칙 정의 (데이터 SSOT)
public struct SecretMaskRule: Sendable {
    public let id: String
    public let summary: String
    public let regex: NSRegularExpression
    public let template: String

    public init(
        id: String,
        summary: String,
        pattern: String,
        template: String,
        options: NSRegularExpression.Options = []
    ) {
        self.id = id
        self.summary = summary
        do {
            self.regex = try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            preconditionFailure("Invalid regex pattern for \(id): \(error)")
        }
        self.template = template
    }
}

public enum SecretMaskRuleData {
    public static let mask = "***"

    /// 값 형태 플래그 목록 (--token, --api-key, --password, --secret, -p)
    public static let valueFlags: [String] = [
        "--token",
        "--api-key",
        "--password",
        "--secret",
        "-p"
    ]

    /// KEY=VALUE 에서 KEY 가 포함해야 하는 민감 키워드 (대소문자 무관)
    public static let sensitiveKeyKeywords: [String] = [
        "TOKEN",
        "SECRET",
        "PASSWORD",
        "KEY",
        "AUTH"
    ]

    /// 알려진 토큰 접두사 목록
    public static let tokenPrefixes: [String] = [
        "sk-",
        "ghp_",
        "glpat-",
        "xoxb-"
    ]

    /// 인증 헤더 이름
    public static let authorizationHeaderName = "Authorization"

    /// 규칙 패턴 목록 한 곳 (SSOT)
    public static let rules: [SecretMaskRule] = [
        // 1. URL 의 user:pass@
        SecretMaskRule(
            id: "url-credentials",
            summary: "URL user:pass@ masking",
            pattern: "([a-zA-Z][a-zA-Z0-9+.-]*://[^/\\s:@]+):([^@\\s/]+)@",
            template: "$1:***@"
        ),
        // 2-A. 따옴표로 둘러싸인 Authorization: 헤더
        SecretMaskRule(
            id: "authorization-header-quoted",
            summary: "Quoted Authorization header masking",
            pattern: "(?i)(?<=^|[\\s;&|])([\"'])Authorization:\\s*[^\"']*\\1",
            template: "$1Authorization: ***$1"
        ),
        // 2-B. 따옴표 없는 Authorization: 헤더 (Bearer/Basic 토큰 또는 단일 토큰)
        SecretMaskRule(
            id: "authorization-header-unquoted",
            summary: "Unquoted Authorization header masking",
            pattern: "(?i)(?<=^|[\\s;&|])Authorization:\\s*(?:(?:Bearer|Basic)\\s+[^\\s\"';&|]+|[^\\s\"';&|]+)",
            template: "Authorization: ***"
        ),
        // 3. 값 형태 플래그 = 형태 (--token=value, -p=value 등)
        SecretMaskRule(
            id: "value-flag-equals",
            summary: "Value flag with equals sign (--token=value, -p=value)",
            pattern: "(?i)(?<=^|[\\s;&|])(--(?:token|api-key|password|secret)|-p)=(?:[^\\s\"';&|]+|\"[^\"]*\"|'[^']*')",
            template: "$1=***"
        ),
        // 4. 값 형태 플래그 공백 분리 형태 (--token value, -p value 등)
        SecretMaskRule(
            id: "value-flag-space",
            summary: "Value flag with space separator (--token value, -p value)",
            pattern: "(?i)(?<=^|[\\s;&|])(--(?:token|api-key|password|secret)|-p)\\s+(?:[^\\s\"';&|]+|\"[^\"]*\"|'[^']*')",
            template: "$1 ***"
        ),
        // 5. KEY=VALUE 형태 (KEY 가 TOKEN|SECRET|PASSWORD|KEY|AUTH 포함)
        SecretMaskRule(
            id: "key-value",
            summary: "KEY=VALUE where KEY contains TOKEN, SECRET, PASSWORD, KEY, or AUTH",
            pattern: "(?i)(?<=^|[\\s;&|])([a-z0-9_.-]*(?:token|secret|password|key|auth)[a-z0-9_.-]*)=(?:[^\\s\"';&|]+|\"[^\"]*\"|'[^']*')",
            template: "$1=***"
        ),
        // 6. 접두 토큰 (sk-, ghp_, glpat-, xoxb-)
        SecretMaskRule(
            id: "prefix-tokens",
            summary: "Tokens starting with sk-, ghp_, glpat-, or xoxb-",
            pattern: "(?<=^|[\\s\"'=:,;])(?:sk-[A-Za-z0-9_-]+|ghp_[A-Za-z0-9]+|glpat-[A-Za-z0-9_-]+|xoxb-[A-Za-z0-9_-]+)(?=[\\s\"'=:,;]|$)",
            template: "***"
        ),
    ]
}
