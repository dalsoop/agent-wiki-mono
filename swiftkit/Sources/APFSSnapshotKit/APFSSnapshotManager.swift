import Foundation
import os
import CommandKit

private let logger = Logger(subsystem: "net.ranode.swiftkit", category: "apfs-manager")

/// APFS 스냅샷 관리 프로토콜
public protocol APFSSnapshotManaging: Sendable {
    /// 지정된 볼륨에 APFS 로컬 스냅샷 생성
    func createLocalSnapshot(volumePath: String) async throws -> APFSSnapshot

    /// 지정된 볼륨의 로컬 스냅샷 목록 조회
    func listLocalSnapshots(volumePath: String) async throws -> [APFSSnapshot]

    /// 스냅샷을 지정된 마운트 경로에 마운트 (기본 읽기 전용)
    func mountSnapshot(_ snapshot: APFSSnapshot, mountPoint: URL, readOnly: Bool) async throws

    /// 마운트 해제
    func unmountSnapshot(mountPoint: URL, force: Bool) async throws

    /// 로컬 스냅샷 삭제
    func deleteLocalSnapshot(_ snapshot: APFSSnapshot) async throws

    /// 특정 일자의 로컬 스냅샷 삭제
    func deleteLocalSnapshot(dateString: String) async throws

    /// 특정 경로가 마운트 지점인지 확인
    func isMounted(mountPoint: URL) async -> Bool
}

/// 기본 APFS 스냅샷 매니저 구현체
public final class APFSSnapshotManager: APFSSnapshotManaging, Sendable {
    private let runner: CommandRunning
    private let tmutilPath: String
    private let mountApfsPath: String
    private let umountPath: String
    private let diskutilPath: String

    public init(
        runner: CommandRunning = ProcessCommandRunner(),
        tmutilPath: String = "/usr/bin/tmutil",
        mountApfsPath: String = "/sbin/mount_apfs",
        umountPath: String = "/sbin/umount",
        diskutilPath: String = "/usr/sbin/diskutil"
    ) {
        self.runner = runner
        self.tmutilPath = tmutilPath
        self.mountApfsPath = mountApfsPath
        self.umountPath = umountPath
        self.diskutilPath = diskutilPath
    }

    // MARK: - 1. 스냅샷 생성 (tmutil localsnapshot)

    public func createLocalSnapshot(volumePath: String = "/") async throws -> APFSSnapshot {
        logger.info("Creating APFS local snapshot for volume: \(volumePath)")
        
        let normalizedVolume = (volumePath as NSString).standardizingPath
        var args = ["localsnapshot"]
        if normalizedVolume != "/" {
            args.append(normalizedVolume)
        }

        let result = await runner.run(tmutilPath, args, timeout: 10.0)
        guard result.exitCode == 0 else {
            let errorMsg = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? result.stdout
                : result.stderr
            throw APFSSnapshotError.snapshotCreationFailed("tmutil localsnapshot failed with exit code \(result.exitCode): \(errorMsg)")
        }

        // 디바이스 노드 추출 시도
        let deviceNode: String?
        do {
            deviceNode = try APFSVolumeDetector.detectVolume(for: URL(fileURLWithPath: normalizedVolume)).deviceNode
        } catch {
            deviceNode = nil
        }

        return try APFSSnapshotParser.parseCreatedSnapshot(
            from: result.stdout,
            volumePath: normalizedVolume,
            deviceNode: deviceNode
        )
    }

    // MARK: - 2. 스냅샷 목록 조회 (tmutil listlocalsnapshots)

    public func listLocalSnapshots(volumePath: String = "/") async throws -> [APFSSnapshot] {
        let normalizedVolume = (volumePath as NSString).standardizingPath
        let result = await runner.run(tmutilPath, ["listlocalsnapshots", normalizedVolume], timeout: 10.0)
        guard result.exitCode == 0 else {
            let errorMsg = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? result.stdout
                : result.stderr
            throw APFSSnapshotError.commandExecutionFailed(cmd: "tmutil listlocalsnapshots", exitCode: result.exitCode, stderr: errorMsg)
        }

        let deviceNode: String?
        do {
            deviceNode = try APFSVolumeDetector.detectVolume(for: URL(fileURLWithPath: normalizedVolume)).deviceNode
        } catch {
            deviceNode = nil
        }

        return APFSSnapshotParser.parseSnapshotList(
            from: result.stdout,
            volumePath: normalizedVolume,
            deviceNode: deviceNode
        )
    }

    // MARK: - 3. 스냅샷 마운트 (mount_apfs -s <snapshot> -o rdonly <deviceNode> <mountPoint>)

    public func mountSnapshot(_ snapshot: APFSSnapshot, mountPoint: URL, readOnly: Bool = true) async throws {
        logger.info("Mounting APFS snapshot \(snapshot.name) at \(mountPoint.path) (readOnly: \(readOnly))")

        // 1) 마운트 디렉터리 존재 보장
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true, attributes: [
            .posixPermissions: 0o700
        ])

        // 2) 디바이스 노드 확인
        var device = snapshot.deviceNode
        if device == nil || (device?.isEmpty ?? true) {
            do {
                device = try APFSVolumeDetector.detectVolume(for: URL(fileURLWithPath: snapshot.volumePath)).deviceNode
            } catch {
                device = nil
            }
        }
        guard let deviceNode = device, !deviceNode.isEmpty else {
            throw APFSSnapshotError.mountFailed("Cannot determine BSD device node for volume '\(snapshot.volumePath)'")
        }

        // 3) mount_apfs 실행
        var args: [String] = ["-s", snapshot.name]
        if readOnly {
            args.append(contentsOf: ["-o", "rdonly"])
        }
        args.append(deviceNode)
        args.append(mountPoint.path)

        let result = await runner.run(mountApfsPath, args, timeout: 10.0)
        if result.exitCode != 0 {
            // 보조 시도: /sbin/mount -t apfs
            let mountFallbackArgs = [
                "-t", "apfs",
                "-o", readOnly ? "rdonly,-s=\(snapshot.name)" : "-s=\(snapshot.name)",
                deviceNode,
                mountPoint.path
            ]
            let fallbackResult = await runner.run("/sbin/mount", mountFallbackArgs, timeout: 10.0)
            if fallbackResult.exitCode != 0 {
                let errorMsg = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? (fallbackResult.stderr.isEmpty ? result.stdout : fallbackResult.stderr)
                    : result.stderr
                throw APFSSnapshotError.mountFailed("mount_apfs failed with exit code \(result.exitCode): \(errorMsg)")
            }
        }
    }

    // MARK: - 4. 스냅샷 마운트 해제 (umount / diskutil unmount force)

    public func unmountSnapshot(mountPoint: URL, force: Bool = false) async throws {
        logger.info("Unmounting snapshot at \(mountPoint.path) (force: \(force))")

        let primaryArgs = force ? ["-f", mountPoint.path] : [mountPoint.path]
        let result = await runner.run(umountPath, primaryArgs, timeout: 10.0)
        if result.exitCode == 0 {
            return
        }

        // 실패 시 force unmount 에스컬레이션
        if force || result.exitCode != 0 {
            logger.warning("Standard unmount failed, escalating to diskutil unmount force: \(mountPoint.path)")
            let diskutilResult = await runner.run(diskutilPath, ["unmount", "force", mountPoint.path], timeout: 10.0)
            if diskutilResult.exitCode == 0 {
                return
            }
            let err = diskutilResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? diskutilResult.stdout
                : diskutilResult.stderr
            throw APFSSnapshotError.unmountFailed("Failed to force unmount \(mountPoint.path): \(err)")
        }
    }

    // MARK: - 5. 스냅샷 삭제 (tmutil deletelocalsnapshots)

    public func deleteLocalSnapshot(_ snapshot: APFSSnapshot) async throws {
        try await deleteLocalSnapshot(dateString: snapshot.dateString)
    }

    public func deleteLocalSnapshot(dateString: String) async throws {
        logger.info("Deleting APFS local snapshot for date: \(dateString)")
        let result = await runner.run(tmutilPath, ["deletelocalsnapshots", dateString], timeout: 10.0)
        guard result.exitCode == 0 else {
            let errorMsg = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? result.stdout
                : result.stderr
            throw APFSSnapshotError.snapshotDeletionFailed("tmutil deletelocalsnapshots '\(dateString)' failed with code \(result.exitCode): \(errorMsg)")
        }
    }

    // MARK: - 6. 마운트 상태 확인

    public func isMounted(mountPoint: URL) async -> Bool {
        let path = (mountPoint.path as NSString).standardizingPath
        var stat = statfs()
        guard statfs(path, &stat) == 0 else {
            return false
        }
        let mountedOn = withUnsafePointer(to: &stat.f_mntonname) { ptr -> String in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MNAMELEN)) {
                String(cString: $0)
            }
        }
        return (mountedOn as NSString).standardizingPath == path
    }
}
