import Foundation
import StateRootKit

public struct ArchivedRoomInfo: Codable, Sendable, Identifiable, Equatable {
    public var id: String { archiveName }
    public let archiveName: String
    public let originalRoomID: String
    public let tenantSlug: String
    public let archivedAt: Date
    public let purgeAfter: Date
    public let sizeBytes: Int64
    public let isExpired: Bool

    public init(
        archiveName: String,
        originalRoomID: String,
        tenantSlug: String,
        archivedAt: Date,
        purgeAfter: Date,
        sizeBytes: Int64,
        isExpired: Bool = false
    ) {
        self.archiveName = archiveName
        self.originalRoomID = originalRoomID
        self.tenantSlug = tenantSlug
        self.archivedAt = archivedAt
        self.purgeAfter = purgeAfter
        self.sizeBytes = sizeBytes
        self.isExpired = isExpired
    }
}

public enum RoomArchiveError: Error, LocalizedError, Equatable {
    case roomNotFound(String)
    case archiveNotFound(String)
    case invalidMeta(String, String)

    public var errorDescription: String? {
        switch self {
        case .roomNotFound(let roomID):
            return "룸 디렉터리를 찾을 수 없습니다: \(roomID)"
        case .archiveNotFound(let archiveName):
            return "아카이브를 찾을 수 없습니다: \(archiveName)"
        case .invalidMeta(let archiveName, let detail):
            return "아카이브 메타데이터가 깨졌습니다 (\(archiveName)): \(detail)"
        }
    }
}

struct ArchiveMeta: Codable, Equatable {
    var archiveName: String
    var originalRoomID: String
    var archivedAt: TimeInterval
    var retentionDays: Double
    var purgeAfter: TimeInterval
}

public enum RoomArchive {
    public static let archiveDirectoryName = ".archive"

    public static func archiveRoot(homeDirectory: String = StateRootKit.resolveHost(environment: [:])) -> URL {
        SandboxLayout.url(
            "\(SandboxContext.sandboxesDirectoryName)/\(archiveDirectoryName)",
            homeDirectory: homeDirectory
        )
    }

    /// 활성 룸을 7일 보관소(.archive/)로 이동시킨다 (Soft-Archive).
    @discardableResult
    public static func archive(
        roomID: String,
        homeDirectory: String = StateRootKit.resolveHost(environment: [:]),
        retentionDays: Double = 7.0,
        now: Date = Date()
    ) throws -> String {
        let sandboxesRoot = SandboxLayout.url(
            SandboxContext.sandboxesDirectoryName,
            homeDirectory: homeDirectory
        )
        let sourceRoomURL = sandboxesRoot.appendingPathComponent(roomID, isDirectory: true)
        let archiveRootURL = archiveRoot(homeDirectory: homeDirectory)

        let fm = FileManager.default
        guard fm.fileExists(atPath: sourceRoomURL.path) else {
            throw RoomArchiveError.roomNotFound(roomID)
        }

        try fm.createDirectory(at: archiveRootURL, withIntermediateDirectories: true)

        let timestamp = Int(now.timeIntervalSince1970)
        let archiveName = "\(roomID)_\(timestamp)"
        let targetArchiveURL = archiveRootURL.appendingPathComponent(archiveName, isDirectory: true)

        let purgeDate = now.addingTimeInterval(retentionDays * 86400)
        let meta = ArchiveMeta(
            archiveName: archiveName,
            originalRoomID: roomID,
            archivedAt: now.timeIntervalSince1970,
            retentionDays: retentionDays,
            purgeAfter: purgeDate.timeIntervalSince1970
        )
        let metaURL = sourceRoomURL.appendingPathComponent(".archive_meta.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let metaData = try encoder.encode(meta)
        try metaData.write(to: metaURL, options: .atomic)

        try fm.moveItem(at: sourceRoomURL, to: targetArchiveURL)
        return archiveName
    }

    /// 아카이브 보관소에 보관된 모든 룸 목록을 스캔한다. 보관소가 없으면 빈 배열.
    public static func listArchived(
        homeDirectory: String = StateRootKit.resolveHost(environment: [:]),
        now: Date = Date()
    ) throws -> [ArchivedRoomInfo] {
        let archiveRootURL = archiveRoot(homeDirectory: homeDirectory)
        let fm = FileManager.default
        guard fm.fileExists(atPath: archiveRootURL.path) else { return [] }

        let items = try fm.contentsOfDirectory(
            at: archiveRootURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .totalFileSizeKey],
            options: [.skipsHiddenFiles]
        )

        var results: [ArchivedRoomInfo] = []
        for url in items {
            if let info = try info(forArchiveDirectory: url, now: now) {
                results.append(info)
            }
        }
        return results.sorted { $0.archivedAt > $1.archivedAt }
    }

    /// 7일 이상 경과하여 만료된 아카이브 룸을 영구 소각(Hard-Purge GC)한다.
    @discardableResult
    public static func pruneExpired(
        homeDirectory: String = StateRootKit.resolveHost(environment: [:]),
        now: Date = Date()
    ) throws -> [String] {
        let archived = try listArchived(homeDirectory: homeDirectory, now: now)
        let expired = archived.filter(\.isExpired)
        let archiveRootURL = archiveRoot(homeDirectory: homeDirectory)
        let fm = FileManager.default

        var purged: [String] = []
        for item in expired {
            let targetURL = archiveRootURL.appendingPathComponent(item.archiveName, isDirectory: true)
            try fm.removeItem(at: targetURL)
            purged.append(item.archiveName)
        }
        return purged
    }

    /// 아카이브된 룸을 활성 샌드박스로 다시 복원(Restore)한다.
    @discardableResult
    public static func restore(
        archiveName: String,
        homeDirectory: String = StateRootKit.resolveHost(environment: [:])
    ) throws -> String {
        let archiveRootURL = archiveRoot(homeDirectory: homeDirectory)
        let sourceArchiveURL = archiveRootURL.appendingPathComponent(archiveName, isDirectory: true)
        let sandboxesRoot = SandboxLayout.url(
            SandboxContext.sandboxesDirectoryName,
            homeDirectory: homeDirectory
        )

        let fm = FileManager.default
        guard fm.fileExists(atPath: sourceArchiveURL.path) else {
            throw RoomArchiveError.archiveNotFound(archiveName)
        }

        let originalRoom = archiveName.components(separatedBy: "_").dropLast().joined(separator: "_")
        let targetRoomID = originalRoom.isEmpty ? "restored-\(archiveName)" : originalRoom
        let targetRoomURL = sandboxesRoot.appendingPathComponent(targetRoomID, isDirectory: true)

        let metaURL = sourceArchiveURL.appendingPathComponent(".archive_meta.json")
        if fm.fileExists(atPath: metaURL.path) {
            try fm.removeItem(at: metaURL)
        }

        try fm.moveItem(at: sourceArchiveURL, to: targetRoomURL)
        return targetRoomID
    }

    private static func info(forArchiveDirectory url: URL, now: Date) throws -> ArchivedRoomInfo? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        let archiveName = url.lastPathComponent
        let originalRoom = archiveName.components(separatedBy: "_").dropLast().joined(separator: "_")
        let tenant = originalRoom.split(separator: "-").dropFirst().dropLast().joined(separator: "-")

        var archivedAt = Date()
        var purgeAfter = archivedAt.addingTimeInterval(7 * 86400)

        let metaURL = url.appendingPathComponent(".archive_meta.json")
        if FileManager.default.fileExists(atPath: metaURL.path) {
            do {
                let data = try Data(contentsOf: metaURL)
                let meta = try JSONDecoder().decode(ArchiveMeta.self, from: data)
                archivedAt = Date(timeIntervalSince1970: meta.archivedAt)
                purgeAfter = Date(timeIntervalSince1970: meta.purgeAfter)
            } catch {
                throw RoomArchiveError.invalidMeta(archiveName, error.localizedDescription)
            }
        }

        let values = try url.resourceValues(forKeys: [.totalFileSizeKey])
        let size = Int64(values.totalFileSize ?? 0)

        return ArchivedRoomInfo(
            archiveName: archiveName,
            originalRoomID: originalRoom.isEmpty ? archiveName : originalRoom,
            tenantSlug: tenant.isEmpty ? "default" : tenant,
            archivedAt: archivedAt,
            purgeAfter: purgeAfter,
            sizeBytes: size,
            isExpired: now > purgeAfter
        )
    }
}
