import Foundation
import AgentSessionKit
import StateRootKit

/// docs/doc 집계용 가벼운 세션 문서 인덱스.
/// 전체 SessionContextCard(SessionScan 최대 16MB) 없이 주입·읽힘·사각 경로만 담는다.
public struct SessionDocIndex: Sendable, Codable, Equatable {
    public let sessionId: String
    public let tool: String
    public let cwd: String
    public let lastActive: Date
    public let injected: [PathEntry]
    public let touched: [PathEntry]
    public let blindSpots: [PathEntry]
    public let sourceMTime: TimeInterval
    public let sourceSize: Int

    public struct PathEntry: Sendable, Codable, Equatable {
        public let path: String
        public let provenance: String
        public init(path: String, provenance: String) {
            self.path = path
            self.provenance = provenance
        }
    }

    public struct Source: Sendable, Equatable {
        public let sessionId: String
        public let tool: String
        public let cwd: String
        public let lastActive: Date
        public let sourceMTime: TimeInterval
        public let sourceSize: Int

        public init(sessionId: String, tool: String, cwd: String, lastActive: Date,
                    sourceMTime: TimeInterval, sourceSize: Int) {
            self.sessionId = sessionId
            self.tool = tool
            self.cwd = cwd
            self.lastActive = lastActive
            self.sourceMTime = sourceMTime
            self.sourceSize = sourceSize
        }
    }

    public struct Paths: Sendable, Equatable {
        public let injected: [PathEntry]
        public let touched: [PathEntry]
        public let blindSpots: [PathEntry]

        public init(injected: [PathEntry], touched: [PathEntry], blindSpots: [PathEntry]) {
            self.injected = injected
            self.touched = touched
            self.blindSpots = blindSpots
        }
    }

    public init(source: Source, paths: Paths) {
        self.sessionId = source.sessionId
        self.tool = source.tool
        self.cwd = source.cwd
        self.lastActive = source.lastActive
        self.injected = paths.injected
        self.touched = paths.touched
        self.blindSpots = paths.blindSpots
        self.sourceMTime = source.sourceMTime
        self.sourceSize = source.sourceSize
    }
}

/// `~/.agent-session-context-ledger/doc-index/<id>.json` — transcript mtime·size 로 무효화.
public struct DocIndexCache: Sendable {
    public let root: String

    public init(root: String = StateRootKit.path(".agent-session-context-ledger/doc-index")) {
        self.root = root
    }

    private func filePath(for sessionId: String) -> String {
        root + "/" + sessionId + ".json"
    }

    public func load(sessionId: String, sourceMTime: TimeInterval, sourceSize: Int,
                     fm: FileManager = .default) -> SessionDocIndex? {
        guard let data = fm.contents(atPath: filePath(for: sessionId)) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let idx = try? dec.decode(SessionDocIndex.self, from: data) else { return nil }
        guard idx.sourceMTime == sourceMTime, idx.sourceSize == sourceSize else { return nil }
        return idx
    }

    public func save(_ idx: SessionDocIndex, fm: FileManager = .default) {
        do { try fm.createDirectory(atPath: root, withIntermediateDirectories: true) } catch { _ = error }
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(idx) else { return }
        do { try data.write(to: URL(fileURLWithPath: filePath(for: idx.sessionId)), options: .atomic) } catch { _ = error }
    }

    public static func sourceKey(for ref: SessionRef, fm: FileManager = .default) -> (TimeInterval, Int)? {
        guard let attrs = try? fm.attributesOfItem(atPath: ref.transcriptPath) else { return nil }
        let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attrs[.size] as? Int) ?? 0
        return (mtime, size)
    }
}
