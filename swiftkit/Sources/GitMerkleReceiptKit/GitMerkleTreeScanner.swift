import Foundation
import CommandKit
import InteropKit

/// Git Tree Merkle OID 스캐너.
/// `git write-tree` 및 `git write-tree --prefix=<app>`를 인메모리에서 안전하게 실행하여
/// 루트 및 서브트리 OID를 획득한다.
/// `BoundedProcessLimiter`를 통해 과도한 동시 서브프로세스 생성으로 인한 시스템 자원 고갈을 방지한다.
public final class GitMerkleTreeScanner: Sendable {
    public let repositoryRoot: URL
    public let gitBinaryPath: String
    public let limiter: BoundedProcessLimiter
    public let runner: CommandRunning

    public init(
        repositoryRoot: URL,
        gitBinaryPath: String? = nil,
        maxConcurrent: Int = 1,
        runner: CommandRunning = ProcessCommandRunner()
    ) {
        self.repositoryRoot = repositoryRoot
        self.gitBinaryPath = gitBinaryPath ?? Self.resolveGitBinary()
        self.limiter = BoundedProcessLimiter(maxConcurrent: maxConcurrent)
        self.runner = runner
    }

    public init(
        repositoryRoot: URL,
        gitBinaryPath: String? = nil,
        limiter: BoundedProcessLimiter,
        runner: CommandRunning = ProcessCommandRunner()
    ) {
        self.repositoryRoot = repositoryRoot
        self.gitBinaryPath = gitBinaryPath ?? Self.resolveGitBinary()
        self.limiter = limiter
        self.runner = runner
    }

    /// 시스템에 설치된 Git 바이너리 경로 탐색 (HostPlatform 표준 경로 활용)
    public static func resolveGitBinary() -> String {
        for dir in HostPlatform.standardBinPaths {
            let gitPath = "\(dir)/git"
            if FileManager.default.isExecutableFile(atPath: gitPath) {
                return gitPath
            }
        }
        return "/usr/bin/git"
    }

    /// 현재 인덱스의 Root Tree OID를 추출한다 (`git write-tree`).
    /// 실측 50ms 내외 소요 (인메모리 인덱스 해시 리졸브).
    public func scanRootTree() async throws -> String {
        try await limiter.withLimit {
            let spec = CommandSpecification(
                self.gitBinaryPath,
                ["write-tree"],
                workingDirectory: self.repositoryRoot,
                timeout: 30
            )
            let result = await self.runner.run(spec)
            guard result.exitCode == 0 else {
                throw GitMerkleTreeError.gitFailed(exitCode: result.exitCode, stderr: result.stderr)
            }
            let oid = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            guard Self.isValidOID(oid) else {
                throw GitMerkleTreeError.invalidOID(oid)
            }
            return oid
        }
    }

    /// 특정 앱/디렉터리의 Subtree OID를 추출한다 (`git write-tree --prefix=<prefix>`).
    /// - Parameter prefix: 상대 경로 (예: `apps/agent-lint-catalog-swift` 또는 `swiftkit`)
    public func scanSubtree(prefix: String) async throws -> String {
        let cleanPrefix = Self.normalizePrefix(prefix)
        return try await limiter.withLimit {
            let spec = CommandSpecification(
                self.gitBinaryPath,
                ["write-tree", "--prefix=\(cleanPrefix)"],
                workingDirectory: self.repositoryRoot,
                timeout: 30
            )
            let result = await self.runner.run(spec)
            guard result.exitCode == 0 else {
                let stderr = result.stderr
                if stderr.contains("not found") || stderr.contains("fatal: git-write-tree: prefix") {
                    throw GitMerkleTreeError.prefixNotFound(cleanPrefix)
                }
                throw GitMerkleTreeError.gitFailed(exitCode: result.exitCode, stderr: stderr)
            }
            let oid = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            guard Self.isValidOID(oid) else {
                throw GitMerkleTreeError.invalidOID(oid)
            }
            return oid
        }
    }

    /// 여러 Subtree prefix들에 대해 `BoundedProcessLimiter`의 한계 내에서 동시 스캔을 수행한다.
    /// - Parameter prefixes: 상대 경로 목록
    /// - Returns: [prefix: subtreeOID] 딕셔너리
    public func scanSubtrees(prefixes: [String]) async throws -> [String: String] {
        try await withThrowingTaskGroup(of: (String, String).self) { group in
            for prefix in prefixes {
                group.addTask {
                    let oid = try await self.scanSubtree(prefix: prefix)
                    return (prefix, oid)
                }
            }

            var results: [String: String] = [:]
            results.reserveCapacity(prefixes.count)
            for try await (prefix, oid) in group {
                results[prefix] = oid
            }
            return results
        }
    }

    /// SHA-1 (40자) 또는 SHA-256 (64자) Git OID 형식 검증
    public static func isValidOID(_ string: String) -> Bool {
        let count = string.utf8.count
        guard count == 40 || count == 64 else { return false }
        for byte in string.utf8 {
            switch byte {
            case 48...57, 97...102, 65...70:
                continue
            default:
                return false
            }
        }
        return true
    }

    /// prefix 경로 정규화 (선두 slash, './' 제거, trailing slash 제거)
    public static func normalizePrefix(_ prefix: String) -> String {
        var clean = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        while clean.hasPrefix("./") {
            clean = String(clean.dropFirst(2))
        }
        while clean.hasPrefix("/") {
            clean = String(clean.dropFirst())
        }
        while clean.hasSuffix("/") {
            clean = String(clean.dropLast())
        }
        return clean
    }
}
