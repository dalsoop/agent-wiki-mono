import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// 고속 파일시스템 가비지 컬렉터 (Storage GC & Orphan Cleaner Engine)
public enum FastStorageGC: Sendable {

    static let sessionContainerNames: Set<String> = [
        "sandboxes", "sessions", "runs", "workers"
    ]

    // MARK: - 프로세스 생존 판정

    /// PID 유효성 및 생존 상태 확인 (kill 0 신호 전달)
    public static func isProcessAlive(_ pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    // MARK: - 통합 가비지 컬렉션

    /// 지정된 루트 디렉터리 내의 임시 잔류 파일, 고아 세션 디렉터리, 빈 디렉터리를 스윕
    public static func collectGarbage(
        at rootPath: String,
        options: FastStorageGCOptions = .default,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) throws -> FastStorageGCReport {
        guard fileManager.fileExists(atPath: rootPath) else {
            return FastStorageGCReport()
        }

        var report = FastStorageGCReport()

        // 1. 임시 잔류 파일 정리
        let tempReport = try pruneTemporaryFiles(
            at: rootPath,
            options: options,
            fileManager: fileManager,
            now: now
        )
        mergeReports(into: &report, source: tempReport)

        // 2. 고아 세션 디렉터리 감지 및 정리
        let sessionReport = try pruneOrphanSessions(
            at: rootPath,
            options: options,
            fileManager: fileManager,
            now: now
        )
        mergeReports(into: &report, source: sessionReport)

        // 3. 빈 디렉터리 정리
        cleanupEmptyDirectoriesIfConfigured(
            rootPath: rootPath,
            options: options,
            report: &report,
            fileManager: fileManager
        )

        return report
    }

    // MARK: - 임시 파일 정리

    /// 임시 파일 확장자/접두사 및 지정된 수명을 초과한 파일 제거
    public static func pruneTemporaryFiles(
        at rootPath: String,
        options: FastStorageGCOptions = .default,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) throws -> FastStorageGCReport {
        guard fileManager.fileExists(atPath: rootPath) else {
            return FastStorageGCReport()
        }

        let entries = try FastDirectoryScanner.scan(root: rootPath, recursive: true)
        var report = FastStorageGCReport(scannedCount: entries.count)

        for entry in entries {
            processTemporaryEntry(
                entry,
                options: options,
                report: &report,
                fileManager: fileManager,
                now: now
            )
        }

        return report
    }

    // MARK: - 고아 세션 디렉터리 정리

    /// PID 사망 또는 수명 만료된 고아 세션/샌드박스 디렉터리 감지 및 제거
    public static func pruneOrphanSessions(
        at rootPath: String,
        options: FastStorageGCOptions = .default,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) throws -> FastStorageGCReport {
        guard fileManager.fileExists(atPath: rootPath) else {
            return FastStorageGCReport()
        }

        let candidateDirs = try findSessionCandidates(at: rootPath, fileManager: fileManager)
        var report = FastStorageGCReport(scannedCount: candidateDirs.count)

        for dirPath in candidateDirs {
            processSessionDirectory(
                dirPath,
                options: options,
                report: &report,
                fileManager: fileManager,
                now: now
            )
        }

        return report
    }

    // MARK: - 빈 디렉터리 정리

    /// 비어있는 디렉터리들을 재귀적으로 정리 (루트 디렉터리 자체는 보존)
    public static func pruneEmptyDirectories(
        at rootPath: String,
        dryRun: Bool = false,
        fileManager: FileManager = .default
    ) throws -> [String] {
        guard fileManager.fileExists(atPath: rootPath) else { return [] }
        var pruned: [String] = []
        var errors: [String] = []
        try pruneEmptyDirectoriesRecursively(
            at: rootPath,
            isRoot: true,
            dryRun: dryRun,
            pruned: &pruned,
            errors: &errors,
            fileManager: fileManager
        )
        return pruned
    }
}
