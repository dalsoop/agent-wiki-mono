import Foundation

public enum SQLSafety {
    private static let allowedKeywords: Set<String> = ["select", "with", "show", "explain"]

    public static func isReadOnly(_ sql: String) -> Bool {
        guard let keyword = firstKeyword(in: sql) else { return false }
        guard allowedKeywords.contains(keyword) else { return false }
        // The read-only promise must also block STACKED statements: psql runs every `;`-separated
        // statement in one `-c`, so `select 1; drop table t` would otherwise pass on its first keyword.
        return isSingleStatement(sql)
    }

    /// True when `sql` is at most one statement — no top-level `;` separating a second statement.
    /// Semicolons inside string literals (`'…'`, `"…"`, with doubled-quote escaping) and comments
    /// (`-- …`, `/* … */`) are ignored. Dollar-quoting isn't parsed; such input counts conservatively
    /// as multiple statements (rejected), which is safe for a read-only guard.
    static func isSingleStatement(_ sql: String) -> Bool {
        let chars = Array(sql)
        let n = chars.count
        var i = 0
        var statements = 0
        var currentHasContent = false
        while i < n {
            let c = chars[i]
            if c == "-", i + 1 < n, chars[i + 1] == "-" {
                i += 2
                while i < n, chars[i] != "\n" { i += 1 }
                continue
            }
            if c == "/", i + 1 < n, chars[i + 1] == "*" {
                i += 2
                while i + 1 < n, !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
                i = min(i + 2, n)
                continue
            }
            if c == "'" || c == "\"" {
                currentHasContent = true
                let quote = c
                i += 1
                while i < n {
                    if chars[i] == quote {
                        if i + 1 < n, chars[i + 1] == quote { i += 2; continue }   // doubled escape
                        i += 1; break
                    }
                    i += 1
                }
                continue
            }
            if c == ";" {
                if currentHasContent { statements += 1; currentHasContent = false }
                i += 1
                continue
            }
            if !c.isWhitespace { currentHasContent = true }
            i += 1
        }
        if currentHasContent { statements += 1 }
        return statements <= 1
    }

    private static func firstKeyword(in sql: String) -> String? {
        var text = sql[...]

        while true {
            text = text.drop { $0.isWhitespace || $0 == ";" }
            if text.hasPrefix("--") {
                if let newline = text.firstIndex(of: "\n") {
                    text = text[text.index(after: newline)...]
                    continue
                }
                return nil
            }
            if text.hasPrefix("/*") {
                guard let end = text.range(of: "*/") else { return nil }
                text = text[end.upperBound...]
                continue
            }
            break
        }

        let keyword = text.prefix { $0.isLetter }
        guard !keyword.isEmpty else { return nil }
        return keyword.lowercased()
    }
}

