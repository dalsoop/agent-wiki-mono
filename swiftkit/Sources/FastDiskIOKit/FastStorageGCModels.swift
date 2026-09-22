import Foundation

/// 가비지 컬렉션 결과 보고서
public struct FastStorageGCReport: Sendable, Equatable, Codable {
    public var prunedFiles: [String]
    public var prunedDirectories: [String]
    public var reclaimedBytes: Int64
    public var errors: [String]
    public var scannedCount: Int

    public init(
        prunedFiles: [String] = [],
        prunedDirectories: [String] = [],
        reclaimedBytes: Int64 = 0,
        errors: [String] = [],
        scannedCount: Int = 0
    ) {
        self.prunedFiles = prunedFiles
        self.prunedDirectories = prunedDirectories
        self.reclaimedBytes = reclaimedBytes
        self.errors = errors
        self.scannedCount = scannedCount
    }

    public var isClean: Bool { errors.isEmpty }
}

/// 가비지 컬렉션 옵션
public struct FastStorageGCOptions: Sendable, Equatable {
    /// 임시 파일 최대 허용 수명 (초 단위, 기본 24시간 = 86400초). 이보다 오래된 임시 파일 제거.
    public var maxTemporaryAge: TimeInterval
    /// 고아 세션 디렉터리 최대 허용 수명 (초 단위, 기본 3일 = 259200초). 이보다 오래된 세션 디렉터리 제거.
    public var maxOrphanSessionAge: TimeInterval
    /// 감지할 임시 파일 확장자 목록
    public var temporaryExtensions: Set<String>
    /// 감지할 임시 파일 접두사 목록
    public var temporaryPrefixes: [String]
    /// 감지할 세션/작업 디렉터리 접두사 목록
    public var sessionDirectoryPrefixes: [String]
    /// 활성 프로세스 PID 집합 (nil이면 시스템에 kill(pid, 0) 질의)
    public var activePIDs: Set<pid_t>?
    /// 실제 삭제 없이 시뮬레이션만 수행 여부
    public var dryRun: Bool
    /// 빈 디렉터리 자동 정리 여부
    public var removeEmptyDirectories: Bool

    public init(
        maxTemporaryAge: TimeInterval = 86400,
        maxOrphanSessionAge: TimeInterval = 259200,
        temporaryExtensions: Set<String> = ["tmp", "temp", "swp", "bak", "part", "lock.old", "download"],
        temporaryPrefixes: [String] = [".tmp-", "tmp.", ".swap-", "scratch-", "temp-"],
        sessionDirectoryPrefixes: [String] = ["session-", "sandbox-", "run-", "proc-", "worker-", "orphan-"],
        activePIDs: Set<pid_t>? = nil,
        dryRun: Bool = false,
        removeEmptyDirectories: Bool = true
    ) {
        self.maxTemporaryAge = maxTemporaryAge
        self.maxOrphanSessionAge = maxOrphanSessionAge
        self.temporaryExtensions = temporaryExtensions
        self.temporaryPrefixes = temporaryPrefixes
        self.sessionDirectoryPrefixes = sessionDirectoryPrefixes
        self.activePIDs = activePIDs
        self.dryRun = dryRun
        self.removeEmptyDirectories = removeEmptyDirectories
    }

    public static let `default` = FastStorageGCOptions()
}
