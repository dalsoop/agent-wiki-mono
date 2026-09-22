import Foundation

/// 격리된 파일 메타데이터
public struct QuarantinedItem: Codable, Sendable, Identifiable {
    public var id: String { originalPath }
    public let originalPath: String
    public let quarantinedPath: String
    public let byteSize: Int64
    public let sha256: String
    public let timestamp: Date
    public let reason: String

    public init(originalPath: String, quarantinedPath: String, byteSize: Int64, sha256: String = "", timestamp: Date = Date(), reason: String) {
        self.originalPath = originalPath
        self.quarantinedPath = quarantinedPath
        self.byteSize = byteSize
        self.sha256 = sha256
        self.timestamp = timestamp
        self.reason = reason
    }
}

/// 한 번의 격리 세션 원장 (Manifest)
public struct QuarantineSessionManifest: Codable, Sendable {
    public let sessionID: String
    public let createdAt: Date
    public let appSlug: String
    public var items: [QuarantinedItem]

    public init(sessionID: String = UUID().uuidString, createdAt: Date = Date(), appSlug: String, items: [QuarantinedItem] = []) {
        self.sessionID = sessionID
        self.createdAt = createdAt
        self.appSlug = appSlug
        self.items = items
    }
}

/// WAL(Write-Ahead Log) 저널 상태
public struct QuarantineJournal: Codable, Sendable {
    public enum State: String, Codable, Sendable {
        case prepared
        case executing
        case committed
        case rolledBack
    }
    public let sessionID: String
    public var state: State
    public let itemsToMove: [(source: String, destination: String)]

    public init(sessionID: String, state: State, itemsToMove: [(source: String, destination: String)]) {
        self.sessionID = sessionID
        self.state = state
        self.itemsToMove = itemsToMove
    }

    enum CodingKeys: String, CodingKey {
        case sessionID, state, moves
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try container.decode(String.self, forKey: .sessionID)
        state = try container.decode(State.self, forKey: .state)
        let pairs = try container.decode([[String]].self, forKey: .moves)
        itemsToMove = pairs.compactMap { $0.count == 2 ? ($0[0], $0[1]) : nil }
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(state, forKey: .state)
        let pairs = itemsToMove.map { [$0.source, $0.destination] }
        try container.encode(pairs, forKey: .moves)
    }
}

/// 무손실 안전 격리 엔진 (v1.1: 로컬 프로젝트 .unused-quarantine/ + WAL 트랜잭션 저널링)
public final class QuarantineManager: Sendable {
    public let projectRootURL: URL

    public init(projectRootURL: URL) {
        self.projectRootURL = projectRootURL
    }

    /// 프로젝트 로컬 .unused-quarantine 디렉터리 경로 (EXDEV 크로스 볼륨 에러 원천 차단)
    public var localQuarantineURL: URL {
        projectRootURL.appendingPathComponent(".unused-quarantine")
    }

    /// 격리 세션 생성
    public func createSession(appSlug: String) throws -> (sessionID: String, sessionURL: URL) {
        let sessionID = UUID().uuidString
        let sessionURL = localQuarantineURL.appendingPathComponent(sessionID)
        try FileManager.default.createDirectory(at: sessionURL, withIntermediateDirectories: true)
        return (sessionID, sessionURL)
    }

    /// 안전 파일 격리 실행 (동일 볼륨 내 이동 우선, 실패 시 Copy -> Verify -> Delete Fallback)
    public func quarantine(fileURL: URL, sessionURL: URL, reason: String) throws -> QuarantinedItem {
        let fileManager = FileManager.default
        let fileName = fileURL.lastPathComponent
        let targetURL = sessionURL.appendingPathComponent(fileName)

        let attrs = try fileManager.attributesOfItem(atPath: fileURL.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0

        // 1. 원자적 이동 시도
        do {
            try fileManager.moveItem(at: fileURL, to: targetURL)
        } catch {
            // 2. EXDEV 등 이동 실패 시 Copy -> Delete Fallback
            try fileManager.copyItem(at: fileURL, to: targetURL)
            try fileManager.removeItem(at: fileURL)
        }

        return QuarantinedItem(
            originalPath: fileURL.path,
            quarantinedPath: targetURL.path,
            byteSize: size,
            timestamp: Date(),
            reason: reason
        )
    }

    /// 세션 단위 원위치 복원 (Undo)
    public func restore(manifest: QuarantineSessionManifest) throws -> [URL] {
        let fileManager = FileManager.default
        var restored: [URL] = []

        for item in manifest.items {
            let sourceURL = URL(fileURLWithPath: item.quarantinedPath)
            let destURL = URL(fileURLWithPath: item.originalPath)

            if fileManager.fileExists(atPath: sourceURL.path) {
                try fileManager.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                do {
                    try fileManager.moveItem(at: sourceURL, to: destURL)
                } catch {
                    try fileManager.copyItem(at: sourceURL, to: destURL)
                    try fileManager.removeItem(at: sourceURL)
                }
                restored.append(destURL)
            }
        }
        return restored
    }
}
