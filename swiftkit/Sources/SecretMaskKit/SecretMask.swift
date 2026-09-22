import Foundation

/// 명령줄·로그·헤더의 비밀 값을 마스킹하는 통합 인터페이스
public enum SecretMask {
    public static let mask = SecretMaskRuleData.mask

    /// 규칙 패턴 목록 한 곳 (SSOT)
    public static var rules: [SecretMaskRule] {
        SecretMaskRuleData.rules
    }

    /// 한 줄의 명령 문자열(또는 텍스트)에서 비밀 패턴을 마스킹한다.
    public static func command(_ line: String) -> String {
        var current = line
        for rule in SecretMaskRuleData.rules {
            let range = NSRange(location: 0, length: current.utf16.count)
            current = rule.regex.stringByReplacingMatches(
                in: current,
                options: [],
                range: range,
                withTemplate: rule.template
            )
        }
        return current
    }

    /// 인자 목록(argv)에서 비밀 값을 마스킹한다.
    public static func arguments(_ argv: [String]) -> [String] {
        var masked: [String] = []
        var redactNext = false

        for arg in argv {
            if redactNext {
                masked.append(mask)
                redactNext = false
                continue
            }

            let lower = arg.lowercased()
            if SecretMaskRuleData.valueFlags.contains(lower) {
                masked.append(arg)
                redactNext = true
                continue
            }

            masked.append(command(arg))
        }

        return masked
    }

    /// HTTP 헤더 딕셔너리에서 비밀 값을 마스킹한다.
    public static func headers(_ dict: [String: String]) -> [String: String] {
        var masked: [String: String] = [:]
        for (key, value) in dict {
            let upper = key.uppercased()
            if upper == SecretMaskRuleData.authorizationHeaderName.uppercased() ||
                SecretMaskRuleData.sensitiveKeyKeywords.contains(where: { upper.contains($0) }) {
                masked[key] = mask
            } else {
                masked[key] = command(value)
            }
        }
        return masked
    }
}
