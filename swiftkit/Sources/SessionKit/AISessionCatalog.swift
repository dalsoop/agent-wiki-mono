import Foundation

/// One locally persisted AI conversation, normalized across runtime-specific
/// layouts. `transcriptURL` always points at the append-only conversation log.
public struct AISessionRecord: Sendable, Equatable, Identifiable {
    public let id: String
    public let runtime: AIRuntime
    public let cwd: String?
    public let title: String?
    public let firstPrompt: String?
    public let transcriptURL: URL
    public let metadataURL: URL?
    public let modifiedAt: Date
    public let sizeBytes: Int
    public let isSubagent: Bool
    public let parentID: String?
    public let nickname: String?

    public struct Files: Sendable, Equatable {
        public var transcriptURL: URL
        public var metadataURL: URL?
        public var modifiedAt: Date
        public var sizeBytes: Int

        public init(transcriptURL: URL, metadataURL: URL?, modifiedAt: Date, sizeBytes: Int) {
            self.transcriptURL = transcriptURL
            self.metadataURL = metadataURL
            self.modifiedAt = modifiedAt
            self.sizeBytes = sizeBytes
        }
    }

    public struct Lineage: Sendable, Equatable {
        public var isSubagent: Bool
        public var parentID: String?
        public var nickname: String?

        public init(isSubagent: Bool = false, parentID: String? = nil, nickname: String? = nil) {
            self.isSubagent = isSubagent
            self.parentID = parentID
            self.nickname = nickname
        }
    }

    public init(
        id: String, runtime: AIRuntime, cwd: String?, title: String?,
        firstPrompt: String?, files: Files, lineage: Lineage = Lineage()
    ) {
        self.id = id
        self.runtime = runtime
        self.cwd = cwd
        self.title = title
        self.firstPrompt = firstPrompt
        self.transcriptURL = files.transcriptURL
        self.metadataURL = files.metadataURL
        self.modifiedAt = files.modifiedAt
        self.sizeBytes = files.sizeBytes
        self.isSubagent = lineage.isSubagent
        self.parentID = lineage.parentID
        self.nickname = lineage.nickname
    }
}

/// Shared local-session discovery for every AI-facing Swift app.
///
/// Layouts:
/// - Claude: `~/.claude/projects/**/*.jsonl`
/// - Codex: `~/.codex/sessions/**/rollout-*.jsonl`
/// - Grok: `~/.grok/sessions/<encoded-cwd>/<id>/{summary.json,updates.jsonl}`
/// - Antigravity: `~/.gemini/antigravity-cli/conversation_summaries.db` (sqlite 목록)
///   + `conversations/<id>.db` (전사본)
public struct AISessionCatalog: Sendable {
    public let claudeRoot: URL
    public let codexRoot: URL
    public let grokRoot: URL
    public let agyHome: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                environment: [String: String] = ProcessInfo.processInfo.environment) {
        let claudeBase = environment["CLAUDE_CONFIG_DIR"].map(URL.init(fileURLWithPath:))
            ?? home.appendingPathComponent(".claude", isDirectory: true)
        let codexBase = environment["CODEX_HOME"].map(URL.init(fileURLWithPath:))
            ?? home.appendingPathComponent(".codex", isDirectory: true)
        let grokBase = environment["GROK_HOME"].map(URL.init(fileURLWithPath:))
            ?? home.appendingPathComponent(".grok", isDirectory: true)
        claudeRoot = claudeBase.appendingPathComponent("projects", isDirectory: true)
        codexRoot = codexBase.appendingPathComponent("sessions", isDirectory: true)
        grokRoot = grokBase.appendingPathComponent("sessions", isDirectory: true)
        agyHome = home.appendingPathComponent(".gemini/antigravity-cli", isDirectory: true)
    }

    public init(claudeRoot: URL, codexRoot: URL, grokRoot: URL,
                agyHome: URL? = nil) {
        self.claudeRoot = claudeRoot
        self.codexRoot = codexRoot
        self.grokRoot = grokRoot
        self.agyHome = agyHome
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent(".gemini/antigravity-cli", isDirectory: true)
    }

    public func discover(minSize: Int = 0, includeClaudeSubagents: Bool = false,
                         modifiedAfter: Date? = nil,
                         limitPerRuntime: Int? = nil) -> [AISessionRecord] {
        var all: [AISessionRecord] = []
        all += limited(scanClaude(minSize: minSize,
                                  includeSubagents: includeClaudeSubagents,
                                  modifiedAfter: modifiedAfter,
                                  limit: limitPerRuntime),
                       to: limitPerRuntime)
        all += limited(scanCodex(minSize: minSize,
                                 modifiedAfter: modifiedAfter,
                                 limit: limitPerRuntime),
                       to: limitPerRuntime)
        all += limited(scanGrok(minSize: minSize,
                                modifiedAfter: modifiedAfter,
                                limit: limitPerRuntime),
                       to: limitPerRuntime)
        all += limited(scanAntigravity(modifiedAfter: modifiedAfter,
                                       limit: limitPerRuntime),
                       to: limitPerRuntime)
        return all.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    private func limited(_ records: [AISessionRecord], to limit: Int?) -> [AISessionRecord] {
        let sorted = records.sorted { $0.modifiedAt > $1.modifiedAt }
        guard let limit else { return sorted }
        return Array(sorted.prefix(limit))
    }

    private func scanClaude(minSize: Int, includeSubagents: Bool,
                            modifiedAfter: Date?, limit: Int?) -> [AISessionRecord] {
        recentCandidates(files(under: claudeRoot) { url in
            guard url.pathExtension == "jsonl" else { return false }
            return includeSubagents || !url.pathComponents.contains("subagents")
        }, minSize: minSize, modifiedAfter: modifiedAfter, limit: limit).compactMap {
            url, modified, size in
            let head = SessionHead.read(url)
            let meta = SessionMeta.claude(head: head)
            let isSubagent = head.contains(#""isSidechain":true"#)
                || url.pathComponents.contains("subagents")
            return AISessionRecord(
                id: url.deletingPathExtension().lastPathComponent,
                runtime: .claude,
                cwd: meta.cwd,
                title: meta.firstPrompt,
                firstPrompt: meta.firstPrompt,
                files: .init(transcriptURL: url, metadataURL: nil, modifiedAt: modified, sizeBytes: size),
                lineage: .init(isSubagent: isSubagent)
            )
        }
    }

    private func scanCodex(minSize: Int, modifiedAfter: Date?,
                           limit: Int?) -> [AISessionRecord] {
        let titles = codexTitles()
        return recentCandidates(files(under: codexRoot) { url in
            url.pathExtension == "jsonl" && url.lastPathComponent.hasPrefix("rollout-")
        }, minSize: minSize, modifiedAfter: modifiedAfter, limit: limit).compactMap {
            url, modified, size in
            let head = SessionHead.read(url)
            let meta = SessionMeta.codex(head: head)
            let id = meta.id ?? SessionIdent.codexUUID(fromFileName: url.lastPathComponent)
                ?? url.deletingPathExtension().lastPathComponent
            return AISessionRecord(
                id: id,
                runtime: .codex,
                cwd: meta.cwd,
                title: titles[id],
                firstPrompt: SessionMeta.codexFirstPrompt(head: head),
                files: .init(transcriptURL: url, metadataURL: nil, modifiedAt: modified, sizeBytes: size),
                lineage: .init(
                    isSubagent: meta.parentThreadID != nil || head.contains(#""thread_source":"subagent""#),
                    parentID: meta.parentThreadID,
                    nickname: meta.nickname
                )
            )
        }
    }

    private func scanGrok(minSize: Int, modifiedAfter: Date?,
                          limit: Int?) -> [AISessionRecord] {
        let candidates = files(under: grokRoot) {
            $0.lastPathComponent == "summary.json"
        }.compactMap { summaryURL, summaryModified, _
            -> (URL, Date, URL, Date, Int)? in
            let dir = summaryURL.deletingLastPathComponent()
            let transcript = dir.appendingPathComponent("updates.jsonl")
            guard let values = try? transcript.resourceValues(
                forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]),
                  values.isRegularFile == true else { return nil }
            let modified = values.contentModificationDate ?? summaryModified
            return (summaryURL, summaryModified, transcript, modified, values.fileSize ?? 0)
        }
        let recent = candidates
            .filter { candidate in
                candidate.4 >= minSize
                    && modifiedAfter.map { candidate.3 >= $0 } != false
            }
            .sorted { $0.3 > $1.3 }
        let selected = candidateLimit(limit).map { Array(recent.prefix($0)) } ?? recent

        return selected.compactMap { summaryURL, summaryModified, transcript, modified, size in
            guard let text = try? String(contentsOf: summaryURL, encoding: .utf8),
                  let meta = SessionMeta.grok(summary: text) else { return nil }
            let dir = summaryURL.deletingLastPathComponent()
            let firstPrompt = SessionMeta.grokFirstPrompt(head: SessionHead.read(transcript))
            return AISessionRecord(
                id: meta.id ?? dir.lastPathComponent,
                runtime: .grok,
                cwd: meta.cwd,
                title: meta.title ?? meta.summary,
                firstPrompt: firstPrompt,
                files: .init(
                    transcriptURL: transcript,
                    metadataURL: summaryURL,
                    modifiedAt: modified == .distantPast ? (meta.updatedAt ?? summaryModified) : modified,
                    sizeBytes: size
                ),
                lineage: .init(
                    isSubagent: meta.parentSessionID != nil,
                    parentID: meta.parentSessionID,
                    nickname: meta.agentName
                )
            )
        }
    }

    /// Antigravity 목록은 jsonl 파일 훑기가 아니라 summaries db SELECT 다.
    /// sizeBytes 는 전사본 db 크기(없으면 0).
    private func scanAntigravity(modifiedAfter: Date?, limit: Int?) -> [AISessionRecord] {
        let summariesURL = agyHome.appendingPathComponent("conversation_summaries.db")
        guard FileManager.default.fileExists(atPath: summariesURL.path),
              let db = try? SQLiteReadOnly(path: summariesURL.path) else { return [] }
        let rows = (try? db.rows(
            "SELECT conversation_id, title, preview, step_count, last_user_input_time, "
                + "last_modified_time, workspace_uris, killed, parent_conversation_id, agent_name "
                + "FROM conversation_summaries WHERE killed = 0"
        )) ?? []
        var records: [AISessionRecord] = []
        for row in rows {
            guard row.count >= 7, let id = row[0].text else { continue }
            let inputAt = SessionMeta.antigravityDate(row[4].text)
            let modifiedAt = SessionMeta.antigravityDate(row[5].text) ?? inputAt
                ?? .distantPast
            if modifiedAfter.map({ modifiedAt >= $0 }) == false { continue }
            let transcript = agyHome.appendingPathComponent("conversations/\(id).db")
            let size = (try? transcript.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            records.append(AISessionRecord(
                id: id,
                runtime: .agy,
                cwd: SessionMeta.antigravityCWD(fromWorkspaceURIs: row.count > 6 ? row[6].text : nil),
                title: row[1].text,
                firstPrompt: row[2].text,
                files: .init(transcriptURL: transcript, metadataURL: summariesURL,
                             modifiedAt: modifiedAt, sizeBytes: size),
                lineage: .init(
                    isSubagent: row.count > 8 && !(row[8].text ?? "").isEmpty,
                    parentID: row.count > 8 ? row[8].text : nil,
                    nickname: row.count > 9 ? row[9].text : nil
                )
            ))
        }
        // 요청한 개수를 정렬 후 자른다(db 쿼리에 LIMIT 이 없으므로 여기서).
        let sorted = records.sorted { $0.modifiedAt > $1.modifiedAt }
        guard let limit else { return sorted }
        return Array(sorted.prefix(limit))
    }

    private func codexTitles() -> [String: String] {
        let candidates = [codexRoot.appendingPathComponent("session_index.jsonl"),
                          codexRoot.deletingLastPathComponent().appendingPathComponent("session_index.jsonl")]
        guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else { return [:] }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        return SessionMeta.codexIndex(text: text)
    }

    private func files(under root: URL, matching: (URL) -> Bool) -> [(URL, Date, Int)] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]
        ) else { return [] }
        var result: [(URL, Date, Int)] = []
        for case let url as URL in enumerator where matching(url) {
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { continue }
            result.append((url, values.contentModificationDate ?? .distantPast, values.fileSize ?? 0))
        }
        return result
    }

    private func recentCandidates(
        _ candidates: [(URL, Date, Int)],
        minSize: Int,
        modifiedAfter: Date?,
        limit: Int?
    ) -> [(URL, Date, Int)] {
        let recent = candidates
            .filter { candidate in
                candidate.2 >= minSize
                    && modifiedAfter.map { candidate.1 >= $0 } != false
            }
            .sorted { $0.1 > $1.1 }
        guard let count = candidateLimit(limit) else { return recent }
        return Array(recent.prefix(count))
    }

    /// 일부 손상 파일이 있어도 요청한 개수를 채울 수 있게 메타데이터
    /// 후보는 최종 제한보다 여유 있게 읽는다.
    private func candidateLimit(_ limit: Int?) -> Int? {
        guard let limit else { return nil }
        guard limit > 0 else { return 0 }
        return limit > Int.max / 4 ? Int.max : limit * 4
    }
}
