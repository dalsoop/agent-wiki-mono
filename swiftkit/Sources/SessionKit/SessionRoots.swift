import FastDiskIOKit
import Foundation

/// Where Claude/Codex/Grok leave their session transcripts, and how to enumerate them.
/// Extracted from the discovery code duplicated across agent-session-replay,
/// agent-fleet-map, agent-deck, and mcp-manager. Apps keep their own event
/// semantics; SessionKit owns only "find the files, read a line, pull a field".
public enum SessionRoots {
    public static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    public static var claudeProjects: URL { home.appendingPathComponent(".claude/projects", isDirectory: true) }
    public static var codexSessions: URL { home.appendingPathComponent(".codex/sessions", isDirectory: true) }
    public static var grokSessions: URL { home.appendingPathComponent(".grok/sessions", isDirectory: true) }
    /// Antigravity CLI(`agy`)의 세션 저장소. jsonl 이 아니라 sqlite 목록 + conversations/<id>.db
    /// 전사본이라 `enumerateJSONL` 에는 배선하지 않는다 — AntigravitySessionReader 가 직접 읽는다.
    public static var antigravityHome: URL { home.appendingPathComponent(".gemini/antigravity-cli", isDirectory: true) }
    public static var antigravityConversations: URL { antigravityHome.appendingPathComponent("conversations", isDirectory: true) }
    public static var antigravitySummariesDB: URL { antigravityHome.appendingPathComponent("conversation_summaries.db") }
    /// codex thread-name index (id → thread_name). Two apps used different paths;
    /// both are checked so callers don't have to guess.
    public static var codexSessionIndexCandidates: [URL] {
        [codexSessions.appendingPathComponent("session_index.jsonl"),
         home.appendingPathComponent(".codex/session_index.jsonl")]
    }

    public static var codexSessionIndex: URL? {
        codexSessionIndexCandidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    public typealias Runtime = AIRuntime

    /// One discovered transcript file with cheap metadata (no content read).
    public struct File: Sendable, Equatable {
        public var url: URL
        public var runtime: Runtime
        public var modifiedAt: Date
        public var sizeBytes: Int
        public init(url: URL, runtime: Runtime, modifiedAt: Date, sizeBytes: Int) {
            self.url = url; self.runtime = runtime; self.modifiedAt = modifiedAt; self.sizeBytes = sizeBytes
        }
    }

    /// Enumerate `.jsonl` transcripts under the requested runtimes' roots, newest-first.
    /// - Parameters:
    ///   - runtimes: which roots to walk. **Walk only what you need** — `~/.grok/sessions` alone
    ///     holds 10만+ files, and walking it to answer a Claude-only question cost 12초 per call
    ///     (실측 2026-09-03, `agent-session-context-ledger status --tool claude`).
    ///   - minSize: skip files smaller than this ("empty shell" filter). Default 0.
    ///   - since: only files modified at/after this instant (recency filter). Nil = all.
    ///   - includeClaudeSubagents: include `subagents/agent-*.jsonl` sidechains
    ///     (default false — most apps list them via drill-in, not the top list).
    public static func enumerateJSONL(runtimes: Set<Runtime>,
                                      minSize: Int = 0, since: Date? = nil,
                                      includeClaudeSubagents: Bool = false) -> [File] {
        var out: [File] = []
        if runtimes.contains(.claude) {
            out += includeClaudeSubagents
                ? scan(root: claudeProjects, runtime: .claude, minSize: minSize, since: since,
                       includeClaudeSubagents: true)
                : scanClaudeTopLevel(root: claudeProjects, minSize: minSize, since: since)
        }
        if runtimes.contains(.codex) {
            out += scan(root: codexSessions, runtime: .codex, minSize: minSize, since: since,
                        includeClaudeSubagents: true)   // codex has no claude-style sidechain dir
        }
        if runtimes.contains(.grok) {
            out += scanGrok(root: grokSessions, minSize: minSize, since: since)
        }
        return out.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    /// All three runtimes. Prefer `enumerateJSONL(runtimes:)` when the caller filters afterwards.
    public static func enumerateJSONL(minSize: Int = 0, since: Date? = nil,
                                      includeClaudeSubagents: Bool = false) -> [File] {
        enumerateJSONL(runtimes: [.claude, .codex, .grok], minSize: minSize, since: since,
                       includeClaudeSubagents: includeClaudeSubagents)
    }

    static func scan(root: URL, runtime: Runtime, minSize: Int, since: Date?,
                     includeClaudeSubagents: Bool) -> [File] {
        let entries = FastDirectoryScanner.scanEntries(in: root.path)
        var files: [File] = []
        for entry in entries {
            guard !entry.isDirectory else { continue }
            guard !entry.name.hasPrefix(".") else { continue }
            guard entry.name.hasSuffix(".jsonl") else { continue }
            if runtime == .codex, !entry.name.hasPrefix("rollout-") { continue }
            let url = URL(fileURLWithPath: entry.path)
            if runtime == .claude, !includeClaudeSubagents,
               url.deletingLastPathComponent().lastPathComponent == "subagents" { continue }
            let size = Int(entry.size)
            if size < minSize { continue }
            let mtime = entry.modifiedAt
            if let since, mtime < since { continue }
            files.append(File(url: url, runtime: runtime, modifiedAt: mtime, sizeBytes: size))
        }
        return files
    }

    /// Claude top-level sessions sit exactly at `<root>/<project-slug>/<uuid>.jsonl`. Sidechains
    /// (`<uuid>/subagents/*.jsonl`) and memory dirs live deeper; the recursive walk visited
    /// 8,400 entries to find 1,900 sessions (실측 2026-09-03). When sidechains are not wanted,
    /// list two levels and stop.
    public static func scanClaudeTopLevel(root: URL, minSize: Int, since: Date?) -> [File] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let projects = contents(ofDirectory: root, keys: [.isDirectoryKey]) else { return [] }
        var files: [File] = []
        for project in projects where isDirectory(project) {
            guard let entries = contents(ofDirectory: project, keys: keys) else { continue }
            for url in entries where url.pathExtension == "jsonl" {
                guard let v = resourceValues(of: url, keys: Set(keys)), v.isRegularFile ?? false else { continue }
                let size = v.fileSize ?? 0
                if size < minSize { continue }
                let mtime = v.contentModificationDate ?? .distantPast
                if let since, mtime < since { continue }
                files.append(File(url: url, runtime: .claude, modifiedAt: mtime, sizeBytes: size))
            }
        }
        return files
    }

    /// Grok layout is fixed two levels deep: `<root>/<encoded-cwd>/<session-id>/updates.jsonl`.
    /// Address the file directly instead of walking the tree — each session directory also
    /// carries chat_history/events/rewind logs and lock files (실측 27 files per session).
    public static func scanGrok(root: URL, minSize: Int, since: Date?) -> [File] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        // 루트가 없으면(grok 미설치) 빈 목록이 답이다 — 에러가 아니다.
        guard let groups = contents(ofDirectory: root, keys: [.isDirectoryKey, .contentModificationDateKey]) else { return [] }
        var files: [File] = []
        for group in groups where Self.isDirectory(group) {
            if let since {
                let groupMTime = resourceValues(of: group, keys: [.contentModificationDateKey])?.contentModificationDate ?? .distantPast
                if groupMTime < since { continue }
            }
            guard let sessions = contents(ofDirectory: group, keys: [.isDirectoryKey]) else { continue }
            for session in sessions where Self.isDirectory(session) {
                let url = session.appendingPathComponent("updates.jsonl")
                // updates.jsonl 이 없으면 세션 디렉터리가 아니다(prompt_history 같은 그룹 파일).
                guard let v = resourceValues(of: url, keys: Set(keys)), v.isRegularFile ?? false else { continue }
                let size = v.fileSize ?? 0
                if size < minSize { continue }
                let mtime = v.contentModificationDate ?? .distantPast
                if let since, mtime < since { continue }
                files.append(File(url: url, runtime: .grok, modifiedAt: mtime, sizeBytes: size))
            }
        }
        return files
    }

    private static func isDirectory(_ url: URL) -> Bool {
        resourceValues(of: url, keys: [.isDirectoryKey])?.isDirectory ?? false
    }

    // MARK: - best-effort 파일시스템 프로브
    //
    // 세션 발견은 best-effort 다: 권한이 없거나 사라진 항목은 **목록에서 빠지는 게 정답**이고,
    // 호출자마다 do/catch 를 반복하면 그 의도가 흐려진다. 삼키는 자리를 여기 한 곳에 모은다.

    /// 속성을 못 읽으면 nil(항목 제외).
    public static func resourceValues(of url: URL, keys: Set<URLResourceKey>) -> URLResourceValues? {
        do {
            return try url.resourceValues(forKeys: keys)
        } catch {
            return nil  // 권한 없음·경쟁 삭제 — 목록에서 뺀다.
        }
    }

    /// 디렉터리를 못 읽으면 nil(루트 없음 = 빈 목록, 권한 없는 그룹 = 건너뜀).
    public static func contents(ofDirectory url: URL, keys: [URLResourceKey] = []) -> [URL]? {
        do {
            return try FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        } catch {
            return nil  // 없거나 권한 없음.
        }
    }

    /// 경로 문자열판 `contents(ofDirectory:)`.
    public static func contents(ofDirectoryPath path: String) -> [String]? {
        do {
            return try FileManager.default.contentsOfDirectory(atPath: path)
        } catch {
            return nil  // 없거나 권한 없음.
        }
    }

    /// 파일 mtime. 없으면 nil.
    public static func modificationDate(atPath path: String) -> Date? {
        do {
            return try FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date
        } catch {
            return nil  // 아직 안 만들어진 로그.
        }
    }
}
