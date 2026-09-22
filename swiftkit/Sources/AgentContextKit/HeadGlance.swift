import Foundation
import AgentSessionKit

/// 세션 카드 맨 위에 붙는 **머리 한 줄 요약**.
/// 주입 목록·/tmp 문서 나열만 보면 "지금 머리가 코드 작업인지 문서 작업인지"가
/// 안 보인다 — 도구 비율 + 코드 포커스 + 임시문서 오염을 한 블록으로 압축한다.
public struct HeadGlance: Sendable, Codable, Equatable {
    /// `bash-heavy` · `edit-heavy` · `read-heavy` · `mixed` · `quiet`
    public let mode: String
    /// 한국어 한 줄 (CLI·GUI 공통).
    public let blurb: String
    public let bashCalls: Int
    public let readCalls: Int
    public let editCalls: Int
    public let totalToolCalls: Int
    public let injectedDocCount: Int
    public let injectedApproxTokens: Int
    public let injectionObserved: Bool
    /// `touched` 중 내구(비임시) 문서 수.
    public let durableDocCount: Int
    /// `touched` 중 임시(/tmp 등) 문서 수 — 크면 문서 섹션이 오염된 것.
    public let ephemeralDocCount: Int
    /// 코드 포커스 상위 건수(카드에 실은 개수).
    public let codeFocusCount: Int
    public let truncated: Bool

    public struct ToolCalls: Sendable, Equatable {
        public let bashCalls: Int
        public let readCalls: Int
        public let editCalls: Int
        public let totalToolCalls: Int

        public init(bashCalls: Int, readCalls: Int, editCalls: Int, totalToolCalls: Int) {
            self.bashCalls = bashCalls
            self.readCalls = readCalls
            self.editCalls = editCalls
            self.totalToolCalls = totalToolCalls
        }
    }

    public struct DocStats: Sendable, Equatable {
        public let injectedDocCount: Int
        public let injectedApproxTokens: Int
        public let injectionObserved: Bool
        public let durableDocCount: Int
        public let ephemeralDocCount: Int
        public let codeFocusCount: Int

        public init(
            injectedDocCount: Int, injectedApproxTokens: Int, injectionObserved: Bool,
            durableDocCount: Int, ephemeralDocCount: Int, codeFocusCount: Int
        ) {
            self.injectedDocCount = injectedDocCount
            self.injectedApproxTokens = injectedApproxTokens
            self.injectionObserved = injectionObserved
            self.durableDocCount = durableDocCount
            self.ephemeralDocCount = ephemeralDocCount
            self.codeFocusCount = codeFocusCount
        }
    }

    public init(mode: String, blurb: String, tools: ToolCalls, docs: DocStats, truncated: Bool) {
        self.mode = mode
        self.blurb = blurb
        self.bashCalls = tools.bashCalls
        self.readCalls = tools.readCalls
        self.editCalls = tools.editCalls
        self.totalToolCalls = tools.totalToolCalls
        self.injectedDocCount = docs.injectedDocCount
        self.injectedApproxTokens = docs.injectedApproxTokens
        self.injectionObserved = docs.injectionObserved
        self.durableDocCount = docs.durableDocCount
        self.ephemeralDocCount = docs.ephemeralDocCount
        self.codeFocusCount = docs.codeFocusCount
        self.truncated = truncated
    }
}

/// 지침(md) 이 아닌 **코드/설정 파일** 포커스. `DocumentTrace` 는 의도적으로
/// md·txt 만 세므로, Bash 로 소스를 긁는 세션은 문서 섹션이 비거나 /tmp 만 가득 찬다.
/// 머리 안을 보려면 digest.files 의 비문서 상위 경로가 필요하다.
public struct CodeFocus: Sendable, Codable, Equatable {
    public let path: String
    public let hits: Int
    public let kind: String

    public init(path: String, hits: Int, kind: String) {
        self.path = path
        self.hits = hits
        self.kind = kind
    }
}

public enum HeadAnalysis {
    /// 코드로 볼 확장자. 문서(md/txt) 는 `DocumentTrace` 축에 맡긴다.
    public static let codeExtensions: Set<String> = [
        "swift", "m", "h", "mm", "c", "cc", "cpp", "hpp",
        "ts", "tsx", "js", "jsx", "mjs", "cjs",
        "py", "rb", "go", "rs", "java", "kt", "kts",
        "json", "yml", "yaml", "toml", "plist",
        "sh", "zsh", "bash", "rhai",
    ]

    public static func codeFocus(from digest: SessionDigest, limit: Int = 12) -> [CodeFocus] {
        digest.files
            .compactMap { path, hits -> CodeFocus? in
                let kind = (path as NSString).pathExtension.lowercased()
                guard codeExtensions.contains(kind) else { return nil }
                // 임시 산출물 경로는 코드 포커스에서도 뒤로 민다(완전 제외는 안 함).
                return CodeFocus(path: path, hits: hits, kind: kind)
            }
            .sorted { a, b in
                let ae = DocumentTrace.isEphemeral(a.path), be = DocumentTrace.isEphemeral(b.path)
                if ae != be { return !ae && be }
                if a.hits != b.hits { return a.hits > b.hits }
                return a.path < b.path
            }
            .prefix(limit)
            .map { $0 }
    }

    public static func glance(
        tools: [String: Int],
        injected: [InjectedDoc],
        injectedApproxTokens: Int,
        injectionObservable: Bool,
        touched: [TouchedDoc],
        codeFocus: [CodeFocus],
        truncated: Bool
    ) -> HeadGlance {
        func n(_ key: String) -> Int { tools[key] ?? 0 }
        // 런타임마다 이름이 다르다. Claude 는 Bash/Read, Grok 는 run_terminal_command/read_file.
        let bash = n("Bash") + n("bash") + n("Shell") + n("shell")
            + n("run_terminal_command")
        let read = n("Read") + n("read") + n("read_file")
        let edit = n("Edit") + n("edit") + n("Write") + n("write") + n("MultiEdit")
            + n("search_replace")
        let total = tools.values.reduce(0, +)
        let durable = touched.filter { !DocumentTrace.isEphemeral($0.path) }.count
        let ephemeral = touched.count - durable

        let mode: String
        if total == 0 {
            mode = "quiet"
        } else if bash >= max(read, edit) * 2 && bash >= 10 {
            mode = "bash-heavy"
        } else if edit >= max(bash, read) && edit >= 5 {
            mode = "edit-heavy"
        } else if read >= max(bash, edit) && read >= 5 {
            mode = "read-heavy"
        } else {
            mode = "mixed"
        }

        var parts: [String] = []
        switch mode {
        case "bash-heavy": parts.append("셸 중심(코드·grep 작업 가능 — 문서는 /tmp 에 묻힐 수 있음)")
        case "edit-heavy": parts.append("편집 중심")
        case "read-heavy": parts.append("읽기 중심")
        case "quiet": parts.append("도구 호출 거의 없음")
        default: parts.append("혼합 작업")
        }
        if !injectionObservable {
            parts.append("주입은 재구성")
        }
        if ephemeral > durable && ephemeral >= 3 {
            parts.append("문서 목록 임시파일 오염(\(ephemeral)건)")
        }
        if codeFocus.isEmpty && bash > 20 {
            parts.append("코드 포커스 없음(창 잘림 가능)")
        }
        if truncated {
            parts.append("일부만 읽음")
        }

        return HeadGlance(
            mode: mode,
            blurb: parts.joined(separator: " · "),
            tools: .init(bashCalls: bash, readCalls: read, editCalls: edit, totalToolCalls: total),
            docs: .init(
                injectedDocCount: injected.count,
                injectedApproxTokens: injectedApproxTokens,
                injectionObserved: injectionObservable,
                durableDocCount: durable,
                ephemeralDocCount: ephemeral,
                codeFocusCount: codeFocus.count
            ),
            truncated: truncated
        )
    }
}
