import Foundation
import StateRootKit
import WikiLedgerKit

/// 파생 그래프 인덱스 캐시. `~/.swift-app-state/agent-wiki-graph/index.json`.
///
/// md-lineage-viewer IndexCache 패턴: `currentVersion` 으로 스키마가 깨지면 폐기,
/// 원자적 교체. 원장 mtime 지문(`ledgerFingerprint`)이 바뀌면 재빌드.
public enum IndexCache {
    public static let currentVersion = 1
    public static let appName = "agent-wiki-graph"
    public static let stateRelativePath = ".swift-app-state/\(appName)"
    public static var defaultDir: URL {
        StateRootKit.url(stateRelativePath)
    }
    public static var defaultURL: URL { defaultDir.appendingPathComponent("index.json") }

    public struct Snapshot: Codable, Sendable {
        public var version: Int
        public var ledgerFingerprint: String
        public var nodes: [WikiNode]
        public var edges: [WikiEdge]
        public var nodeCount: Int
        public var edgeCount: Int
        public var orphanCount: Int
        public var indexedAt: Date

        public init(version: Int, ledgerFingerprint: String, nodes: [WikiNode], edges: [WikiEdge],
                    nodeCount: Int, edgeCount: Int, orphanCount: Int, indexedAt: Date) {
            self.version = version
            self.ledgerFingerprint = ledgerFingerprint
            self.nodes = nodes
            self.edges = edges
            self.nodeCount = nodeCount
            self.edgeCount = edgeCount
            self.orphanCount = orphanCount
            self.indexedAt = indexedAt
        }
    }

    /// 스키마 버전이 다르거나 원장 지문이 바뀌면 stale — 캐시를 현재로 단정하지 않는다.
    public static func isStale(_ snapshot: Snapshot, ledgerFingerprint: String) -> Bool {
        snapshot.version != currentVersion || snapshot.ledgerFingerprint != ledgerFingerprint
    }

    public static func load(url: URL = defaultURL) -> Snapshot? {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return nil
        }
        do {
            let snap = try JSONDecoder.wiki.decode(Snapshot.self, from: data)
            // 스키마 깨지면 폐기(과거 버전 캐시는 믿지 않는다).
            guard snap.version == currentVersion else { return nil }
            return snap
        } catch {
            fputs("IndexCache.load: \(error.localizedDescription)\n", stderr)
            return nil
        }
    }

    public static func save(url: URL = defaultURL, _ snapshot: Snapshot) {
        let dir = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder.wiki.encode(snapshot)
            let tmp = dir.appendingPathComponent(".index.json.tmp")
            try data.write(to: tmp, options: .atomic)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } catch {
            fputs("IndexCache.save: \(error.localizedDescription)\n", stderr)
        }
    }
}

// WikiNode/WikiEdge Codable 은 WikiLedgerKit 에서 선언.

extension JSONEncoder {
    static let wiki: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}
extension JSONDecoder {
    static let wiki: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
