import Foundation
import os

private let logger = Logger(subsystem: "net.ranode.swiftkit", category: "sparsebundle")

/// 네트워크/SMB 볼륨(예: Synology NAS)의 파일시스템 제약을 극복하기 위해
/// APFS Sparsebundle 컨테이너를 생성, 마운트(`hdiutil attach -nobrowse`), 분리(`hdiutil detach`)하는 어댑터.
/// APFS 컨테이너 내부에서는 네이티브 하드링크(`--link-dest`), 확장 속성(xattr), 권한이 100% 보존됩니다.
public struct SparsebundleAdapter: Sendable {
    public typealias CommandExecution = @Sendable (String, [String]) throws -> (exitCode: Int32, stdout: String, stderr: String)

    public static let `default` = SparsebundleAdapter()

    private let executor: CommandExecution
    private let hdiutilPath: String

    public init(
        executor: @escaping CommandExecution = SparsebundleAdapter.defaultCommandExecution,
        hdiutilPath: String = "/usr/bin/hdiutil"
    ) {
        self.executor = executor
        self.hdiutilPath = hdiutilPath
    }

    /// 기본 명령어 실행기 (Process 기반)
    public static let defaultCommandExecution: CommandExecution = { executable, arguments in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment
        process.standardInput = FileHandle.nullDevice

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()

        let watchdogTask = Task {
            do {
                try await Task.sleep(nanoseconds: 60_000_000_000)
            } catch {
                return
            }
            guard process.isRunning else { return }
            process.terminate()
            do {
                try await Task.sleep(nanoseconds: 2_000_000_000)
            } catch {
                return
            }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdogTask.cancel()

        let stdout = String(decoding: outData, as: UTF8.self)
        let stderr = String(decoding: errData, as: UTF8.self)
        return (process.terminationStatus, stdout, stderr)
    }

    // MARK: - Types
    public struct BundlePhysicalStats: Sendable, Equatable {
        public let bandCount: Int
        public let totalPhysicalBytes: Int64

        public var formattedPhysicalSize: String {
            ByteCountFormatter.string(fromByteCount: totalPhysicalBytes, countStyle: .file)
        }

        public init(bandCount: Int, totalPhysicalBytes: Int64) {
            self.bandCount = bandCount
            self.totalPhysicalBytes = totalPhysicalBytes
        }
    }

    public struct CompactResult: Sendable, Equatable {
        public let beforeBytes: Int64
        public let afterBytes: Int64
        public let reclaimedBytes: Int64

        public var formattedReclaimedSize: String {
            ByteCountFormatter.string(fromByteCount: max(0, reclaimedBytes), countStyle: .file)
        }

        public init(beforeBytes: Int64, afterBytes: Int64) {
            self.beforeBytes = beforeBytes
            self.afterBytes = afterBytes
            self.reclaimedBytes = max(0, beforeBytes - afterBytes)
        }
    }

    // MARK: - Static Convenience API

    /// 정적 편의 메서드: Sparsebundle을 생성(미존재 시)하고 마운트하여 마운트 포인트 URL을 반환
    @discardableResult
    public static func attachOrCreateSparsebundle(at url: URL, sizeGiB: Int = 2048) throws -> URL {
        try Self.default.attachOrCreateSparsebundle(at: url, sizeGiB: sizeGiB)
    }

    /// 정적 편의 메서드: 마운트된 Sparsebundle을 안전하게 분리
    public static func detachSparsebundle(mountPoint: URL) throws {
        try Self.default.detachSparsebundle(mountPoint: mountPoint)
    }

    /// 정적 편의 메서드: Sparsebundle 물리 크기 측정
    public static func measureBundlePhysicalStats(for bundleURL: URL) throws -> BundlePhysicalStats {
        try Self.default.measureBundlePhysicalStats(for: bundleURL)
    }

    /// 정적 편의 메서드: Sparsebundle 밴드 압축 및 용량 회수
    public static func compactSparsebundle(at url: URL) throws -> CompactResult {
        try Self.default.compactSparsebundle(at: url)
    }

    // MARK: - Core Operations

    /// 타깃 URL에 APFS sparsebundle을 생성(미존재 시)하고 마운트한 뒤 마운트 포인트 URL을 반환합니다.
    @discardableResult
    public func attachOrCreateSparsebundle(at url: URL, sizeGiB: Int = 2048) throws -> URL {
        let bundleURL = resolveBundleURL(from: url)

        // 1. 이미 마운트되어 있는지 hdiutil info로 확인
        if let existingMount = findMountPoint(for: bundleURL) {
            logger.info("Sparsebundle already mounted at: \(existingMount.path)")
            return existingMount
        }

        // 2. 번들이 없으면 새로 생성
        if !FileManager.default.fileExists(atPath: bundleURL.path) {
            try createSparsebundle(at: bundleURL, sizeGiB: sizeGiB)
        }

        // 3. hdiutil attach -nobrowse -plist 로 마운트 수행
        return try attachSparsebundle(at: bundleURL)
    }

    /// Sparsebundle 번들 내부의 `bands/` 물리 용량을 측정합니다.
    public func measureBundlePhysicalStats(for bundleURL: URL) throws -> BundlePhysicalStats {
        let resolved = resolveBundleURL(from: bundleURL)
        let bandsDir = resolved.appendingPathComponent("bands", isDirectory: true)

        guard FileManager.default.fileExists(atPath: bandsDir.path) else {
            return BundlePhysicalStats(bandCount: 0, totalPhysicalBytes: 0)
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: bandsDir,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        var totalBytes: Int64 = 0
        var count = 0

        for fileURL in contents {
            let resourceValues: URLResourceValues?
            do {
                resourceValues = try fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey])
            } catch {
                resourceValues = nil
            }
            let size = resourceValues?.totalFileAllocatedSize ?? resourceValues?.fileAllocatedSize ?? resourceValues?.fileSize ?? 0
            totalBytes += Int64(size)
            count += 1
        }

        return BundlePhysicalStats(bandCount: count, totalPhysicalBytes: totalBytes)
    }

    /// APFS Sparsebundle의 빈 공간을 압축(`hdiutil compact`)하여 물리적 NAS 용량을 회수합니다.
    public func compactSparsebundle(at url: URL) throws -> CompactResult {
        let bundleURL = resolveBundleURL(from: url)
        guard FileManager.default.fileExists(atPath: bundleURL.path) else {
            throw SparsebundleError.invalidURL(bundleURL)
        }

        let beforeStats = try measureBundlePhysicalStats(for: bundleURL)
        let existingMount = findMountPoint(for: bundleURL)
        if let existingMount {
            logger.info("Unmounting \(existingMount.path) prior to compaction...")
            try detachSparsebundle(mountPoint: existingMount)
        }

        defer {
            if existingMount != nil {
                do {
                    _ = try attachSparsebundle(at: bundleURL)
                } catch {
                    logger.warning("Failed to remount after compaction: \(error.localizedDescription)")
                }
            }
        }

        let args = ["compact", bundleURL.path]
        logger.info("Compacting sparsebundle: \(args.joined(separator: " "))")
        let (exitCode, stdout, stderr) = try executor(hdiutilPath, args)

        guard exitCode == 0 else {
            let errorMsg = stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                : stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SparsebundleError.compactFailed(errorMsg.isEmpty ? "Exit code \(exitCode)" : errorMsg)
        }

        let afterStats = try measureBundlePhysicalStats(for: bundleURL)
        let result = CompactResult(beforeBytes: beforeStats.totalPhysicalBytes, afterBytes: afterStats.totalPhysicalBytes)
        logger.info("Compaction completed: Reclaimed \(result.formattedReclaimedSize)")
        return result
    }

    /// 마운트된 볼륨을 분리(`hdiutil detach`)합니다.
    public func detachSparsebundle(mountPoint: URL) throws {
        let mountPath = mountPoint.path
        let (exitCode, stdout, stderr) = try executor(hdiutilPath, ["detach", mountPath])
        if exitCode == 0 {
            logger.info("Successfully detached sparsebundle at: \(mountPath)")
            return
        }

        logger.warning("Normal detach failed for \(mountPath), attempting force detach: \(stderr)")
        let (forceExit, _, forceErr) = try executor(hdiutilPath, ["detach", mountPath, "-force"])
        if forceExit == 0 {
            logger.info("Successfully force-detached sparsebundle at: \(mountPath)")
            return
        }

        let combinedErr = forceErr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? stdout : stderr)
            : forceErr
        throw SparsebundleError.detachFailed(combinedErr)
    }

    /// 주어진 URL이 가리키는 sparsebundle의 현재 마운트 포인트를 조회합니다.
    public func findMountPoint(for bundleURL: URL) -> URL? {
        let resolved = resolveBundleURL(from: bundleURL)
        let resolvedPath = resolved.standardizedFileURL.path

        guard let (exitCode, stdout, _) = try? executor(hdiutilPath, ["info", "-plist"]),
              exitCode == 0,
              let data = stdout.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let images = plist["images"] as? [[String: Any]] else {
            return nil
        }

        for image in images {
            guard let imagePath = image["image-path"] as? String else { continue }
            let standardImagePath = URL(fileURLWithPath: imagePath).standardizedFileURL.path
            guard standardImagePath == resolvedPath || imagePath == resolvedPath else { continue }
            guard let entities = image["system-entities"] as? [[String: Any]] else { continue }
            if let mountPoint = extractMountPoint(from: entities) {
                return mountPoint
            }
        }

        return nil
    }

    private func extractMountPoint(from entities: [[String: Any]]) -> URL? {
        for entity in entities {
            if let mountPoint = entity["mount-point"] as? String, !mountPoint.isEmpty {
                return URL(fileURLWithPath: mountPoint, isDirectory: true)
            }
        }
        return nil
    }

    /// 현재 마운트되어 있는지 여부
    public func isMounted(bundleURL: URL) -> Bool {
        findMountPoint(for: bundleURL) != nil
    }

    // MARK: - Private Helpers

    public func resolveBundleURL(from url: URL) -> URL {
        guard url.pathExtension.lowercased() != "sparsebundle" else { return url }
        if shouldAppendDefaultVaultName(for: url) {
            return url.appendingPathComponent("mac-vault.sparsebundle", isDirectory: true)
        }
        return url.appendingPathExtension("sparsebundle")
    }

    private func shouldAppendDefaultVaultName(for url: URL) -> Bool {
        if url.lastPathComponent.lowercased() == "backup" { return true }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    private func createSparsebundle(at bundleURL: URL, sizeGiB: Int) throws {
        let parentDir = bundleURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        let volname = bundleURL.deletingPathExtension().lastPathComponent
        let sizeArg = "\(max(1, sizeGiB))g"
        let args = [
            "create",
            "-size", sizeArg,
            "-type", "SPARSEBUNDLE",
            "-fs", "APFS",
            "-volname", volname,
            bundleURL.path
        ]

        logger.info("Creating APFS sparsebundle: \(args.joined(separator: " "))")
        let (exitCode, stdout, stderr) = try executor(hdiutilPath, args)
        guard exitCode == 0 else {
            let errorMsg = stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                : stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SparsebundleError.createFailed(errorMsg.isEmpty ? "Exit code \(exitCode)" : errorMsg)
        }
    }

    private func attachSparsebundle(at bundleURL: URL) throws -> URL {
        ensureLockAndTokenFiles(at: bundleURL)

        let args = ["attach", bundleURL.path, "-nobrowse", "-plist"]
        logger.info("Attaching sparsebundle: \(args.joined(separator: " "))")
        let (exitCode, stdout, stderr) = try executor(hdiutilPath, args)

        if exitCode == 0, let mountPoint = resolveMountAfterAttach(stdout: stdout, bundleURL: bundleURL) {
            return mountPoint
        }
        if let existing = findMountPoint(for: bundleURL) {
            return existing
        }

        return try recoverAndRetryAttach(bundleURL: bundleURL, exitCode: exitCode, stderr: stderr, stdout: stdout, args: args)
    }

    private func resolveMountAfterAttach(stdout: String, bundleURL: URL) -> URL? {
        parseMountPoint(fromPlistOutput: stdout) ?? findMountPoint(for: bundleURL)
    }

    private func ensureLockAndTokenFiles(at bundleURL: URL) {
        let lockURL = bundleURL.appendingPathComponent("lock")
        let tokenURL = bundleURL.appendingPathComponent("token")
        if !FileManager.default.fileExists(atPath: lockURL.path) {
            do { try Data().write(to: lockURL) } catch {
                logger.warning("Could not create lock anchor file: \(error.localizedDescription)")
            }
        }
        if !isMounted(bundleURL: bundleURL) {
            do { try Data().write(to: tokenURL) } catch {
                logger.warning("Could not ensure clean token anchor file: \(error.localizedDescription)")
            }
        }
    }

    private func recoverAndRetryAttach(bundleURL: URL, exitCode: Int32, stderr: String, stdout: String, args: [String]) throws -> URL {
        logger.warning("Initial attach failed (exit code \(exitCode): \(stderr)). Attempting self-healing recovery...")
        do {
            _ = try SparsebundleSelfHealer(executor: executor, hdiutilPath: hdiutilPath).checkAndHeal(bundleURL: bundleURL)
        } catch {
            logger.warning("Self healing attempt failed: \(error.localizedDescription)")
        }

        let (retryCode, retryOut, retryErr) = try executor(hdiutilPath, args)
        if retryCode == 0, let mountPoint = resolveMountAfterAttach(stdout: retryOut, bundleURL: bundleURL) {
            return mountPoint
        }

        let errorMsg = retryErr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? stdout : stderr)
            : retryErr
        throw SparsebundleError.attachFailed(errorMsg.isEmpty ? "Exit code \(retryCode)" : errorMsg)
    }

    private func parseMountPoint(fromPlistOutput output: String) -> URL? {
        guard let data = output.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]] else {
            return nil
        }

        for entity in entities {
            if let mountPoint = entity["mount-point"] as? String, !mountPoint.isEmpty {
                return URL(fileURLWithPath: mountPoint, isDirectory: true)
            }
        }
        return nil
    }
}
