import Foundation

/// SSOT configuration constants for BackupTransport.
public enum BackupTransportConfig {
    /// Default execution timeout in seconds (2 hours).
    public static let defaultExecutionTimeout: TimeInterval = 7200.0
}

/// Options configuring backup transport operations.
public struct BackupTransportOptions: Sendable, Equatable {
    public let dryRun: Bool
    public let canHardLink: Bool
    public let timeout: TimeInterval
    public let ignorePartialErrors: Bool
    public let materializeFiles: Bool

    public init(
        dryRun: Bool = false,
        canHardLink: Bool = true,
        timeout: TimeInterval = BackupTransportConfig.defaultExecutionTimeout,
        ignorePartialErrors: Bool = false,
        materializeFiles: Bool = true
    ) {
        self.dryRun = dryRun
        self.canHardLink = canHardLink
        self.timeout = timeout
        self.ignorePartialErrors = ignorePartialErrors
        self.materializeFiles = materializeFiles
    }
}

/// Execution result metrics and status from a backup transport.
public struct BackupTransportResult: Sendable, Equatable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32
    public let durationSeconds: Double
    public let totalFiles: Int
    public let totalBytes: Int64
    public let transferredBytes: Int64
    public let isPartial: Bool

    public init(
        stdout: String,
        stderr: String,
        exitCode: Int32,
        durationSeconds: Double,
        totalFiles: Int,
        totalBytes: Int64,
        transferredBytes: Int64? = nil,
        isPartial: Bool = false
    ) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
        self.durationSeconds = durationSeconds
        self.totalFiles = totalFiles
        self.totalBytes = totalBytes
        self.transferredBytes = transferredBytes ?? totalBytes
        self.isPartial = isPartial
    }
}

/// Real-time progress update during backup transport.
public struct BackupProgressUpdate: Sendable, Codable, Equatable {
    public let currentFile: String
    public let transferredBytes: Int64
    public let totalEstimatedBytes: Int64
    public let percent: Double
    public let speedMBps: Double
    public let estimatedRemainingSeconds: TimeInterval?
    public let elapsedSeconds: TimeInterval?

    public var etaSeconds: TimeInterval? { estimatedRemainingSeconds }

    public init(
        currentFile: String,
        transferredBytes: Int64 = 0,
        totalEstimatedBytes: Int64 = 0,
        percent: Double = 0.0,
        speedMBps: Double = 0.0,
        estimatedRemainingSeconds: TimeInterval? = nil,
        elapsedSeconds: TimeInterval? = nil
    ) {
        self.currentFile = currentFile
        self.transferredBytes = transferredBytes
        self.totalEstimatedBytes = totalEstimatedBytes
        self.percent = percent
        self.speedMBps = speedMBps
        self.estimatedRemainingSeconds = estimatedRemainingSeconds
        self.elapsedSeconds = elapsedSeconds
    }

    /// Helper calculating progress percentage, transfer rate, and ETA.
    public static func calculating(
        currentFile: String,
        transferredBytes: Int64,
        totalEstimatedBytes: Int64,
        elapsedSeconds: TimeInterval
    ) -> BackupProgressUpdate {
        let speed: Double
        if elapsedSeconds > 0.001 && transferredBytes > 0 {
            let s = (Double(transferredBytes) / 1_048_576.0) / elapsedSeconds
            speed = s.isFinite && !s.isNaN ? max(0.0, s) : 0.0
        } else {
            speed = 0.0
        }

        let calculatedPercent: Double
        if totalEstimatedBytes > 0 {
            let p = Double(transferredBytes) / Double(totalEstimatedBytes)
            calculatedPercent = p.isFinite && !p.isNaN ? min(1.0, max(0.0, p)) : 0.0
        } else {
            calculatedPercent = 0.0
        }

        let remainingSec: TimeInterval?
        if speed > 0 && totalEstimatedBytes > transferredBytes {
            let remainingMB = Double(totalEstimatedBytes - transferredBytes) / 1_048_576.0
            let sec = remainingMB / speed
            if sec.isFinite && !sec.isNaN && sec >= 0 {
                remainingSec = min(sec, 86400 * 365)
            } else {
                remainingSec = nil
            }
        } else {
            remainingSec = nil
        }

        return BackupProgressUpdate(
            currentFile: currentFile,
            transferredBytes: transferredBytes,
            totalEstimatedBytes: totalEstimatedBytes,
            percent: calculatedPercent,
            speedMBps: speed,
            estimatedRemainingSeconds: remainingSec,
            elapsedSeconds: elapsedSeconds
        )
    }
}

/// Abstract transport protocol for backup engines (rsync, APFS snapshot cloning, modern chunk dedup, etc.).
public protocol BackupTransport: Sendable {
    func execute(
        sourceURL: URL,
        destinationURL: URL,
        linkDestURL: URL?,
        excludes: [String],
        options: BackupTransportOptions,
        progressHandler: (@Sendable (BackupProgressUpdate) -> Void)?
    ) async throws -> BackupTransportResult
}
