import Foundation

public enum Redactor {
    public static let mask = "‹redacted›"
    public static func redact(_ text: String, values: [String]) -> String {
        values.reduce(text) { partial, value in value.isEmpty ? partial : partial.replacingOccurrences(of: value, with: mask) }
    }
}

public enum Placeholder {
    public static let token = "{{secret}}"
    public static func substitute(args: [String], value: String) -> [String] { args.map { $0.replacingOccurrences(of: token, with: value) } }
    public static func contains(_ args: [String]) -> Bool { args.contains { $0.contains(token) } }
    public static func substituteFields(args: [String], fields: [String: String]) -> [String] {
        let open = "{{field:", close = "}}"
        return args.map { arg in
            var result = ""; var rest = Substring(arg)
            while let range = rest.range(of: open) {
                result += rest[..<range.lowerBound]
                let after = rest[range.upperBound...]
                guard let closeRange = after.range(of: close) else { result += rest[range.lowerBound...]; rest = ""; break }
                let key = String(after[..<closeRange.lowerBound])
                result += fields[key] ?? "\(open)\(key)\(close)"
                rest = after[closeRange.upperBound...]
            }
            return result + rest
        }
    }
}
