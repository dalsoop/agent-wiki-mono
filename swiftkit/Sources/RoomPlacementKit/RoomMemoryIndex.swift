import Foundation
import StateRootKit

/// 룸 메모리 항목 (에이전트 인과 추론, 세션 요약, 학습된 지식)
public struct RoomMemoryItem: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let roomID: String
    public let tenant: String
    public let fileName: String
    public let title: String?
    public let contentSnippet: String
    public let fullContent: String
    public let state: RoomLifecycleState
    public let recordedAt: Date?

    public init(
        id: String,
        roomID: String,
        tenant: String,
        fileName: String,
        title: String? = nil,
        contentSnippet: String,
        fullContent: String,
        state: RoomLifecycleState,
        recordedAt: Date? = nil
    ) {
        self.id = id
        self.roomID = roomID
        self.tenant = tenant
        self.fileName = fileName
        self.title = title
        self.contentSnippet = contentSnippet
        self.fullContent = fullContent
        self.state = state
        self.recordedAt = recordedAt
    }
}

/// 룸 메모리 검색 결과
public struct RoomMemorySearchResult: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(roomID):\(fileName)" }
    public let roomID: String
    public let tenant: String
    public let fileName: String
    public let matchedText: String
    public let score: Double
    public let state: RoomLifecycleState

    public init(
        roomID: String,
        tenant: String,
        fileName: String,
        matchedText: String,
        score: Double,
        state: RoomLifecycleState
    ) {
        self.roomID = roomID
        self.tenant = tenant
        self.fileName = fileName
        self.matchedText = matchedText
        self.score = score
        self.state = state
    }
}

/// 테넌트 내 전체 룸의 기억을 교차 인덱싱/검색하는 서비스
public struct RoomMemoryIndexer: Sendable {
    private var fileManager: FileManager { .default }

    public init() {}

    /// 특정 테넌트의 모든 룸 메모리 검색
    public func search(
        query: String,
        tenant: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [RoomMemorySearchResult] {
        let rooms = listRooms(tenant: tenant, environment: environment)
        let loweredQuery = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !loweredQuery.isEmpty else { return [] }

        var results: [RoomMemorySearchResult] = []

        for layout in rooms {
            let roomID = layout.roomURL.lastPathComponent
            let summary = RoomVaultManager().summary(roomID: roomID, tenantID: tenant, in: layout)
            let state = summary.lifecycleState

            var files: [String] = []
            do {
                files = try fileManager.contentsOfDirectory(atPath: layout.memoryDir.path)
            } catch {
                files = []
            }

            let supportedExtensions = [".json", ".md", ".txt"]
            for file in files where supportedExtensions.contains(where: { file.hasSuffix($0) }) {
                let fileURL = layout.memoryDir.appendingPathComponent(file)
                var content = ""
                do {
                    content = try String(contentsOf: fileURL, encoding: .utf8)
                } catch {
                    content = ""
                }
                guard !content.isEmpty else { continue }

                if content.lowercased().contains(loweredQuery) {
                    let snippet = makeSnippet(from: content, matching: loweredQuery)
                    let score = scoreRelevance(content: content, query: loweredQuery)
                    results.append(
                        RoomMemorySearchResult(
                            roomID: roomID,
                            tenant: tenant,
                            fileName: file,
                            matchedText: snippet,
                            score: score,
                            state: state
                        )
                    )
                }
            }
        }

        return results.sorted { $0.score > $1.score }
    }

    /// 특정 테넌트의 모든 룸 볼트 레이아웃 수집
    public func listRooms(
        tenant: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [RoomVaultLayout] {
        let tenantRoot = StateRootKit.tenantStateRoot(tenant: tenant, environment: environment)
        let roomsDir = URL(fileURLWithPath: tenantRoot, isDirectory: true).appendingPathComponent("rooms", isDirectory: true)

        var roomIDs: [String] = []
        do {
            roomIDs = try fileManager.contentsOfDirectory(atPath: roomsDir.path)
        } catch {
            return []
        }

        return roomIDs.compactMap { id -> RoomVaultLayout? in
            guard !id.hasPrefix(".") else { return nil }
            let roomURL = roomsDir.appendingPathComponent(id, isDirectory: true)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: roomURL.path, isDirectory: &isDir), isDir.boolValue else {
                return nil
            }
            return RoomVaultLayout(roomURL: roomURL)
        }
    }

    private func makeSnippet(from content: String, matching query: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        for line in lines where line.lowercased().contains(query) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.count > 120 ? String(trimmed.prefix(117)) + "..." : trimmed
        }
        return String(content.prefix(100))
    }

    private func scoreRelevance(content: String, query: String) -> Double {
        let count = content.lowercased().components(separatedBy: query).count - 1
        return Double(min(count * 10, 100))
    }
}
