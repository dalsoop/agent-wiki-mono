import Foundation

/// `doc CLAUDE.md` 처럼 **basename / 상대경로** 로 물었을 때 검색 대상을 고른다.
///
/// 예전에는 cwd 에 무조건 붙여 `.bare/CLAUDE.md`(없는 파일)만 보고 "안 물었다"고 했다.
/// basename 이면 후보를 펼치고, 세션 쪽에서는 basename 일치도 허용한다.
public enum DocPathQuery {
    public struct Resolve: Sendable, Equatable {
        /// 절대 경로 후보(존재 확인된 것만, 없으면 basename-only 매칭에 의존).
        public let candidates: [String]
        /// 입력이 경로 구분자 없는 basename 인가.
        public let basenameOnly: Bool
        /// 비교용 basename (`CLAUDE.md`).
        public let basename: String
        /// 사람이 읽을 해석 메모.
        public let note: String?

        public init(candidates: [String], basenameOnly: Bool, basename: String, note: String?) {
            self.candidates = candidates
            self.basenameOnly = basenameOnly
            self.basename = basename
            self.note = note
        }
    }

    public static func resolve(
        _ raw: String,
        cwd: String,
        home: String = NSHomeDirectory(),
        fm: FileManager = .default
    ) -> Resolve {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = (trimmed as NSString).lastPathComponent
        let basenameOnly = !trimmed.contains("/")
        var candidates: [String] = []
        var seen = Set<String>()

        func add(_ path: String) {
            let n = (path as NSString).standardizingPath
            guard !seen.contains(n) else { return }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: n, isDirectory: &isDir), !isDir.boolValue else { return }
            seen.insert(n)
            candidates.append(n)
        }

        if trimmed.hasPrefix("/") {
            add(trimmed)
        } else if trimmed.hasPrefix("~/") {
            add(home + String(trimmed.dropFirst(1)))
        } else {
            add(cwd + "/" + trimmed)
        }

        // basename 질의: 흔한 지침 위치 + bare 옆 main/ 를 후보로 펼친다.
        if basenameOnly, base.hasSuffix(".md") {
            add(home + "/.claude/" + base)
            add(home + "/.codex/" + base)
            add(home + "/.grok/" + base)
            // cwd 상향
            var dir = (cwd as NSString).standardizingPath
            var hops = 0
            while !dir.isEmpty, dir != "/", hops < 8 {
                add(dir + "/" + base)
                add(dir + "/.claude/" + base)
                let parent = (dir as NSString).deletingLastPathComponent
                if parent == dir { break }
                dir = parent
                hops += 1
            }
            // bare + worktree mono
            let normCwd = (cwd as NSString).standardizingPath
            if (normCwd as NSString).lastPathComponent == ".bare" {
                let repo = (normCwd as NSString).deletingLastPathComponent
                add(repo + "/main/" + base)
                add(repo + "/" + base)
            }
        }

        let note: String?
        if basenameOnly {
            note = candidates.isEmpty
                ? "basename 매칭(세션 카드 경로 끝이름) — 디스크 후보 없음"
                : "후보 \(candidates.count)경로 + basename 매칭"
        } else if candidates.isEmpty {
            note = "경로가 디스크에 없음 — 세션 로그 절대경로 정확 일치만 시도"
        } else {
            note = nil
        }

        return Resolve(
            candidates: candidates,
            basenameOnly: basenameOnly,
            basename: base,
            note: note
        )
    }

    /// 카드 안 경로가 질의와 맞는가.
    public static func matches(path: String, resolve: Resolve) -> Bool {
        let n = (path as NSString).standardizingPath
        if resolve.candidates.contains(n) { return true }
        if resolve.basenameOnly {
            return (n as NSString).lastPathComponent == resolve.basename
        }
        // 상대/절대 한 경로 질의인데 후보에 없을 때 — 끝이름+suffix 느슨 매칭 금지
        // (오탐 큼). 정확 일치만.
        return n == (resolve.candidates.first ?? "")
    }
}
