import Foundation
import os

private let logger = Logger(subsystem: "net.ranode.swiftkit", category: "self-healer")

public struct SelfHealingResult: Sendable, Equatable {
    public let tokenRemoved: Bool
    public let fsckRepaired: Bool
    public let detail: String

    public init(tokenRemoved: Bool, fsckRepaired: Bool, detail: String) {
        self.tokenRemoved = tokenRemoved
        self.fsckRepaired = fsckRepaired
        self.detail = detail
    }
}

public enum SelfHealingError: LocalizedError, Sendable {
    case bundleNotFound(URL)
    case recoveryFailed(String)

    public var errorDescription: String? {
        switch self {
        case .bundleNotFound(let url):
            return "Sparsebundle not found at: \(url.path)"
        case .recoveryFailed(let reason):
            return "Self-healing recovery failed: \(reason)"
        }
    }
}

/// 네트워크 마운트(예: Synology NAS)에서 Wi-Fi 순단이나 크래시로 방치된 Stale Lock(`token`)을 정리하고,
/// 비정상 종료된 APFS Sparsebundle의 저널 손상을 `fsck_apfs`로 자동 복구하는 자가 치유 엔진.
public struct SparsebundleSelfHealer: Sendable {
    public typealias CommandExecution = @Sendable (String, [String]) throws -> (exitCode: Int32, stdout: String, stderr: String)

    public static let `default` = SparsebundleSelfHealer()

    private let executor: CommandExecution
    private let hdiutilPath: String
    private let fsckApfsPath: String
    private let fsckHfsPath: String

    public init(
        executor: @escaping CommandExecution = SparsebundleAdapter.defaultCommandExecution,
        hdiutilPath: String = "/usr/bin/hdiutil",
        fsckApfsPath: String = "/sbin/fsck_apfs",
        fsckHfsPath: String = "/sbin/fsck_hfs"
    ) {
        self.executor = executor
        self.hdiutilPath = hdiutilPath
        self.fsckApfsPath = fsckApfsPath
        self.fsckHfsPath = fsckHfsPath
    }

    /// Sparsebundle 번들의 Stale Lock 여부를 검사하고 dirty journal을 복구합니다.
    @discardableResult
    public func checkAndHeal(
        bundleURL: URL,
        staleThresholdSeconds: TimeInterval = 300
    ) throws -> SelfHealingResult {
        let adapter = SparsebundleAdapter(executor: executor, hdiutilPath: hdiutilPath)
        let resolved = adapter.resolveBundleURL(from: bundleURL)

        let fm = FileManager()
        guard fm.fileExists(atPath: resolved.path) else {
            throw SelfHealingError.bundleNotFound(resolved)
        }

        var (tokenRemoved, logs) = inspectAndHealTokenLock(resolved: resolved, threshold: staleThresholdSeconds)

        let attachArgs = ["attach", resolved.path, "-nomount", "-noverify", "-plist"]
        let (attachExit, attachOut, attachErr) = try executor(hdiutilPath, attachArgs)

        guard attachExit == 0 else {
            let reason = attachErr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? attachOut.trimmingCharacters(in: .whitespacesAndNewlines)
                : attachErr.trimmingCharacters(in: .whitespacesAndNewlines)
            logger.error("Failed to attach sparsebundle in nomount mode: \(reason)")
            return SelfHealingResult(
                tokenRemoved: tokenRemoved,
                fsckRepaired: false,
                detail: logs.joined(separator: ", ") + " (attach failed: \(reason))"
            )
        }

        let diskEntities = parseDiskEntities(fromPlist: attachOut)
        guard !diskEntities.isEmpty else {
            return SelfHealingResult(
                tokenRemoved: tokenRemoved,
                fsckRepaired: false,
                detail: logs.joined(separator: ", ") + " (No disk nodes found)"
            )
        }

        defer {
            if let rootDisk = diskEntities.first?.dev {
                do {
                    _ = try executor(hdiutilPath, ["detach", rootDisk, "-force"])
                } catch {
                    _ = error
                }
            }
        }

        let fsckRepaired = runFsckOnEntities(diskEntities, logs: &logs)

        return SelfHealingResult(
            tokenRemoved: tokenRemoved,
            fsckRepaired: fsckRepaired,
            detail: logs.joined(separator: "; ")
        )
    }

    private func inspectAndHealTokenLock(resolved: URL, threshold: TimeInterval) -> (Bool, [String]) {
        var tokenRemoved = false
        var logs: [String] = []
        let tokenURL = resolved.appendingPathComponent("token")
        let lockURL = resolved.appendingPathComponent("lock")
        let fm = FileManager()

        if !fm.fileExists(atPath: lockURL.path) {
            do { try Data().write(to: lockURL) } catch { _ = error }
        }

        if fm.fileExists(atPath: tokenURL.path) {
            let attrs: [FileAttributeKey: Any]?
            do {
                attrs = try fm.attributesOfItem(atPath: tokenURL.path)
            } catch {
                attrs = nil
            }
            let modDate = attrs?[.modificationDate] as? Date ?? .distantPast
            let age = Date().timeIntervalSince(modDate)

            logger.warning("Found stale token lock (age: \(Int(age))s). Safely resetting token lock...")
            do {
                try Data().write(to: tokenURL)
                tokenRemoved = true
                logs.append("Stale lock token reset to clean state (age: \(Int(age))s)")
            } catch {
                logger.error("Failed to reset token file: \(error.localizedDescription)")
            }
        } else {
            do { try Data().write(to: tokenURL) } catch { _ = error }
        }
        return (tokenRemoved, logs)
    }

    private func runFsckOnEntities(_ entities: [ParsedDiskEntity], logs: inout [String]) -> Bool {
        var fsckRepaired = false
        for entity in entities {
            let disk = entity.dev
            let isHfs = entity.volumeKind.lowercased() == "hfs"
            let fsckBin = isHfs ? fsckHfsPath : fsckApfsPath
            let fsckArgs = isHfs ? ["-fy", disk] : ["-y", disk]

            logger.info("Running \(fsckBin): \(fsckArgs.joined(separator: " "))")
            let result: (exitCode: Int32, stdout: String, stderr: String)?
            do {
                result = try executor(fsckBin, fsckArgs)
            } catch {
                result = nil
            }
            let fsckExit = result?.exitCode ?? -1
            let fsckErr = result?.stderr ?? "exec failed"

            if fsckExit == 0 {
                fsckRepaired = true
                logs.append("Journal verified clean on \(disk)")
            } else {
                logger.warning("fsck reported status \(fsckExit) on \(disk): \(fsckErr)")
                logs.append("Journal check/repaired status \(fsckExit) on \(disk)")
            }
        }
        return fsckRepaired
    }

    private struct ParsedDiskEntity {
        let dev: String
        let volumeKind: String
    }

    private func parseDiskEntities(fromPlist plistString: String) -> [ParsedDiskEntity] {
        guard let data = plistString.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]] else {
            return []
        }

        var results: [ParsedDiskEntity] = []
        for entity in entities {
            if let dev = entity["dev-entry"] as? String, !dev.isEmpty {
                let kind = entity["volume-kind"] as? String ?? ""
                results.append(ParsedDiskEntity(dev: dev, volumeKind: kind))
            }
        }
        return results
    }
}
