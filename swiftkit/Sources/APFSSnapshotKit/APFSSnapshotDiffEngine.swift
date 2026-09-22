import Foundation
import os

private let logger = Logger(subsystem: "net.ranode.swiftkit", category: "apfs-diff")

/// 변경 유형
public enum APFSChangeKind: String, Sendable, Equatable, Codable {
    case added
    case modified
    case deleted
}

/// 변경 항목
public struct APFSChangeItem: Sendable, Equatable {
    public let relativePath: String
    public let kind: APFSChangeKind
    public let previousSize: Int64
    public let currentSize: Int64
    public let previousModificationDate: Date?
    public let currentModificationDate: Date?

    public init(
        relativePath: String,
        kind: APFSChangeKind,
        previousSize: Int64 = 0,
        currentSize: Int64 = 0,
        previousModificationDate: Date? = nil,
        currentModificationDate: Date? = nil
    ) {
        self.relativePath = relativePath
        self.kind = kind
        self.previousSize = previousSize
        self.currentSize = currentSize
        self.previousModificationDate = previousModificationDate
        self.currentModificationDate = currentModificationDate
    }
}

/// 고속 변경 감지 리포트
public struct APFSDiffReport: Sendable, Equatable {
    public let changes: [APFSChangeItem]
    public let addedCount: Int
    public let modifiedCount: Int
    public let deletedCount: Int
    public let unmodifiedCount: Int
    public let totalChangedBytes: Int64
    public let scanDurationSeconds: Double

    public var totalChangesCount: Int {
        addedCount + modifiedCount + deletedCount
    }

    public init(
        changes: [APFSChangeItem],
        addedCount: Int,
        modifiedCount: Int,
        deletedCount: Int,
        unmodifiedCount: Int,
        totalChangedBytes: Int64,
        scanDurationSeconds: Double
    ) {
        self.changes = changes
        self.addedCount = addedCount
        self.modifiedCount = modifiedCount
        self.deletedCount = deletedCount
        self.unmodifiedCount = unmodifiedCount
        self.totalChangedBytes = totalChangedBytes
        self.scanDurationSeconds = scanDurationSeconds
    }
}

/// APFS 기반 파일 메타데이터 스냅샷 엔트리
private struct FileMetadataEntry: Sendable {
    let relativePath: String
    let fileSize: Int64
    let modificationDate: Date?
    let isDirectory: Bool
    let inode: UInt64?
}

/// APFS 네이티브 고속 변경 감지 엔진
/// 두 개의 스냅샷 마운트 트리 또는 이전 스냅샷과 현재 작업 트리 사이의
/// 메타데이터(inode 번호, mtime, 크기)를 고속 비교하여 변경 목록을 실시간 산출
public enum APFSSnapshotDiffEngine: Sendable {
    private static let resourceKeys: Set<URLResourceKey> = [
        .fileSizeKey,
        .contentModificationDateKey,
        .isDirectoryKey,
        .fileResourceIdentifierKey,
        .isSymbolicLinkKey
    ]

    /// 기준 디렉터리(이전 스냅샷 등)와 대상 디렉터리(최신 스냅샷/작업트리) 간의 고속 차이 계산
    public static func computeDiff(
        baselineURL: URL,
        targetURL: URL,
        excludes: [String] = []
    ) throws -> APFSDiffReport {
        let startTime = Date()

        let baselineEntries = try scanDirectory(rootURL: baselineURL, excludes: excludes)
        let targetEntries = try scanDirectory(rootURL: targetURL, excludes: excludes)

        var changes: [APFSChangeItem] = []
        var addedCount = 0
        var modifiedCount = 0
        var deletedCount = 0
        var unmodifiedCount = 0
        var totalChangedBytes: Int64 = 0

        // 1) Target 항목들을 순회하며 Added / Modified / Unmodified 분류
        for (relPath, targetEntry) in targetEntries {
            if let baselineEntry = baselineEntries[relPath] {
                // 두 곳 모두 존재: 변경 여부 비교
                let isModified = checkIsModified(baseline: baselineEntry, target: targetEntry)
                if isModified {
                    modifiedCount += 1
                    totalChangedBytes += targetEntry.fileSize
                    changes.append(APFSChangeItem(
                        relativePath: relPath,
                        kind: .modified,
                        previousSize: baselineEntry.fileSize,
                        currentSize: targetEntry.fileSize,
                        previousModificationDate: baselineEntry.modificationDate,
                        currentModificationDate: targetEntry.modificationDate
                    ))
                } else {
                    unmodifiedCount += 1
                }
            } else {
                // Target에만 존재: Added
                addedCount += 1
                totalChangedBytes += targetEntry.fileSize
                changes.append(APFSChangeItem(
                    relativePath: relPath,
                    kind: .added,
                    previousSize: 0,
                    currentSize: targetEntry.fileSize,
                    previousModificationDate: nil,
                    currentModificationDate: targetEntry.modificationDate
                ))
            }
        }

        // 2) Baseline에만 있고 Target에 없는 항목: Deleted
        for (relPath, baselineEntry) in baselineEntries {
            if targetEntries[relPath] == nil {
                deletedCount += 1
                changes.append(APFSChangeItem(
                    relativePath: relPath,
                    kind: .deleted,
                    previousSize: baselineEntry.fileSize,
                    currentSize: 0,
                    previousModificationDate: baselineEntry.modificationDate,
                    currentModificationDate: nil
                ))
            }
        }

        let duration = Date().timeIntervalSince(startTime)

        return APFSDiffReport(
            changes: changes,
            addedCount: addedCount,
            modifiedCount: modifiedCount,
            deletedCount: deletedCount,
            unmodifiedCount: unmodifiedCount,
            totalChangedBytes: totalChangedBytes,
            scanDurationSeconds: duration
        )
    }

    private static func checkIsModified(baseline: FileMetadataEntry, target: FileMetadataEntry) -> Bool {
        if baseline.isDirectory != target.isDirectory {
            return true
        }
        if baseline.isDirectory {
            return false // 디렉터리 자체는 하위 파일 비교로 판단
        }
        if baseline.fileSize != target.fileSize {
            return true
        }
        if let baseDate = baseline.modificationDate, let targetDate = target.modificationDate {
            if abs(baseDate.timeIntervalSince(targetDate)) >= 1.0 {
                return true
            }
        }
        return false
    }

    private static func scanDirectory(
        rootURL: URL,
        excludes: [String]
    ) throws -> [String: FileMetadataEntry] {
        var results: [String: FileMetadataEntry] = [:]
        let fm = FileManager.default
        let resolvedRoot = rootURL.resolvingSymlinksInPath()
        guard fm.fileExists(atPath: resolvedRoot.path) else {
            return results
        }

        let rootPath = resolvedRoot.path
        let prefixLength = rootPath.hasSuffix("/") ? rootPath.count : rootPath.count + 1

        guard let enumerator = fm.enumerator(
            at: resolvedRoot,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsPackageDescendants]
        ) else {
            return results
        }

        for case let fileURL as URL in enumerator {
            let resolvedFileURL = fileURL.resolvingSymlinksInPath()
            let fullPath = resolvedFileURL.path
            guard fullPath.hasPrefix(rootPath) else { continue }

            let relativePath: String
            if fullPath.count >= prefixLength {
                relativePath = String(fullPath.dropFirst(prefixLength))
            } else {
                relativePath = resolvedFileURL.lastPathComponent
            }
            if relativePath.isEmpty { continue }

            // 제외 필터 검사
            var shouldExclude = false
            for exc in excludes {
                if relativePath == exc || relativePath.hasPrefix("\(exc)/") || fileURL.lastPathComponent == exc {
                    shouldExclude = true
                    break
                }
            }
            if shouldExclude {
                enumerator.skipDescendants()
                continue
            }

            let values: URLResourceValues?
            do {
                values = try fileURL.resourceValues(forKeys: resourceKeys)
            } catch {
                values = nil
            }
            let isDir = values?.isDirectory ?? false
            let fileSize = Int64(values?.fileSize ?? 0)
            let mtime = values?.contentModificationDate
            var st = stat()
            let inode: UInt64? = (stat(fileURL.path, &st) == 0) ? UInt64(st.st_ino) : nil

            results[relativePath] = FileMetadataEntry(
                relativePath: relativePath,
                fileSize: fileSize,
                modificationDate: mtime,
                isDirectory: isDir,
                inode: inode
            )
        }

        return results
    }
}
