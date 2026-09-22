import Foundation

/// 붙여넣은 네이티브 재개 한 줄.
///
/// `runtime == nil` 은 세션 id 만 있거나, `--resume` 처럼 런타임이 겹치는 플래그만
/// 있는 경우다. 앱이 목록에서 툴을 가린다.
public struct ResumeRequest: Equatable, Sendable {
    public var runtime: AIRuntime?
    public var sessionID: String

    public init(runtime: AIRuntime?, sessionID: String) {
        self.runtime = runtime
        self.sessionID = sessionID
    }
}

/// `AIRuntime.resumeTokens` 표로 붙여넣기를 읽는다.
///
/// 앱 전용 표식(`agent-handoff pack`)은 여기 두지 않는다.
public enum ResumeRequestParser {
    public static func parse(_ text: String) -> ResumeRequest? {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        for line in lines {
            if let hit = parseLine(String(line)) { return hit }
        }
        return parseLine(text)
    }

    static func parseLine(_ raw: String) -> ResumeRequest? {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }
        let tokens = tokenize(line)
        guard !tokens.isEmpty else { return nil }

        for runtime in AIRuntime.allCases {
            if let id = match(runtime, tokens: tokens, requireExecutable: true) {
                return ResumeRequest(runtime: runtime, sessionID: id)
            }
        }
        for runtime in AIRuntime.allCases {
            if let id = match(runtime, tokens: tokens, requireExecutable: false) {
                return ResumeRequest(runtime: runtime, sessionID: id)
            }
        }
        if let id = valueAfterFlags(tokens: tokens, flags: sharedFlags()) {
            return ResumeRequest(runtime: nil, sessionID: id)
        }
        if looksLikeSessionID(line) {
            return ResumeRequest(runtime: nil, sessionID: tokens[0])
        }
        return nil
    }

    /// 실행 파일이 없을 때는 **그 런타임만** 쓰는 토큰으로만 맞춘다.
    /// `--resume` 은 claude/grok 이 겹치므로 여기 넣지 않는다.
    static func match(_ runtime: AIRuntime, tokens: [String], requireExecutable: Bool) -> String? {
        let rest: [String]
        if requireExecutable {
            guard let exeAt = tokens.firstIndex(where: {
                $0.caseInsensitiveCompare(runtime.executableName) == .orderedSame ||
                (runtime == .cursor && $0.caseInsensitiveCompare("cursor") == .orderedSame)
            }) else { return nil }
            rest = Array(tokens[(exeAt + 1)...])
        } else {
            rest = tokens
        }
        let wanted = requireExecutable ? runtime.resumeTokens : uniqueTokens(of: runtime)
        for token in wanted {
            switch token {
            case .flag(let flag):
                if let id = valueAfterFlag(tokens: rest, flag: flag) { return id }
            case .subcommand(let name):
                guard requireExecutable else { continue }
                guard let subAt = rest.firstIndex(where: {
                    $0.caseInsensitiveCompare(name) == .orderedSame
                }), subAt + 1 < rest.count else { continue }
                let id = rest[subAt + 1]
                if isUsableID(id) { return stripEquals(id) }
            }
        }
        return nil
    }

    static func uniqueTokens(of runtime: AIRuntime) -> [ResumeToken] {
        runtime.resumeTokens.filter { token in
            let key = tokenKey(token)
            let owners = AIRuntime.allCases.filter { $0.resumeTokens.contains { tokenKey($0) == key } }
            return owners.count == 1
        }
    }

    static func sharedFlags() -> [String] {
        var count: [String: Int] = [:]
        for runtime in AIRuntime.allCases {
            for token in runtime.resumeTokens {
                if case .flag(let flag) = token {
                    count[flag, default: 0] += 1
                }
            }
        }
        return count.compactMap { $0.value > 1 ? $0.key : nil }
    }

    static func tokenKey(_ token: ResumeToken) -> String {
        switch token {
        case .flag(let flag): "flag:\(flag)"
        case .subcommand(let name): "sub:\(name)"
        }
    }

    static func valueAfterFlags(tokens: [String], flags: [String]) -> String? {
        for flag in flags {
            if let id = valueAfterFlag(tokens: tokens, flag: flag) { return id }
        }
        return nil
    }

    static func valueAfterFlag(tokens: [String], flag: String) -> String? {
        var i = 0
        while i < tokens.count {
            let t = tokens[i]
            if t == flag {
                guard i + 1 < tokens.count else { return nil }
                let id = tokens[i + 1]
                return isUsableID(id) ? id : nil
            }
            let prefix = flag + "="
            if t.hasPrefix(prefix) {
                let id = String(t.dropFirst(prefix.count))
                return isUsableID(id) ? id : nil
            }
            i += 1
        }
        return nil
    }

    static func tokenize(_ line: String) -> [String] {
        line.split(omittingEmptySubsequences: true, whereSeparator: \.isWhitespace).map(String.init)
    }

    static func stripEquals(_ s: String) -> String {
        if let i = s.firstIndex(of: "=") { return String(s[s.index(after: i)...]) }
        return s
    }

    public static func isUsableID(_ s: String) -> Bool {
        guard s.count >= 8, !s.hasPrefix("-") else { return false }
        return s.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" || $0 == "."
        }
    }

    static func looksLikeSessionID(_ line: String) -> Bool {
        let tokens = tokenize(line)
        guard tokens.count == 1, let id = tokens.first else { return false }
        return isUsableID(id)
    }
}
