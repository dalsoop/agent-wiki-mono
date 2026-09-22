import Foundation
import SkillRegistryKit
import StateRootKit

/// 룸 내부의 4대 격리 영역 레이아웃 계약.
/// - raw/     : 세션 로그, PTY 터미널 버퍼, 툴 호출 trace (휘발성/아카이브 대상)
/// - curated/ : 검증된 최종 산출물, 해결 코드 (보존 대상)
/// - memory/  : per-agent 대화/작업 맥락 기억
/// - skills/  : 룸 안에서 정제/오버라이드된 SKILL.md
public struct RoomVaultLayout: Sendable, Equatable {
    public let roomURL: URL

    public var rawDir: URL {
        roomURL.appendingPathComponent("raw", isDirectory: true)
    }

    public var curatedDir: URL {
        roomURL.appendingPathComponent("curated", isDirectory: true)
    }

    public var memoryDir: URL {
        roomURL.appendingPathComponent("memory", isDirectory: true)
    }

    public var skillsDir: URL {
        roomURL.appendingPathComponent("skills", isDirectory: true)
    }

    /// 인지 원장(가계산, 델타, 시냅스 그래프) 디렉터리
    public var cognitiveDir: URL {
        roomURL.appendingPathComponent("cognitive", isDirectory: true)
    }

    public var precomputeFile: URL {
        cognitiveDir.appendingPathComponent("precompute.json")
    }

    public var deltaFile: URL {
        cognitiveDir.appendingPathComponent("delta.json")
    }

    public var synapsesFile: URL {
        cognitiveDir.appendingPathComponent("synapses.json")
    }

    public var snapshotFile: URL {
        roomURL.appendingPathComponent("snapshot.json")
    }

    /// 앱 차용 원장 (append-only JSONL)
    public var appBorrowsFile: URL {
        rawDir.appendingPathComponent(RoomAppBorrowStore.fileName)
    }

    public var receiptsDir: URL {
        roomURL.appendingPathComponent("receipts", isDirectory: true)
    }

    public func receiptFile(for skillName: String) -> URL {
        receiptsDir.appendingPathComponent("\(skillName).json")
    }

    public var receiptFile: URL {
        roomURL.appendingPathComponent("receipt.json")
    }

    public init(roomURL: URL) {
        self.roomURL = roomURL
    }

    /// 표준 방 경로로부터 레이아웃 구성
    public static func forRoom(
        tenant: String,
        roomID: String,
        environment: [String: String] = [:],
        homeDirectory: String = NSHomeDirectory()
    ) -> RoomVaultLayout {
        let roomURL = RoomPaths.roomDirectory(
            tenant: tenant,
            roomID: roomID,
            environment: environment,
            homeDirectory: homeDirectory
        )
        return RoomVaultLayout(roomURL: roomURL)
    }
}

/// 룸 볼트 관리 계약
public struct RoomVaultManager: Sendable {
    private var fileManager: FileManager { .default }

    public init() {}

    /// 4대 폴더 구조가 없으면 원자적으로 생성
    @discardableResult
    public func ensureLayout(at layout: RoomVaultLayout) throws -> RoomVaultLayout {
        let dirs = [layout.roomURL, layout.rawDir, layout.curatedDir, layout.memoryDir, layout.skillsDir, layout.cognitiveDir]
        for dir in dirs {
            if !fileManager.fileExists(atPath: dir.path) {
                try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
        return layout
    }

    /// curated 영역에 산출물 파일 저장
    public func writeCurated(
        relativePath: String,
        data: Data,
        in layout: RoomVaultLayout
    ) throws -> URL {
        try ensureLayout(at: layout)
        let target = layout.curatedDir.appendingPathComponent(relativePath)
        let parent = target.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parent.path) {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        try data.write(to: target, options: .atomic)
        return target
    }

    /// skills 영역에 스킬 폴더 및 SKILL.md 생성
    public func writeSkill(
        name: String,
        content: String,
        in layout: RoomVaultLayout
    ) throws -> URL {
        try ensureLayout(at: layout)
        let skillFolder = layout.skillsDir.appendingPathComponent(name, isDirectory: true)
        if !fileManager.fileExists(atPath: skillFolder.path) {
            try fileManager.createDirectory(at: skillFolder, withIntermediateDirectories: true)
        }
        let skillFile = skillFolder.appendingPathComponent("SKILL.md")
        try Data(content.utf8).write(to: skillFile, options: .atomic)
        return skillFile
    }

    /// 현재 룸 볼트의 요약 통계
    public func inspect(layout: RoomVaultLayout) -> RoomVaultStats {
        let curatedCount: Int
        do {
            curatedCount = try fileManager.contentsOfDirectory(atPath: layout.curatedDir.path).count
        } catch {
            curatedCount = 0
        }

        let memoryCount: Int
        do {
            memoryCount = try fileManager.contentsOfDirectory(atPath: layout.memoryDir.path).count
        } catch {
            memoryCount = 0
        }

        let skillFolders: [String]
        do {
            skillFolders = try fileManager.contentsOfDirectory(atPath: layout.skillsDir.path)
        } catch {
            skillFolders = []
        }

        let rawSize = directorySize(url: layout.rawDir)

        return RoomVaultStats(
            curatedArtifactCount: curatedCount,
            memoryItemCount: memoryCount,
            skillCount: skillFolders.count,
            rawSizeBytes: rawSize
        )
    }

    private func directorySize(url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            do {
                if let size = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    total += Int64(size)
                }
            } catch {
                continue
            }
        }
        return total
    }

    /// 룸 볼트 전용 스킬 캐스케이드 프록시 생성
    public func skillProxy(
        for layout: RoomVaultLayout,
        tenantSkillsURL: URL? = nil,
        globalRegistry: SkillRegistry = SkillRegistry()
    ) -> SkillProxy {
        SkillProxy(
            roomSkillsURL: layout.skillsDir,
            tenantSkillsURL: tenantSkillsURL,
            globalRegistry: globalRegistry
        )
    }

    /// 룸 볼트 상태 요약 (스냅샷 및 영수증 해석 포함)
    public func summary(roomID: String, tenantID: String, in layout: RoomVaultLayout) -> RoomVaultSummary {
        let stats = inspect(layout: layout)
        let lifecycle = readLifecycle(from: layout.snapshotFile)
        let receiptInfo = readReceiptsSummary(layout: layout)
        let curated = (try? fileManager.contentsOfDirectory(atPath: layout.curatedDir.path)) ?? []
        let skills = (try? fileManager.contentsOfDirectory(atPath: layout.skillsDir.path)) ?? []

        return RoomVaultSummary(
            roomID: roomID,
            tenantID: tenantID,
            stats: stats,
            lifecycleState: lifecycle,
            hasReceipt: receiptInfo.count > 0,
            receiptScope: receiptInfo.scope,
            receiptsCount: receiptInfo.count,
            hasAutoBumped: receiptInfo.hasAutoBumped,
            curatedArtifacts: curated.sorted(),
            localSkills: skills.sorted()
        )
    }

    private func readLifecycle(from snapshotURL: URL) -> RoomLifecycleState {
        guard let data = try? Data(contentsOf: snapshotURL) else { return .active }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(RoomSealedSnapshot.self, from: data))?.state ?? .active
    }

    private func readReceiptsSummary(layout: RoomVaultLayout) -> (count: Int, scope: String?, hasAutoBumped: Bool) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var count = 0
        var scope: String? = nil
        var autoBumped = false

        do {
            let files = try fileManager.contentsOfDirectory(atPath: layout.receiptsDir.path)
            let jsonFiles = files.filter { $0.hasSuffix(".json") }
            count = jsonFiles.count
            for file in jsonFiles {
                do {
                    let data = try Data(contentsOf: layout.receiptsDir.appendingPathComponent(file))
                    let r = try decoder.decode(RoomPromotionReceipt.self, from: data)
                    if scope == nil {
                        scope = r.scope.identifier
                    }
                    if r.resolution == "autoBumped" {
                        autoBumped = true
                    }
                } catch {
                    continue
                }
            }
        } catch {
            count = 0
        }

        guard count == 0, fileManager.fileExists(atPath: layout.receiptFile.path) else {
            return (count, scope, autoBumped)
        }

        do {
            let data = try Data(contentsOf: layout.receiptFile)
            let r = try decoder.decode(RoomPromotionReceipt.self, from: data)
            return (1, r.scope.identifier, r.resolution == "autoBumped")
        } catch {
            return (0, nil, false)
        }
    }
}

public struct RoomVaultStats: Sendable, Codable, Equatable {
    public let curatedArtifactCount: Int
    public let memoryItemCount: Int
    public let skillCount: Int
    public let rawSizeBytes: Int64

    public init(
        curatedArtifactCount: Int,
        memoryItemCount: Int,
        skillCount: Int,
        rawSizeBytes: Int64
    ) {
        self.curatedArtifactCount = curatedArtifactCount
        self.memoryItemCount = memoryItemCount
        self.skillCount = skillCount
        self.rawSizeBytes = rawSizeBytes
    }
}

/// 룸 볼트 조회 요약
public struct RoomVaultSummary: Sendable, Codable, Equatable {
    public let roomID: String
    public let tenantID: String
    public let stats: RoomVaultStats
    public let lifecycleState: RoomLifecycleState
    public let hasReceipt: Bool
    public let receiptScope: String?
    public let receiptsCount: Int
    public let hasAutoBumped: Bool
    public let curatedArtifacts: [String]
    public let localSkills: [String]

    public init(
        roomID: String,
        tenantID: String,
        stats: RoomVaultStats,
        lifecycleState: RoomLifecycleState,
        hasReceipt: Bool,
        receiptScope: String?,
        receiptsCount: Int = 0,
        hasAutoBumped: Bool = false,
        curatedArtifacts: [String],
        localSkills: [String]
    ) {
        self.roomID = roomID
        self.tenantID = tenantID
        self.stats = stats
        self.lifecycleState = lifecycleState
        self.hasReceipt = hasReceipt
        self.receiptScope = receiptScope
        self.receiptsCount = receiptsCount
        self.hasAutoBumped = hasAutoBumped
        self.curatedArtifacts = curatedArtifacts
        self.localSkills = localSkills
    }
}

extension RoomVaultLayout {
    /// 룸 볼트에 대한 단방향 캐스케이드 스킬 프록시 생성
    public func makeSkillProxy(
        tenant: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> SkillProxy {
        let tenantRoot = StateRootKit.tenantStateRoot(tenant: tenant, environment: environment)
        let tenantSkillsURL = URL(fileURLWithPath: tenantRoot, isDirectory: true)
            .appendingPathComponent("skills", isDirectory: true)
        return SkillProxy(
            roomSkillsURL: skillsDir,
            tenantSkillsURL: tenantSkillsURL
        )
    }
}
