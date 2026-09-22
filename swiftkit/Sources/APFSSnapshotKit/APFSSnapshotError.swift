import Foundation

/// APFS 스냅샷 작업 중 발생할 수 있는 표준 에러
public enum APFSSnapshotError: LocalizedError, Sendable, Equatable {
    case volumeDetectionFailed(String)
    case unsupportedFileSystem(String)
    case snapshotCreationFailed(String)
    case snapshotNotFound(String)
    case mountFailed(String)
    case unmountFailed(String)
    case snapshotDeletionFailed(String)
    case pathMappingFailed(String)
    case sessionAlreadyActive
    case sessionNotActive
    case commandExecutionFailed(cmd: String, exitCode: Int32, stderr: String)

    public var errorDescription: String? {
        switch self {
        case .volumeDetectionFailed(let msg):
            return "APFS volume detection failed: \(msg)"
        case .unsupportedFileSystem(let fs):
            return "File system '\(fs)' does not support native APFS snapshots. Only native APFS is supported."
        case .snapshotCreationFailed(let msg):
            return "Failed to create APFS local snapshot: \(msg)"
        case .snapshotNotFound(let name):
            return "APFS snapshot '\(name)' not found."
        case .mountFailed(let msg):
            return "Failed to mount APFS snapshot: \(msg)"
        case .unmountFailed(let msg):
            return "Failed to unmount APFS snapshot: \(msg)"
        case .snapshotDeletionFailed(let msg):
            return "Failed to delete APFS snapshot: \(msg)"
        case .pathMappingFailed(let path):
            return "Failed to resolve snapshot path for original source path: \(path)"
        case .sessionAlreadyActive:
            return "An APFS point-in-time snapshot session is already active."
        case .sessionNotActive:
            return "No APFS point-in-time snapshot session is currently active."
        case .commandExecutionFailed(let cmd, let exitCode, let stderr):
            return "Command '\(cmd)' failed with exit code \(exitCode): \(stderr)"
        }
    }
}
