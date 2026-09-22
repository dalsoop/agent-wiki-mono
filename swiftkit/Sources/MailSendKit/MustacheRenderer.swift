import Foundation

public enum MustacheError: Error, LocalizedError, Sendable, Equatable {
    case invalidJSON(String)

    public var errorDescription: String? {
        switch self {
        case .invalidJSON(let detail): return "JSON 파싱 실패: \(detail)"
        }
    }
}

/// 최소 Mustache: `{{{key}}}` 비이스케이프, `{{key}}` 치환. HTML 모드에서만 `& < > " '` 이스케이프.
public enum MustacheRenderer {
    private static let unescapedRegex = try! NSRegularExpression(
        pattern: #"\{\{\{\s*([A-Za-z0-9_.-]+)\s*\}\}\}"#
    )
    private static let escapedRegex = try! NSRegularExpression(
        pattern: #"\{\{\s*([A-Za-z0-9_.-]+)\s*\}\}"#
    )

    public static func render(_ template: String, data: [String: String], htmlEscape: Bool) -> String {
        let unescaped = replace(template, regex: unescapedRegex) { key in
            data[key] ?? ""
        }
        return replace(unescaped, regex: escapedRegex) { key in
            let raw = data[key] ?? ""
            return htmlEscape ? escapeHTML(raw) : raw
        }
    }

    public static func render(subject: String, html: String, text: String, data: [String: String]) -> RenderedMail {
        RenderedMail(
            subject: render(subject, data: data, htmlEscape: false),
            html: render(html, data: data, htmlEscape: true),
            text: render(text, data: data, htmlEscape: false)
        )
    }

    public static func flattenJSON(_ raw: String) throws -> [String: String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [:] }
        guard let data = trimmed.data(using: .utf8) else {
            throw MustacheError.invalidJSON("utf-8 아님")
        }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw MustacheError.invalidJSON(error.localizedDescription)
        }
        var out: [String: String] = [:]
        flatten(object, prefix: "", into: &out)
        return out
    }

    public static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func replace(
        _ input: String,
        regex: NSRegularExpression,
        value: (String) -> String
    ) -> String {
        let ns = input as NSString
        let matches = regex.matches(in: input, range: NSRange(location: 0, length: ns.length))
        var result = ""
        var cursor = 0
        for match in matches {
            let full = match.range
            if full.location > cursor {
                result += ns.substring(with: NSRange(location: cursor, length: full.location - cursor))
            }
            let keyRange = match.range(at: 1)
            let key = ns.substring(with: keyRange)
            result += value(key)
            cursor = full.location + full.length
        }
        if cursor < ns.length {
            result += ns.substring(from: cursor)
        }
        return result
    }

    private static func flatten(_ value: Any, prefix: String, into out: inout [String: String]) {
        if let dict = value as? [String: Any] {
            for (key, nested) in dict {
                let next = prefix.isEmpty ? key : "\(prefix).\(key)"
                flatten(nested, prefix: next, into: &out)
            }
            return
        }
        if let array = value as? [Any] {
            for (index, nested) in array.enumerated() {
                flatten(nested, prefix: "\(prefix).\(index)", into: &out)
            }
            return
        }
        guard !prefix.isEmpty else { return }
        if value is NSNull {
            out[prefix] = ""
        } else {
            out[prefix] = "\(value)"
        }
    }
}
