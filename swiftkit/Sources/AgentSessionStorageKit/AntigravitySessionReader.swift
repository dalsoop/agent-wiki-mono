import Foundation
import SessionKit
import ISO8601DateCodecKit

/// Antigravity CLI(`agy`) 세션 리더.
///
/// 저장 구조 (실측 2026-09-01, agy 1.1.23 · 로컬 65 전사본):
/// ```
/// ~/.gemini/antigravity-cli/
///   conversation_summaries.db      ← 목록(sqlite): id·title·preview·workspace·시각
///   conversations/<id>.db          ← 전사본(sqlite): steps(idx, step_type, metadata, step_payload)
///   history.jsonl                  ← 사용자 입력 이력(display·timestamp·workspace·conversationId)
/// ```
///
/// blob 은 protobuf 비정형 바이트지만 원문 텍스트가 raw UTF-8 로 그대로 섞여 있다(실측).
/// 정식 protobuf 스키마가 공개돼 있지 않아 **문자열 run 추출**로 읽되, 한국어 원문이
/// 유실되지 않게 유효한 멀티바이트 UTF-8 시퀀스도 run 으로 인정한다.
///
/// step_type 실측 지도:
/// - 14: 사용자 발언(payload 에 원문, **2중 저장**이라 중복 제거 필요)
/// - 15: 에이전트 발언
/// - 132: tool call(metadata blob 에 call id·tool 이름·JSON 인자가 가장 깨끗)
/// - 101 / 17 / 23: 기타(무시 — "안다"로 쳐서 드리프트 경보에서 뺀다)
public struct AntigravitySessionReader: Sendable {
    public let root: String

    public init(root: String = NSHomeDirectory() + "/.gemini/antigravity-cli") {
        self.root = root
    }

    public var summariesDBPath: String { root + "/conversation_summaries.db" }

    /// 파서가 아는 step 종류. 여기 없는 값이 나오면 `unknownEvents` 로 세어 드리프트 감지에 쓴다.
    static let knownStepTypes: Set<Int> = [14, 15, 132, 101, 17, 23]

    /// 전사본 한 줄(step) 단위 이벤트. digest·TranscriptReader·LandingMatcher 가 같이 쓰는
    /// 단일 진입점 — protobuf 해석 지식은 여기 한 곳에만 둔다.
    public struct Step: Sendable {
        public let index: Int
        public let type: Int
        /// metadata blob 에서 뽑은 문자열 run.
        public let metadataStrings: [String]
        /// step_payload blob 에서 뽑은 문자열 run.
        public let payloadStrings: [String]
    }
}

// MARK: - 발견

extension AntigravitySessionReader {
    public func discover(limit: Int = 500, since: Date? = nil) -> [SessionRef] {
        guard let db = try? SessionKit.SQLiteReadOnly(path: summariesDBPath) else { return [] }
        let query: String
        if let since {
            let sinceISO = ISO8601DateCodec.format(since)
            query = "SELECT conversation_id, title, preview, step_count, last_user_input_time, "
                + "last_modified_time, workspace_uris, killed "
                + "FROM conversation_summaries "
                + "WHERE (last_modified_time >= '\(sinceISO)' OR last_user_input_time >= '\(sinceISO)') "
                + "ORDER BY last_user_input_time DESC"
        } else {
            query = "SELECT conversation_id, title, preview, step_count, last_user_input_time, "
                + "last_modified_time, workspace_uris, killed "
                + "FROM conversation_summaries ORDER BY last_user_input_time DESC"
        }
        let rows: [[SessionKit.SQLiteReadOnly.Column]]
        do {
            rows = try db.rows(query)
        } catch {
            return []
        }
        var out: [SessionRef] = []
        for row in rows {
            guard row.count >= 8, let id = row[0].text, (row[7].int ?? 0) == 0 else { continue }
            out.append(ref(row: row, id: id))
            if out.count >= limit { break }
        }
        return out.sorted { $0.lastActive > $1.lastActive }
    }

    public func discover(limit: Int) -> [SessionRef] {
        discover(limit: limit, since: nil)
    }

    /// 세션 id 한 건 조회.
    public func find(id: String) -> SessionRef? {
        findPrefix(id: id, limit: 1).first
    }

    /// 접두사로 최대 `limit` 개까지 매치. 정확 일치가 있으면 그것만 반환한다
    /// (SessionIndex.find 의 모호성 규약 유지).
    public func findPrefix(id: String, limit: Int) -> [SessionRef] {
        let needle = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.count >= 8, let db = try? SessionKit.SQLiteReadOnly(path: summariesDBPath)
        else { return [] }
        let rows: [[SessionKit.SQLiteReadOnly.Column]]
        do {
            rows = try db.rows(
                "SELECT conversation_id, title, preview, step_count, last_user_input_time, "
                    + "last_modified_time, workspace_uris, killed "
                    + "FROM conversation_summaries WHERE conversation_id LIKE '" + escaped(needle) + "%'"
            )
        } catch {
            return []
        }
        var hits: [SessionRef] = []
        for row in rows {
            guard row.count >= 8, let sid = row[0].text, (row[7].int ?? 0) == 0 else { continue }
            let r = ref(row: row, id: sid)
            if sid == needle { return [r] }
            hits.append(r)
            if hits.count >= limit { return hits }
        }
        return hits
    }

    /// LIKE 패턴용 최소 이스케이프(사용자가 넣는 id 는 UUID 자리수가 보통이지만 방어).
    private func escaped(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "''")
    }

    private func ref(row: [SessionKit.SQLiteReadOnly.Column], id: String) -> SessionRef {
        let title = row.count > 1 ? row[1].text : nil
        let preview = row.count > 2 ? row[2].text : nil
        let stepCount = row.count > 3 ? Int(row[3].int ?? 0) : 0
        let inputAt = SessionKit.SessionMeta.antigravityDate(row.count > 4 ? row[4].text : nil)
        let modifiedAt = SessionKit.SessionMeta.antigravityDate(row.count > 5 ? row[5].text : nil)
            ?? inputAt ?? .distantPast
        let cwd = SessionKit.SessionMeta.antigravityCWD(fromWorkspaceURIs: row.count > 6 ? row[6].text : nil)
        // lastActive 계약 = last_modified_time 우선(마지막 입력 이후 에이전트 활동까지 잡는다).
        // last_user_input_time 은 보조 — 마지막 입력만 있고 갱신이 없는 세션의 하한선.
        let path = root + "/conversations/" + id + ".db"
        return SessionRef(
            tool: .agy,
            id: id,
            cwd: cwd ?? "",
            // 제목이 비면 preview(마지막 사용자 입력)로 대체 — 목록에서 빈 줄이 되지 않게.
            title: (title?.isEmpty).map { !$0 } == true ? title : preview,
            lastActive: modifiedAt,
            path: path,
            messageCount: stepCount
        )
    }
}

// MARK: - 파싱

extension AntigravitySessionReader {
    private static let skillMDBytes = Data("SKILL.md".utf8)

    private static func buildStepsQuery(types: Set<Int>?) -> String {
        guard let types, !types.isEmpty else {
            return "SELECT idx, step_type, metadata, step_payload FROM steps ORDER BY idx"
        }
        let typeList = types.map(String.init).joined(separator: ",")
        return "SELECT idx, step_type, metadata, step_payload FROM steps WHERE step_type IN (\(typeList)) ORDER BY idx"
    }

    private static func extractPayloadStrings(stepType: Int, blob: Data) -> [String] {
        guard stepType == 132 else {
            return Self.strings(in: blob)
        }
        // Tool output payload: skip expensive string decoding for large non-skill blobs (e.g. file dumps)
        guard blob.count < 32_768 || blob.range(of: Self.skillMDBytes) != nil else {
            return []
        }
        return Self.strings(in: blob)
    }

    public func steps(_ ref: SessionRef) -> [Step] {
        steps(ref, types: nil)
    }

    public func steps(_ ref: SessionRef, types: Set<Int>?) -> [Step] {
        steps(ref, types: types, limit: nil, reverse: false)
    }

    public func steps(_ ref: SessionRef, types: Set<Int>?, limit: Int?, reverse: Bool) -> [Step] {
        guard let db = try? SessionKit.SQLiteReadOnly(path: ref.transcriptPath) else { return [] }
        var query = Self.buildStepsQuery(types: types)
        if reverse {
            query = query.replacingOccurrences(of: "ORDER BY idx", with: "ORDER BY idx DESC")
        }
        if let limit {
            query += " LIMIT \(limit)"
        }
        var list: [Step] = []
        do {
            try db.forEachRow(query) { row in
                guard row.count >= 4, let index = row[0].int, let type = row[1].int else { return true }
                let stepType = Int(type)
                let metaBlob = row[2].blob ?? Data()
                let payloadBlob = row[3].blob ?? Data()
                list.append(Step(
                    index: Int(index),
                    type: stepType,
                    metadataStrings: Self.strings(in: metaBlob),
                    payloadStrings: Self.extractPayloadStrings(stepType: stepType, blob: payloadBlob)
                ))
                return true
            }
        } catch {
            return list
        }
        return list
    }

    public func digest(_ ref: SessionRef, window: DigestWindow = .standard) -> SessionDigest {
        var d = SessionDigest(ref: ref)
        guard let db = try? SessionKit.SQLiteReadOnly(path: ref.transcriptPath) else { return d }

        if case .recent = window {
            let totalSteps = countSteps(db: db)
            if totalSteps > 400 {
                d.truncated = true
                extractHeadUserMessage(db: db, into: &d)
                processTailSteps(ref, into: &d)
                return d
            }
        }

        // 전체 또는 소형 세션: 순차 스트리밍
        do {
            try db.forEachRow(Self.buildStepsQuery(types: nil)) { row in
                guard row.count >= 4, let index = row[0].int, let type = row[1].int else { return true }
                let stepType = Int(type)
                let metaBlob = row[2].blob ?? Data()
                let payloadBlob = row[3].blob ?? Data()
                let metaStrings = Self.strings(in: metaBlob)
                let payloadStrings = Self.extractPayloadStrings(stepType: stepType, blob: payloadBlob)
                let step = Step(index: Int(index), type: stepType, metadataStrings: metaStrings, payloadStrings: payloadStrings)
                Self.processStep(step, into: &d)
                return true
            }
        } catch {
            d.unknownEvents["db_streaming_error"] = 1
            return d
        }
        return d
    }

    private func countSteps(db: SessionKit.SQLiteReadOnly) -> Int {
        var count = 0
        do {
            try db.forEachRow("SELECT count(*) FROM steps") { row in
                count = Int(row.first?.int ?? 0)
                return false
            }
        } catch {
            return 0
        }
        return count
    }

    private func extractHeadUserMessage(db: SessionKit.SQLiteReadOnly, into d: inout SessionDigest) {
        do {
            try db.forEachRow("SELECT idx, step_type, metadata, step_payload FROM steps WHERE step_type = 14 ORDER BY idx LIMIT 5") { row in
                guard row.count >= 4, let payload = row[3].blob else { return true }
                let runs = Self.strings(in: payload)
                guard let t = Self.humanText(from: runs, used: &d) else { return true }
                d.userMessages.append(t)
                d.turns.append(.init(.user, t))
                return false
            }
        } catch {
            d.unknownEvents["db_head_query_error"] = 1
        }
    }

    private func processTailSteps(_ ref: SessionRef, into d: inout SessionDigest) {
        let tailSteps = steps(ref, types: nil, limit: 300, reverse: true).reversed()
        for step in tailSteps {
            Self.processStep(step, into: &d)
        }
    }

    private static func processStep(_ step: Step, into d: inout SessionDigest) {
        if !knownStepTypes.contains(step.type) {
            d.unknownEvents["step_\(step.type)", default: 0] += 1
        }
        switch step.type {
        case 14:
            guard let t = humanText(from: step.payloadStrings, used: &d) else { return }
            d.userMessages.append(t)
            d.turns.append(.init(.user, t))
        case 15:
            guard let t = longestText(step.payloadStrings, excluding: d.userMessages) else { return }
            d.agentMessages.append(t)
            d.turns.append(.init(.agent, t))
        case 132:
            absorbToolCall(step, into: &d)
        default:
            break
        }
    }

    /// type 14 는 원문을 2중으로 저장한다(실측: 같은 문자열 2회). run 들을 훑되
    /// 이미 뽑은 사용자 발언과 중복이면 건너뛴다.
    static func humanText(from runs: [String], used: inout SessionDigest) -> String? {
        let seen = Set(used.userMessages.map { normalized($0) })
        for run in runs {
            guard isHumanText(run), !seen.contains(normalized(run)) else { continue }
            return normalized(run)
        }
        return nil
    }

    static func longestText(_ runs: [String], excluding known: [String]) -> String? {
        runs
            .filter { isHumanText($0) && !known.contains($0) }
            .max { $0.count < $1.count }
    }

    /// 사람이 쓴 텍스트 run 길이 상한 — protobuf blob 이 통째로 문자열화되는 걸 막는다.
    static let maxHumanRunLength = 8_000

    /// 사람이 쓴 텍스트로 볼 만한 run 인가 — UUID·경로·짧은 식별자는 버린다.
    public static func isHumanText(_ run: String) -> Bool {
        guard run.count >= 2, run.count <= Self.maxHumanRunLength else { return false }
        return !isDiscardableRun(run)
    }

    private static func isDiscardableRun(_ run: String) -> Bool {
        guard !run.hasPrefix("/") else { return true }
        guard run.range(of: #"^[0-9a-fA-F-]{20,}$"#, options: .regularExpression) == nil else { return true }
        guard !run.contains("call_"), !run.hasPrefix("bot-") else { return true }
        guard run.range(of: #"(?s)^\{.*\}"$"#, options: .regularExpression) == nil else { return true }
        let hexish = run.filter { $0.isHexDigit || $0 == "-" }.count
        return Double(hexish) / Double(max(run.count, 1)) > 0.6
    }

    /// type 14 는 같은 원문을 살짝 다른 모양(선행 개행·꼬리 인용부 등)으로 2중 저장한다 —
    /// 비교 전에 양끝 장식을 떼고 중복을 판정한다.
    public static func normalized(_ run: String) -> String {
        run.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// type 132: metadata blob 이 정석(call id + tool 이름 + JSON 인자). payload 는 보조.
    static func absorbToolCall(_ step: Step, into d: inout SessionDigest) {
        AntigravityToolCallAbsorber.absorbToolCall(step, into: &d)
    }

    static func toolName(in runs: [String]) -> String? {
        runs.first { !$0.hasPrefix("call_") && !$0.hasPrefix("{") && !$0.hasPrefix("/") }
    }

    static func firstLine(_ raw: String, cap: Int = 160) -> String? {
        let line = raw.split(whereSeparator: \.isNewline).first.map(String.init) ?? raw
        let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        return t.count <= cap ? t : String(t.prefix(cap - 1)) + "…"
    }
}

enum AntigravityToolCallAbsorber {
    static func absorbToolCall(_ step: AntigravitySessionReader.Step, into d: inout SessionDigest) {
        let all = step.metadataStrings + step.payloadStrings
        for run in all {
            if let dict = parseJSONDict(from: run) {
                absorbJSONRun(dict: dict, metadataStrings: step.metadataStrings, into: &d)
            } else {
                absorbRawPathRun(run, into: &d)
            }
        }
    }

    private static func parseJSONDict(from run: String) -> [String: Any]? {
        guard run.hasPrefix("{"), let data = run.data(using: .utf8) else { return nil }
        do {
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            return nil
        }
    }

    private static func extractFilePaths(from dict: [String: Any], into files: inout [String: Int]) {
        let keys = ["AbsolutePath", "absolute_path", "file_path", "path", "FilePath"]
        for key in keys {
            guard let p = JSONLine.string(dict[key]) else { continue }
            files[p, default: 0] += 1
        }
    }

    private static func absorbJSONRun(dict: [String: Any], metadataStrings: [String], into d: inout SessionDigest) {
        extractFilePaths(from: dict, into: &d.files)
        if let c = JSONLine.string(dict["command"]) ?? JSONLine.string(dict["Command"]) {
            d.commands.append(c)
        }
        guard let summary = JSONLine.string(dict["toolSummary"]) ?? JSONLine.string(dict["toolAction"]) else { return }
        let tool = AntigravitySessionReader.toolName(in: metadataStrings) ?? summary
        d.commandOutputs.append(CommandOutput(command: tool, stdoutLine: AntigravitySessionReader.firstLine(summary)))
    }

    private static func absorbRawPathRun(_ run: String, into d: inout SessionDigest) {
        guard run.hasPrefix("/"), !run.contains(" "),
              run.range(of: #"\.(swift|md|json|sh|py|txt|log)$"#, options: .regularExpression) != nil else {
            return
        }
        d.files[run, default: 0] += 1
    }
}

