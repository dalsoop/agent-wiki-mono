import Foundation
import AgentSessionKit
import StateRootKit

/// 세션이 **실제로 손댄 문서**를 뽑는다.
///
/// 명시적 `Read` 만 보면 대부분을 놓친다. 최근 6세션 실측 도구 분포가
/// Bash 267 · Agent 24 · Write 20 · Edit 16 · Read 5 였다 — 문서 접근의 압도적 다수가
/// 셸 명령 문자열 안에 있다. 그래서 `digest.commands` 를 파싱하는 게 이 타입의 본체다.
public enum DocumentTrace {
    /// 문서로 칠 확장자. 코드 파일은 이 앱의 객체가 아니다(그건 세션 리플레이).
    public static let docExtensions: Set<String> = ["md", "mdx", "markdown", "txt", "rst", "adoc"]

    /// 셸 토큰이 파일 경로처럼 보이는가를 판정할 때 잘라낼 껍데기.
    private static let trimChars = CharacterSet(charactersIn: "'\"`,;:()[]{}<>|&")

    public static func touched(digest: SessionDigest) -> [TouchedDoc] {
        let cwd = digest.ref.cwd
        var hits: [String: (Int, Provenance)] = [:]

        func add(_ raw: String, _ prov: Provenance) {
            guard let path = normalize(raw, cwd: cwd) else { return }
            if let existing = hits[path] {
                // 명시적 read 가 shell 추정을 이긴다 — 더 강한 증거이므로.
                let prov = existing.1 == .read ? .read : prov
                hits[path] = (existing.0 + 1, prov)
            } else {
                hits[path] = (1, prov)
            }
        }

        for (path, count) in digest.files where isDoc(path) {
            for _ in 0..<max(1, count) { add(path, .read) }
        }
        for cmd in digest.commands {
            for token in docTokens(in: cmd) { add(token, .shell) }
        }

        return hits
            .map { TouchedDoc(path: $0.key, provenance: $0.value.1, hits: $0.value.0, kind: ext($0.key)) }
            .sorted(by: rankTouched)
    }

    /// 임시 경로(/tmp · scratchpad …)는 머리를 가린다 — Gujo 세션 실측에서
    /// 읽은 문서 36건이 전부 `/tmp/*.txt` 로 채워져 지침·코드 포커스가 안 보였다.
    /// 정렬 키: 내구 문서 우선 → 명시적 read 우선 → hits → path.
    public static func isEphemeral(_ path: String) -> Bool {
        if path.hasPrefix("/tmp/") || path.hasPrefix("/private/tmp/") { return true }
        if path.hasPrefix("/var/folders/") { return true }
        if path.contains("/scratchpad/") { return true }
        // Claude 에이전트 작업 스크래치 (…/projects/…/scratchpad/…)
        if path.contains("/private/tmp/claude-") { return true }
        return false
    }

    public static func rankTouched(_ a: TouchedDoc, _ b: TouchedDoc) -> Bool {
        let ae = isEphemeral(a.path), be = isEphemeral(b.path)
        if ae != be { return !ae && be }
        let ar = a.provenance == .read ? 1 : 0
        let br = b.provenance == .read ? 1 : 0
        if ar != br { return ar > br }
        if a.hits != b.hits { return a.hits > b.hits }
        return a.path < b.path
    }

    /// 셸 명령 문자열에서 문서 경로처럼 보이는 토큰을 뽑는다.
    ///
    /// 정밀도보다 재현율을 택했다 — 놓친 문서는 "안 읽혔다"는 **틀린 결론**을 만들지만,
    /// 잘못 잡힌 토큰은 경로 정규화 단계에서 존재하지 않는 파일로 걸러진다.
    public static func docTokens(in command: String) -> [String] {
        var out: [String] = []
        for rawToken in command.components(separatedBy: .whitespacesAndNewlines) {
            let token = rawToken.trimmingCharacters(in: trimChars)
            guard !token.isEmpty, isDoc(token) else { continue }
            // 글롭·와일드카드는 개별 문서로 환원할 수 없다.
            guard !token.contains("*"), !token.contains("?") else { continue }
            out.append(token)
        }
        return out
    }

    static func isDoc(_ path: String) -> Bool { docExtensions.contains(ext(path)) }

    static func ext(_ path: String) -> String {
        (path as NSString).pathExtension.lowercased()
    }

    /// 상대 경로를 cwd 기준 절대 경로로 만들고, 실재하는 파일만 남긴다.
    ///
    /// 실재 확인이 오탐 필터다 — 문서 안에 예시로 적힌 `docs/foo.md` 같은 문자열이
    /// 명령에 섞여 들어와도 여기서 떨어진다. 대가는 그 사이 삭제된 문서를 못 세는 것이고,
    /// 이건 "지금 살아 있는 md 중 뭐가 죽었나" 라는 질문에는 오히려 맞는 동작이다.
    public static func normalize(_ raw: String, cwd: String, fm: FileManager = .default) -> String? {
        var p = raw
        if p == "~" {
            p = StateRootKit.root
        } else if p.hasPrefix("~/") {
            p = StateRootKit.path(String(p.dropFirst(2)))
        }
        if !p.hasPrefix("/") { p = cwd + "/" + p }
        let norm = (p as NSString).standardizingPath
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: norm, isDirectory: &isDir), !isDir.boolValue else { return nil }
        return norm
    }
}
