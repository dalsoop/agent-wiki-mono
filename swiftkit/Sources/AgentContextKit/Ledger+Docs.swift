import Foundation
import AgentSessionKit

extension Ledger {
    /// 문서 집계용 가벼운 인덱스. SessionScan/head 없이 digest+주입+사각만.
    /// transcript mtime·size 가 같으면 디스크 캐시를 재사용한다.
    public func docIndex(for ref: SessionRef) -> SessionDocIndex {
        if let key = DocIndexCache.sourceKey(for: ref),
           let hit = docIndexCache.load(sessionId: ref.id, sourceMTime: key.0, sourceSize: key.1) {
            return hit
        }
        let built = buildDocIndex(for: ref)
        docIndexCache.save(built)
        return built
    }

    private func buildDocIndex(for ref: SessionRef) -> SessionDocIndex {
        let dig = digest(ref)
        let blocks = InjectionEvidence.blocks(ref)
        let cwd = blocks.compactMap(\.cwd).first ?? ref.cwd
        let launch = launchStore.load(sessionId: ref.id)
        // SessionScan 생략 — docs 병목(전수 scan) 제거.
        let injectedDocs = launch.map(launchStore.injectedDocs)
            ?? InjectionEvidence.reconcile(resolver.resolve(tool: ref.tool, cwd: cwd), with: blocks)
        let touched = DocumentTrace.touched(digest: dig)
        let blind = resolver.injectBlindSpots(
            tool: ref.tool, cwd: cwd, already: Set(injectedDocs.map(\.path))
        )
        let key = DocIndexCache.sourceKey(for: ref) ?? (ref.lastActive.timeIntervalSince1970, 0)
        return SessionDocIndex(
            source: .init(
                sessionId: ref.id,
                tool: ref.tool.rawValue,
                cwd: cwd,
                lastActive: ref.lastActive,
                sourceMTime: key.0,
                sourceSize: key.1
            ),
            paths: .init(
                injected: injectedDocs.map { .init(path: $0.path, provenance: $0.provenance.rawValue) },
                touched: touched.map { .init(path: $0.path, provenance: $0.provenance.rawValue) },
                blindSpots: blind.map { .init(path: $0.path, provenance: Provenance.walkBlindSpot.rawValue) }
            )
        )
    }

    /// 문서별 사용 집계 — 전체 카드 대신 docIndex(캐시)만 쓴다.
    public func docUsage(tools: Set<AgentTool> = Set(AgentTool.allCases),
                         since: Date? = nil,
                         limit: Int = 200) -> [DocUsage] {
        var injected: [String: Int] = [:]
        var touched: [String: Int] = [:]
        var blind: [String: Int] = [:]
        var byTool: [String: Set<String>] = [:]
        var lastSeen: [String: Date] = [:]

        for ref in sessions(tools: tools, since: since, limit: limit) {
            let idx = docIndex(for: ref)
            for e in idx.injected {
                injected[e.path, default: 0] += 1
                byTool[e.path, default: []].insert(idx.tool)
                lastSeen[e.path] = max(lastSeen[e.path] ?? .distantPast, idx.lastActive)
            }
            for e in idx.touched {
                touched[e.path, default: 0] += 1
                byTool[e.path, default: []].insert(idx.tool)
                lastSeen[e.path] = max(lastSeen[e.path] ?? .distantPast, idx.lastActive)
            }
            for e in idx.blindSpots {
                blind[e.path, default: 0] += 1
                byTool[e.path, default: []].insert(idx.tool)
                lastSeen[e.path] = max(lastSeen[e.path] ?? .distantPast, idx.lastActive)
            }
        }

        return Set(injected.keys).union(touched.keys).union(blind.keys).map { path in
            DocUsage(
                path: path,
                injectedSessions: injected[path] ?? 0,
                touchedSessions: touched[path] ?? 0,
                blindSpotSessions: blind[path] ?? 0,
                tools: (byTool[path] ?? []).sorted(),
                lastSeen: lastSeen[path]
            )
        }
        .sorted { ($0.totalSessions, $1.path) > ($1.totalSessions, $0.path) }
    }

    /// 호환 API — 매칭 시 카드까지 채운다. 주 경로는 docHits.
    public func sessionsTouching(path: String,
                                 tools: Set<AgentTool> = Set(AgentTool.allCases),
                                 since: Date? = nil,
                                 limit: Int = 200,
                                 cwd: String = FileManager.default.currentDirectoryPath
    ) -> [(card: SessionContextCard, how: Provenance, matchedPath: String)] {
        let resolve = DocPathQuery.resolve(path, cwd: cwd)
        var out: [(SessionContextCard, Provenance, String)] = []
        for ref in sessions(tools: tools, since: since, limit: limit) {
            let idx = docIndex(for: ref)
            var matched: [(Provenance, String)] = []
            for e in idx.injected where DocPathQuery.matches(path: e.path, resolve: resolve) {
                matched.append((Provenance(rawValue: e.provenance) ?? .reconstructedCurrent, e.path))
            }
            for e in idx.touched where DocPathQuery.matches(path: e.path, resolve: resolve) {
                matched.append((Provenance(rawValue: e.provenance) ?? .shell, e.path))
            }
            for e in idx.blindSpots where DocPathQuery.matches(path: e.path, resolve: resolve) {
                matched.append((.walkBlindSpot, e.path))
            }
            guard !matched.isEmpty else { continue }
            let c = card(for: ref)
            for m in matched { out.append((c, m.0, m.1)) }
        }
        return out
    }

    /// `doc` CLI — 카드 없이 인덱스만 (캐시 히트 시 매우 빠름).
    public func docHits(
        query: String,
        cwd: String = FileManager.default.currentDirectoryPath,
        tools: Set<AgentTool> = Set(AgentTool.allCases),
        since: Date? = nil,
        limit: Int = 200
    ) -> (resolve: DocPathQuery.Resolve, hits: [DocHit]) {
        let resolve = DocPathQuery.resolve(query, cwd: cwd)
        var hits: [DocHit] = []
        for ref in sessions(tools: tools, since: since, limit: limit) {
            let idx = docIndex(for: ref)
            for e in idx.injected where DocPathQuery.matches(path: e.path, resolve: resolve) {
                hits.append(DocHit(
                    sessionId: idx.sessionId, tool: idx.tool, cwd: idx.cwd,
                    lastActive: idx.lastActive,
                    how: Provenance(rawValue: e.provenance) ?? .reconstructedCurrent,
                    matchedPath: e.path
                ))
            }
            for e in idx.touched where DocPathQuery.matches(path: e.path, resolve: resolve) {
                hits.append(DocHit(
                    sessionId: idx.sessionId, tool: idx.tool, cwd: idx.cwd,
                    lastActive: idx.lastActive,
                    how: Provenance(rawValue: e.provenance) ?? .shell,
                    matchedPath: e.path
                ))
            }
            for e in idx.blindSpots where DocPathQuery.matches(path: e.path, resolve: resolve) {
                hits.append(DocHit(
                    sessionId: idx.sessionId, tool: idx.tool, cwd: idx.cwd,
                    lastActive: idx.lastActive, how: .walkBlindSpot, matchedPath: e.path
                ))
            }
        }
        return (resolve, hits)
    }

    /// 아무 세션에도 안 걸린 md — 죽은 문서 후보.
    ///
    /// 주의: 스캔 범위 밖 세션에서 읽혔을 수 있다. 그래서 "죽었다" 가 아니라 "이 범위에서
    /// 안 걸렸다" 로 읽어야 한다. 범위를 함께 출력하는 이유다.
    public func unreferenced(roots: [String],
                             tools: Set<AgentTool> = Set(AgentTool.allCases),
                             since: Date? = nil,
                             limit: Int = 200,
                             fm: FileManager = .default) -> [String] {
        let used = Set(docUsage(tools: tools, since: since, limit: limit).map(\.path))
        var all: [String] = []
        for root in roots {
            let base = (root as NSString).standardizingPath
            guard let e = fm.enumerator(atPath: base) else { continue }
            for case let rel as String in e {
                guard rel.hasSuffix(".md") else { continue }
                if Self.prunedPathComponents.contains(where: { rel.contains("/\($0)/") || rel.hasPrefix("\($0)/") }) { continue }
                all.append(base + "/" + rel)
            }
        }
        return all.filter { !used.contains($0) }.sorted()
    }
}
