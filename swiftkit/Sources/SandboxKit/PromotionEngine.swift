import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

public struct PromotedArtifact: Codable, Sendable, Equatable {
    public var relativePath: String
    public var sha256: String
    public var sizeBytes: Int64
    public var baseSha256: String?

    public init(relativePath: String, sha256: String, sizeBytes: Int64, baseSha256: String? = nil) {
        self.relativePath = relativePath
        self.sha256 = sha256
        self.sizeBytes = sizeBytes
        self.baseSha256 = baseSha256
    }
}

/// 단방향 승격 검수 영수증 (Immutable Promotion Receipt).
public struct PromotionReceipt: Codable, Sendable, Equatable {
    public let receiptID: String
    public let roomID: String
    public let tenantSlug: String
    public let agentID: String?
    public let verifiedAt: Date
    public let artifacts: [PromotedArtifact]

    public init(
        receiptID: String = "rcpt-\(UUID().uuidString.prefix(8).lowercased())",
        roomID: String,
        tenantSlug: String,
        agentID: String? = nil,
        verifiedAt: Date = Date(),
        artifacts: [PromotedArtifact]
    ) {
        self.receiptID = receiptID
        self.roomID = roomID
        self.tenantSlug = tenantSlug
        self.agentID = agentID
        self.verifiedAt = verifiedAt
        self.artifacts = artifacts
    }
}

public enum PromotionError: Error, LocalizedError, Equatable {
    case artifactNotFound(String)
    case checksumMismatch(expected: String, actual: String, path: String)
    case pathTraversal(String)
    case symlinkNotAllowed(String)
    case conflictDetected(path: String, baseChecksum: String?, masterChecksum: String, sandboxChecksum: String)
    case emptyReceipt
    case io(String)

    public var errorDescription: String? {
        switch self {
        case .artifactNotFound(let path):
            return "승격 대상 파일을 샌드박스에서 찾을 수 없습니다: \(path)"
        case .checksumMismatch(let expected, let actual, let path):
            return "체크섬 불일치 (\(path)) — 기대값: \(expected), 실제값: \(actual)"
        case .pathTraversal(let path):
            return "경로 탈출(Path Traversal) 공격 탐지 — 상위 디렉터리 접근 불가: \(path)"
        case .symlinkNotAllowed(let path):
            return "심볼릭 링크(Symlink) 승격 불가 — 외부 파일 탈취 방어: \(path)"
        case .conflictDetected(let path, let base, let master, let sandbox):
            return "OCC 충돌 탐지 (\(path)) — 마스터 정본이 다른 에이전트에 의해 변경됨 (base: \(base ?? "none"), master: \(master), sandbox: \(sandbox)). 정본을 동기화하고 재시도하십시오."
        case .emptyReceipt:
            return "승격할 산출물이 영수증에 없습니다."
        case .io(let msg):
            return "승격 IO 오류: \(msg)"
        }
    }
}

/// 샌드박스 산출물을 검증 영수증과 대조하여 상위 정본으로 원자적 승격(Atomic Promotion)하는 엔진.
public enum PromotionEngine {
    /// 파일의 SHA-256 체크섬을 계산한다.
    public static func sha256(of url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// 상대 경로가 샌드박스 경계를 벗어나지 않는지 검증한다.
    public static func validateRelativePath(_ rel: String, base: URL) throws -> URL {
        let trimmed = rel.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasPrefix("/") || trimmed.hasPrefix("\\") || trimmed.contains("..") {
            throw PromotionError.pathTraversal(rel)
        }
        let fullPath = (base.appendingPathComponent(trimmed).path as NSString).standardizingPath
        let basePath = (base.path as NSString).standardizingPath
        guard fullPath.hasPrefix(basePath) else {
            throw PromotionError.pathTraversal(rel)
        }
        return URL(fileURLWithPath: fullPath)
    }

    /// 파일이 심볼릭 링크인지 검증한다 (심볼릭 링크 승격 금지).
    public static func ensureNotSymlink(at url: URL, relativePath: String) throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        if (attrs[.type] as? FileAttributeType) == .typeSymbolicLink {
            throw PromotionError.symlinkNotAllowed(relativePath)
        }
    }

    /// 샌드박스 내부의 특정 파일들을 기반으로 영수증을 생성한다.
    public static func makeReceipt(
        context: SandboxContext,
        relativePaths: [String]
    ) throws -> PromotionReceipt {
        guard !relativePaths.isEmpty else { throw PromotionError.emptyReceipt }
        
        var artifacts: [PromotedArtifact] = []
        let fm = FileManager.default

        for rel in relativePaths {
            let fileURL = try validateRelativePath(rel, base: context.sandboxDirectory)
            guard fm.fileExists(atPath: fileURL.path) else {
                throw PromotionError.artifactNotFound(rel)
            }
            try ensureNotSymlink(at: fileURL, relativePath: rel)

            let checksum = try sha256(of: fileURL)
            let attrs = try fm.attributesOfItem(atPath: fileURL.path)
            let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            artifacts.append(PromotedArtifact(relativePath: rel, sha256: checksum, sizeBytes: size))
        }

        return PromotionReceipt(
            roomID: context.roomID,
            tenantSlug: context.tenantSlug,
            agentID: context.agentID,
            artifacts: artifacts
        )
    }

    /// 영수증을 검증하고 샌드박스 산출물을 상위 정본 디렉터리로 원자적 승격한다.
    public static func promote(
        context: SandboxContext,
        receipt: PromotionReceipt
    ) throws {
        guard !receipt.artifacts.isEmpty else { throw PromotionError.emptyReceipt }
        let fm = FileManager.default

        // 1. 사전 체크섬 및 보안 무결성 전수 검사
        for artifact in receipt.artifacts {
            let sourceURL = try validateRelativePath(artifact.relativePath, base: context.sandboxDirectory)
            _ = try validateRelativePath(artifact.relativePath, base: context.readOnlyMasterRoot)

            guard fm.fileExists(atPath: sourceURL.path) else {
                throw PromotionError.artifactNotFound(artifact.relativePath)
            }
            try ensureNotSymlink(at: sourceURL, relativePath: artifact.relativePath)

            let actualChecksum = try sha256(of: sourceURL)
            guard actualChecksum == artifact.sha256 else {
                throw PromotionError.checksumMismatch(
                    expected: artifact.sha256,
                    actual: actualChecksum,
                    path: artifact.relativePath
                )
            }

            // OCC 낙관적 충돌 검증
            let targetURL = try validateRelativePath(artifact.relativePath, base: context.readOnlyMasterRoot)
            if let baseChecksum = artifact.baseSha256, fm.fileExists(atPath: targetURL.path) {
                let masterChecksum = try sha256(of: targetURL)
                if masterChecksum != baseChecksum && masterChecksum != actualChecksum {
                    throw PromotionError.conflictDetected(
                        path: artifact.relativePath,
                        baseChecksum: baseChecksum,
                        masterChecksum: masterChecksum,
                        sandboxChecksum: actualChecksum
                    )
                }
            }
        }

        // 2. 상위 정본 디렉터리로 원자적 복사
        try fm.createDirectory(at: context.readOnlyMasterRoot, withIntermediateDirectories: true)
        let receiptsDir = context.readOnlyMasterRoot.appendingPathComponent(".receipts", isDirectory: true)
        try fm.createDirectory(at: receiptsDir, withIntermediateDirectories: true)

        for artifact in receipt.artifacts {
            let sourceURL = try validateRelativePath(artifact.relativePath, base: context.sandboxDirectory)
            let targetURL = try validateRelativePath(artifact.relativePath, base: context.readOnlyMasterRoot)

            let parentDir = targetURL.deletingLastPathComponent()
            try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)

            let tempTargetURL = parentDir.appendingPathComponent(".atomic_\(UUID().uuidString.prefix(12)).tmp")
            if fm.fileExists(atPath: tempTargetURL.path) {
                try? fm.removeItem(at: tempTargetURL)
            }
            try fm.copyItem(at: sourceURL, to: tempTargetURL)

            // 동일 디렉터리 내 POSIX rename은 커널 레벨에서 원자적 교체(Atomic Replacement)를 보장한다.
            if rename(tempTargetURL.path, targetURL.path) != 0 {
                // rename 실패 시 FileManager replaceItem 폴백
                if fm.fileExists(atPath: targetURL.path) {
                    try fm.removeItem(at: targetURL)
                }
                try fm.moveItem(at: tempTargetURL, to: targetURL)
            }
        }

        // 3. 영수증 원장 저장
        let receiptData = try JSONEncoder().encode(receipt)
        let receiptFile = receiptsDir.appendingPathComponent("\(receipt.receiptID).json")
        try receiptData.write(to: receiptFile, options: .atomic)
    }
}
