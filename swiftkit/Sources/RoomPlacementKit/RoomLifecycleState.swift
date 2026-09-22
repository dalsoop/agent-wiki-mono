import Foundation

/// 룸의 3단계 생명주기
public enum RoomLifecycleState: String, Codable, Sendable, Equatable {
    /// 활성 상태: 에이전트 작업 중, 실시간 세션 및 입출력
    case active
    /// 동결(봉인) 상태: 작업 완료, 체커 검증 완료, 읽기 전용 영수증 발행
    case sealed
    /// 보관(아카이브) 상태: 일정 시간 경과 후 raw/ 정리, curated/와 skills/ 메타만 콜드 보존
    case archived
}

/// 룸 작업 완료 시 봉인되는 스냅샷 (불변)
public struct RoomSealedSnapshot: Codable, Sendable, Equatable {
    public let roomID: String
    public let tenant: String
    public let sealedAt: Date
    public let state: RoomLifecycleState
    public let budgetUsedTokens: Int
    public let durationSeconds: Double
    public let wallPreset: String
    public let curatedArtifacts: [String]
    public let skillNames: [String]
    public let stats: RoomVaultStats

    public init(
        roomID: String,
        tenant: String,
        sealedAt: Date = Date(),
        state: RoomLifecycleState = .sealed,
        budgetUsedTokens: Int = 0,
        durationSeconds: Double = 0,
        wallPreset: String = "standard",
        curatedArtifacts: [String] = [],
        skillNames: [String] = [],
        stats: RoomVaultStats = RoomVaultStats(curatedArtifactCount: 0, memoryItemCount: 0, skillCount: 0, rawSizeBytes: 0)
    ) {
        self.roomID = roomID
        self.tenant = tenant
        self.sealedAt = sealedAt
        self.state = state
        self.budgetUsedTokens = budgetUsedTokens
        self.durationSeconds = durationSeconds
        self.wallPreset = wallPreset
        self.curatedArtifacts = curatedArtifacts
        self.skillNames = skillNames
        self.stats = stats
    }
}

/// 룸 생명주기 아카이버
public struct RoomLifecycleArchiver: Sendable {
    private let vaultManager: RoomVaultManager
    private var fileManager: FileManager { .default }

    public init(
        vaultManager: RoomVaultManager = RoomVaultManager()
    ) {
        self.vaultManager = vaultManager
    }

    /// 룸을 봉인(Seal)하여 불변 스냅샷을 생성하고 snapshot.json에 기록
    @discardableResult
    public func seal(
        roomID: String,
        tenant: String,
        layout: RoomVaultLayout,
        budgetUsedTokens: Int = 0,
        durationSeconds: Double = 0,
        wallPreset: String = "standard",
        enforceDrain: Bool = false,
        isActive: Bool = false
    ) throws -> RoomSealedSnapshot {
        guard !enforceDrain || !isActive else {
            throw RoomLifecycleError.cannotSealActiveRoom(roomID: roomID)
        }

        try vaultManager.ensureLayout(at: layout)
        let stats = vaultManager.inspect(layout: layout)
        let curated = (try? fileManager.contentsOfDirectory(atPath: layout.curatedDir.path)) ?? []
        let skills = (try? fileManager.contentsOfDirectory(atPath: layout.skillsDir.path)) ?? []

        let snapshot = RoomSealedSnapshot(
            roomID: roomID,
            tenant: tenant,
            sealedAt: Date(),
            state: .sealed,
            budgetUsedTokens: budgetUsedTokens,
            durationSeconds: durationSeconds,
            wallPreset: wallPreset,
            curatedArtifacts: curated.sorted(),
            skillNames: skills.sorted(),
            stats: stats
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: layout.snapshotFile, options: .atomic)
        return snapshot
    }

    /// snapshot.json 을 읽어 검증 후 아카이브 수행
    @discardableResult
    public func archive(layout: RoomVaultLayout) throws -> RoomSealedSnapshot {
        guard fileManager.fileExists(atPath: layout.snapshotFile.path) else {
            throw RoomLifecycleError.snapshotNotFound
        }
        let data = try Data(contentsOf: layout.snapshotFile)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(RoomSealedSnapshot.self, from: data)
        guard snapshot.state == .sealed else {
            throw RoomLifecycleError.unsealedRoomCannotBeArchived
        }
        return try archive(layout: layout, snapshot: snapshot)
    }

    /// 룸을 아카이브하여 raw/ 디렉토리를 정리하고 상태를 archived로 전환
    public func archive(
        layout: RoomVaultLayout,
        snapshot: RoomSealedSnapshot
    ) throws -> RoomSealedSnapshot {
        try cleanRawDirectory(at: layout.rawDir)

        let updatedStats = vaultManager.inspect(layout: layout)
        let archived = RoomSealedSnapshot(
            roomID: snapshot.roomID,
            tenant: snapshot.tenant,
            sealedAt: snapshot.sealedAt,
            state: .archived,
            budgetUsedTokens: snapshot.budgetUsedTokens,
            durationSeconds: snapshot.durationSeconds,
            wallPreset: snapshot.wallPreset,
            curatedArtifacts: snapshot.curatedArtifacts,
            skillNames: snapshot.skillNames,
            stats: updatedStats
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(archived)
        try data.write(to: layout.snapshotFile, options: .atomic)
        return archived
    }

    private func cleanRawDirectory(at rawDir: URL) throws {
        guard fileManager.fileExists(atPath: rawDir.path) else { return }
        let files = try fileManager.contentsOfDirectory(atPath: rawDir.path)
        for file in files {
            let filePath = rawDir.appendingPathComponent(file).path
            try fileManager.removeItem(atPath: filePath)
        }
    }
}

public enum RoomLifecycleError: Error, LocalizedError, Equatable {
    case cannotSealActiveRoom(roomID: String)
    case snapshotNotFound
    case unsealedRoomCannotBeArchived

    public var errorDescription: String? {
        switch self {
        case .cannotSealActiveRoom(let id):
            return "Cannot seal room '\(id)' while processes are actively executing. Drain or stop room first."
        case .snapshotNotFound:
            return "No sealed snapshot found in room vault."
        case .unsealedRoomCannotBeArchived:
            return "Room must be sealed before it can be archived."
        }
    }
}
