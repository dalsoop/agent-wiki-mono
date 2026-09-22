import Foundation
import os

private let logger = Logger(subsystem: "net.ranode.swiftkit", category: "apfs-transport-engine")

/// APFS 스냅샷 기반 전송 실행 결과
public struct APFSSnapshotExecutionResult<T: Sendable>: Sendable {
    public let result: T
    public let snapshot: APFSSnapshot?
    public let snapshotMountPoint: URL?
    public let snapshotSetupDuration: TimeInterval
    public let payloadDuration: TimeInterval
    public let totalDuration: TimeInterval
    public let usedLiveFallback: Bool

    public init(
        result: T,
        snapshot: APFSSnapshot?,
        snapshotMountPoint: URL?,
        snapshotSetupDuration: TimeInterval,
        payloadDuration: TimeInterval,
        totalDuration: TimeInterval,
        usedLiveFallback: Bool = false
    ) {
        self.result = result
        self.snapshot = snapshot
        self.snapshotMountPoint = snapshotMountPoint
        self.snapshotSetupDuration = snapshotSetupDuration
        self.payloadDuration = payloadDuration
        self.totalDuration = totalDuration
        self.usedLiveFallback = usedLiveFallback
    }
}

/// APFS 스냅샷 기반 전송 오케스트레이션 엔진
public final class APFSSnapshotTransportEngine: Sendable {
    private let manager: any APFSSnapshotManaging
    private let allowLiveFallback: Bool
    private let cleanupSnapshotOnClose: Bool

    public init(
        manager: any APFSSnapshotManaging = APFSSnapshotManager(),
        allowLiveFallback: Bool = false,
        cleanupSnapshotOnClose: Bool = true
    ) {
        self.manager = manager
        self.allowLiveFallback = allowLiveFallback
        self.cleanupSnapshotOnClose = cleanupSnapshotOnClose
    }

    /// 정적 시점 스냅샷을 생성/마운트한 후 클로저 내에서 정적 소스 경로를 제공하여 전송을 실행
    public func executeWithStaticSnapshot<T: Sendable>(
        sourceURL: URL,
        operation: @Sendable (_ staticSourceURL: URL) async throws -> T
    ) async throws -> APFSSnapshotExecutionResult<T> {
        let overallStart = Date()
        let setupStart = Date()

        do {
            let session = APFSPointInTimeSession(
                sourceURL: sourceURL,
                configuration: APFSPointInTimeSessionConfiguration(
                    cleanupSnapshotOnClose: cleanupSnapshotOnClose,
                    readOnly: true
                ),
                manager: manager
            )
            try await session.begin()
            let setupDuration = Date().timeIntervalSince(setupStart)

            let staticSourceURL: URL
            let operationResult: T
            let payloadDuration: TimeInterval
            let snapshot: APFSSnapshot?
            let snapshotMountPoint: URL?

            do {
                staticSourceURL = try await session.resolveSnapshotURL(for: sourceURL)
                logger.info("Executing snapshot transfer from static source: \(staticSourceURL.path)")

                let payloadStart = Date()
                operationResult = try await operation(staticSourceURL)
                payloadDuration = Date().timeIntervalSince(payloadStart)
                snapshot = await session.activeSnapshot
                snapshotMountPoint = await session.mountPoint
                await session.end()
            } catch {
                await session.end()
                throw error
            }

            let totalDuration = Date().timeIntervalSince(overallStart)

            return APFSSnapshotExecutionResult(
                result: operationResult,
                snapshot: snapshot,
                snapshotMountPoint: snapshotMountPoint,
                snapshotSetupDuration: setupDuration,
                payloadDuration: payloadDuration,
                totalDuration: totalDuration,
                usedLiveFallback: false
            )
        } catch {
            if allowLiveFallback {
                logger.warning("APFS snapshot creation/mount failed (\(error.localizedDescription)). Falling back to live source: \(sourceURL.path)")
                let payloadStart = Date()
                let operationResult = try await operation(sourceURL)
                let payloadDuration = Date().timeIntervalSince(payloadStart)
                let totalDuration = Date().timeIntervalSince(overallStart)

                return APFSSnapshotExecutionResult(
                    result: operationResult,
                    snapshot: nil,
                    snapshotMountPoint: nil,
                    snapshotSetupDuration: 0,
                    payloadDuration: payloadDuration,
                    totalDuration: totalDuration,
                    usedLiveFallback: true
                )
            } else {
                throw error
            }
        }
    }
}
