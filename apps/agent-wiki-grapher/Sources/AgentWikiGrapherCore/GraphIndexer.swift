import Foundation
import GraphEngineKit
import StateRootKit
import WikiLedgerKit

/// 원장 루트를 훑어 그래프를 빌드하고, mtime 신선도로 증분 캐시.
///
/// 그래프 구축(파싱+alias 해상)은 `WikiLedgerKit.WikiLedgerIndex` 에, 신선도 지문은
/// `GraphEngineKit.DirectoryFingerprint` 에 위임한다 — 이 앱은 캐시 오케스트레이션만.
/// (패턴 = md-lineage-viewer MdIndexer/IndexCache: 원장이 SSOT 고 여기는 파생 인덱스.)
public enum GraphIndexer {

    /// 기본 원장 루트. `GUJO_WIKI_ROOT` 우선.
    /// 공용 world `gujo-wiki` 는 테넌트 overlay(`~/.tenants/<slug>/gujo-wiki`)가 아니다.
    public static func defaultRoot(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = NSHomeDirectory()
    ) -> URL {
        if let env = environment["GUJO_WIKI_ROOT"], !env.isEmpty {
            return URL(fileURLWithPath: (env as NSString).expandingTildeInPath)
        }
        return URL(
            fileURLWithPath: StateRootKit.hostPath(
                "gujo-wiki",
                environment: environment,
                homeDirectory: homeDirectory
            )
        )
    }

    /// 원장 objects 디렉터리의 신선도 지문(개수:바이트:최신mtime).
    public static func ledgerFingerprint(root: URL) -> String {
        DirectoryFingerprint.fingerprint(root: root.appendingPathComponent("objects"), fileExtension: "md")
    }

    /// 전체 빌드(캐시 무시). 파싱+alias 해상은 WikiLedgerKit.
    public static func rebuild(root: URL) -> Graph<WikiNode, WikiEdge> {
        WikiLedgerIndex.buildGraph(root: root)
    }

    /// 캐시에서 로드, 지문 같으면 재사용, 아니면 rebuild 후 캐시 저장.
    public static func load(
        root: URL,
        cacheURL: URL = IndexCache.defaultURL,
        forceRebuild: Bool = false
    ) -> Graph<WikiNode, WikiEdge> {
        let fp = ledgerFingerprint(root: root)
        if !forceRebuild,
           let cached = IndexCache.load(url: cacheURL),
           !IndexCache.isStale(cached, ledgerFingerprint: fp) {
            return Graph(nodes: cached.nodes, edges: cached.edges)
        }
        let graph = rebuild(root: root)
        IndexCache.save(
            url: cacheURL,
            .init(version: IndexCache.currentVersion, ledgerFingerprint: fp,
                  nodes: Array(graph.nodes.values), edges: graph.out.values.flatMap { $0 },
                  nodeCount: graph.nodeCount, edgeCount: graph.edgeCount,
                  orphanCount: graph.orphans().count, indexedAt: Date())
        )
        return graph
    }

    /// 진단용: 빌드 없이 파일 수.
    public static func objectFileCount(root: URL) -> Int {
        WikiLedgerIndex.objectFileCount(root: root)
    }
}
