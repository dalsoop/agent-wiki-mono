import Foundation

// 함대 "기능" 검색 — `~/.agent-apps/registry.json` 및 스킬·에이전트 카탈로그를
// 통합 읽어 이름·CLI·명령·summary·why 를 질의한다.

/// 레지스트리 기반 함대 기능 검색기.
///
/// 99앱 × 명령 전체를 매 질의마다 훑어도 수 ms 대(실측). 반복 질의를 위해
/// **registry.json mtime** 기준 문서 캐시만 둔다 — 별도 인덱스 파일/앱별 인덱스는 없다.
public final class CapabilitySearcher: @unchecked Sendable {
    public let store: RegistryStore
    public let agentsURL: URL?
    public let skillsRoots: [URL]

    public static var defaultAgentsURL: URL {
        URL(fileURLWithPath: (("~/.agent-apps/agents.json" as NSString).expandingTildeInPath))
    }

    public static var defaultSkillsRoots: [URL] {
        var roots: [URL] = []
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        if let env = ProcessInfo.processInfo.environment["HOST_SKILLS_ROOT"], !env.isEmpty {
            roots.append(URL(fileURLWithPath: (env as NSString).expandingTildeInPath))
        }
        let candidates = [
            "Documents/WORK/WORKSPACE/ai-tools/host-skills-mono/main",
            "Documents/WORK/WORKSPACE/ai-tools/host-skills-mono",
            "Documents/WORK/WORKSPACE/ai-tools/root-agent-md-mono/main/personal-mac",
            "Documents/WORK/WORKSPACE/ai-tools/root-agent-md-mono/main",
            ".agents",
        ]
        for rel in candidates {
            let u = home.appendingPathComponent(rel, isDirectory: true)
            if fm.fileExists(atPath: u.path) {
                roots.append(u)
            }
        }
        let lockURL = home.appendingPathComponent(".agents/.skill-lock.json")
        if fm.fileExists(atPath: lockURL.path) {
            roots.append(lockURL)
        }
        return roots
    }

    let lock = NSLock()
    var cachedMTime: Date?
    var cachedDocs: [SearchDocument] = []
    var cachedAppCount: Int = 0

    public init(
        store: RegistryStore = RegistryStore(),
        agentsURL: URL? = nil,
        skillsRoots: [URL]? = nil
    ) {
        self.store = store
        let isDefaultStore = store.fileURL.standardizedFileURL.path == RegistryStore().fileURL.standardizedFileURL.path
        self.agentsURL = agentsURL ?? (isDefaultStore ? Self.defaultAgentsURL : nil)
        self.skillsRoots = skillsRoots ?? (isDefaultStore ? Self.defaultSkillsRoots : [])
    }

    private struct SearchContext {
        let started: Double
        let query: String
        let tokens: [String]
        let path: String

        func finish(
            status: CapabilitySearchStatus,
            message: String,
            hits: [CapabilitySearchHit] = [],
            scanned: Int = 0,
            mtime: Double? = nil
        ) -> CapabilitySearchResult {
            let ms = (Date().timeIntervalSinceReferenceDate - started) * 1000
            return CapabilitySearchResult(
                status: status,
                message: message,
                query: query,
                tokens: tokens,
                hits: hits,
                scannedApps: scanned,
                durationMs: ms,
                registry: .init(path: path, mTime: mtime)
            )
        }
    }

    /// 공백 분리 토큰 AND · 부분일치 · 대소문자/NFC 정규화.
    public func search(_ query: String) -> CapabilitySearchResult {
        let started = Date().timeIntervalSinceReferenceDate
        let path = store.fileURL.path
        let tokens = QueryLexicon.dropStopwords(Self.tokenize(query))
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let ctx = SearchContext(started: started, query: trimmed, tokens: tokens, path: path)

        if tokens.isEmpty {
            return ctx.finish(status: .emptyQuery, message: "질의가 비어 있습니다. 예: search orchestrator 작업")
        }

        let fm = FileManager.default
        let storeExists = fm.fileExists(atPath: path)
        let agentsExist = agentsURL.map { fm.fileExists(atPath: $0.path) } ?? false
        let skillsExist = skillsRoots.contains { fm.fileExists(atPath: $0.path) }
        guard [storeExists, agentsExist, skillsExist].contains(true) else {
            return ctx.finish(status: .registryMissing, message: "레지스트리가 없습니다: \(path). ship 가 앱 설치 시 capabilities 를 채웁니다.")
        }

        let mtimeDate = (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        let mtimeUnix = mtimeDate?.timeIntervalSince1970

        let docs: [SearchDocument]
        let appCount: Int
        do {
            let loaded = try loadDocuments(currentMTime: mtimeDate)
            docs = loaded.docs
            appCount = loaded.appCount
        } catch {
            return ctx.finish(status: .registryMissing, message: "레지스트리를 읽지 못했습니다: \(error.localizedDescription)", mtime: mtimeUnix)
        }

        if appCount == 0 {
            return ctx.finish(status: .registryEmpty, message: "레지스트리가 비어 있습니다: \(path). 앱을 ship 하면 capabilities 가 등록됩니다.", scanned: 0, mtime: mtimeUnix)
        }

        let queryVariants = tokens.map { QueryLexicon.variants($0) }
        let tokenScale = computeTokenScale(docs: docs, queryVariants: queryVariants)
        let collected = collectHits(docs: docs, tokens: tokens, queryVariants: queryVariants, tokenScale: tokenScale)

        let unit = docs.contains { $0.kind != .app } ? "도구" : "앱"
        return formatSearchOutcome(
            full: collected.full,
            partial: collected.partial,
            unit: unit,
            appCount: appCount,
            mtimeUnix: mtimeUnix,
            context: ctx
        )
    }

    private func computeTokenScale(docs: [SearchDocument], queryVariants: [[String]]) -> [Double] {
        let n = max(docs.count, 1)
        return queryVariants.map { vs in
            let df = docs.reduce(0) { count, doc in
                let hit = vs.contains { doc.words.contains($0) || doc.words.contains($0 + "s") }
                return count + (hit ? 1 : 0)
            }
            if df * 8 <= n { return 1.0 }
            if df * 3 <= n { return 0.5 }
            return 0.25
        }
    }

    private func collectHits(
        docs: [SearchDocument],
        tokens: [String],
        queryVariants: [[String]],
        tokenScale: [Double]
    ) -> (full: [CapabilitySearchHit], partial: [CapabilitySearchHit]) {
        var full: [CapabilitySearchHit] = []
        var partial: [CapabilitySearchHit] = []
        for doc in docs {
            guard let (hit, matchedTokens, required) = Self.evaluate(
                doc: doc, tokens: tokens, variants: queryVariants, scale: tokenScale)
            else { continue }
            if matchedTokens == required {
                full.append(hit)
            } else {
                partial.append(hit)
            }
        }
        return (full, partial)
    }

    private func formatSearchOutcome(
        full: [CapabilitySearchHit],
        partial: [CapabilitySearchHit],
        unit: String,
        appCount: Int,
        mtimeUnix: Double?,
        context: SearchContext
    ) -> CapabilitySearchResult {
        func rank(_ a: CapabilitySearchHit, _ b: CapabilitySearchHit) -> Bool {
            if a.score != b.score { return a.score > b.score }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }

        var sortedPartial = partial
        sortedPartial.sort(by: rank)
        let hits = (full + Array(sortedPartial.prefix(20))).sorted(by: rank)

        guard full.isEmpty else {
            return context.finish(
                status: .ok,
                message: "\(hits.count)개 \(unit) · \(appCount)\(unit) 스캔",
                hits: hits,
                scanned: appCount,
                mtime: mtimeUnix
            )
        }
        guard hits.isEmpty else {
            return context.finish(
                status: .partialMatches,
                message: "모든 낱말이 걸리는 \(unit)은 없어 **일부 낱말**로 찾았습니다 (질의: \(context.query), \(hits.count)개 · 스캔 \(appCount)\(unit)).",
                hits: hits,
                scanned: appCount,
                mtime: mtimeUnix
            )
        }
        return context.finish(
            status: .noMatches,
            message: "매칭 \(unit)이 없습니다 (질의: \(context.query), 스캔 \(appCount)\(unit)).",
            hits: [],
            scanned: appCount,
            mtime: mtimeUnix
        )
    }

    /// 캐시 비우기(테스트·강제 재로드).
    public func invalidateCache() {
        lock.lock()
        defer { lock.unlock() }
        cachedMTime = nil
        cachedDocs = []
        cachedAppCount = 0
    }

    // MARK: - tokenize / normalize

    public static func tokenize(_ query: String) -> [String] {
        let scalars = CharacterSet.whitespacesAndNewlines
            .union(.punctuationCharacters)
            .union(.symbols)
        return query
            .components(separatedBy: scalars)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    public static func normalize(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.lowercased()
    }

    static func containsWord(_ haystack: String, _ needle: String) -> Bool {
        guard !needle.isEmpty else { return false }
        var searchFrom = haystack.startIndex
        while let r = haystack.range(of: needle, range: searchFrom..<haystack.endIndex) {
            func isWordChar(_ c: Character) -> Bool { c.isLetter || c.isNumber }
            let beforeOK: Bool = r.lowerBound == haystack.startIndex
                || !isWordChar(haystack[haystack.index(before: r.lowerBound)])
            var afterOK: Bool = r.upperBound == haystack.endIndex
                || !isWordChar(haystack[r.upperBound])
            if !afterOK, haystack[r.upperBound] == "s" {
                let next = haystack.index(after: r.upperBound)
                afterOK = next == haystack.endIndex || !isWordChar(haystack[next])
            }
            if beforeOK && afterOK { return true }
            searchFrom = r.upperBound
        }
        return false
    }

    // MARK: - match

    private static func evaluate(
        doc: SearchDocument,
        tokens: [String],
        variants: [[String]],
        scale: [Double]
    ) -> (hit: CapabilitySearchHit, matchedTokens: Int, requiredTokens: Int)? {
        var pairs = Array(zip(tokens.map(normalize), zip(variants, scale)))
            .map { ($0.0, $0.1.0, $0.1.1) }
            .filter { !$0.0.isEmpty }
        if pairs.count >= 2 {
            pairs.removeAll { $0.0.count == 1 && $0.0.unicodeScalars.allSatisfy(\.isASCII) }
        }
        guard !pairs.isEmpty else { return nil }

        var reasons: [CapabilityMatchReason] = []
        var score = 0
        var matchedTokens = 0
        var matchedCmdNames = Set<String>()

        for (t, vs, sc) in pairs {
            guard vs.contains(where: { doc.blob.contains($0) }) else { continue }
            let res = scoreToken(t: t, vs: vs, doc: doc, matchedCmdNames: &matchedCmdNames)
            guard res.fieldHits > 0 else { continue }
            reasons.append(contentsOf: res.reasons)
            matchedTokens += 1
            let raw = res.best + min(2, max(0, res.fieldHits - 1))
            score += max(1, Int((Double(raw) * sc).rounded()))
        }
        guard matchedTokens > 0 else { return nil }

        let matchedCommands = resolveMatchedCommands(doc: doc, pairs: pairs, matchedCmdNames: &matchedCmdNames)
        let uniqueReasons = deduplicateReasons(reasons)

        let hit = CapabilitySearchHit(
            name: doc.name,
            cli: doc.cli,
            version: doc.version,
            matchedCommands: matchedCommands,
            reasons: uniqueReasons,
            score: score,
            kind: doc.kind,
            sourceID: doc.sourceID
        )
        return (hit, matchedTokens, pairs.count)
    }

    private static func matchVariants(in normalized: String, variants: [String]) -> (sub: Bool, whole: Bool) {
        var sub = false
        for v in variants {
            guard normalized.contains(v) else { continue }
            sub = true
            guard !Self.containsWord(normalized, v) else {
                return (true, true)
            }
        }
        return (sub, false)
    }

    private static func scoreToken(
        t: String,
        vs: [String],
        doc: SearchDocument,
        matchedCmdNames: inout Set<String>
    ) -> (best: Int, fieldHits: Int, reasons: [CapabilityMatchReason]) {
        var best = 0
        var fieldHits = 0
        var reasons: [CapabilityMatchReason] = []

        for f in doc.fields {
            let match = matchVariants(in: f.normalized, variants: vs)
            guard match.sub else { continue }
            fieldHits += 1
            reasons.append(CapabilityMatchReason(field: f.field, token: t, snippet: f.snippet))
            let base = fieldWeight(f.field, snippet: f.snippet, matchedCmdNames: &matchedCmdNames)
            let w = match.whole ? base : max(1, base / 2)
            best = max(best, w)
        }
        return (best, fieldHits, reasons)
    }

    private static func fieldWeight(
        _ field: String,
        snippet: String,
        matchedCmdNames: inout Set<String>
    ) -> Int {
        switch field {
        case "name": return 8
        case "cli": return 7
        case "purpose", "persona", "notes", "description", "summary", "skill.summary": return 6
        case "command.name":
            matchedCmdNames.insert(snippet)
            return 5
        case "command.summary": return 4
        case "depends.why": return 2
        default: return 1
        }
    }

    private static func resolveMatchedCommands(
        doc: SearchDocument,
        pairs: [(String, [String], Double)],
        matchedCmdNames: inout Set<String>
    ) -> [CapabilityMatchedCommand] {
        for cmd in doc.commands {
            let nameN = normalize(cmd.name)
            let sumN = normalize(cmd.summary)
            let hit = pairs.contains { _, vs, _ in
                vs.contains { nameN.contains($0) || sumN.contains($0) }
            }
            if hit {
                matchedCmdNames.insert(cmd.name)
            }
        }
        return doc.commands.filter { matchedCmdNames.contains($0.name) }.map {
            CapabilityMatchedCommand(name: $0.name, summary: $0.summary, json: $0.json)
        }
    }

    private static func deduplicateReasons(_ reasons: [CapabilityMatchReason]) -> [CapabilityMatchReason] {
        var seen = Set<String>()
        return reasons.filter { r in
            let k = "\(r.field)|\(r.token)|\(r.snippet)"
            return seen.insert(k).inserted
        }
    }
}
