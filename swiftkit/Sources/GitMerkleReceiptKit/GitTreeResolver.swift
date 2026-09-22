import Foundation
import CommandKit

public enum GitTreeError: Error, LocalizedError, Sendable {
    case oidResolutionFailed(String)
    case stagedTreeCreationFailed(String)
    case unsupportedPlatform

    public var errorDescription: String? {
        switch self {
        case .oidResolutionFailed(let msg): return "Git tree OID resolution failed: \(msg)"
        case .stagedTreeCreationFailed(let msg): return "Git staged tree creation failed: \(msg)"
        case .unsupportedPlatform: return "Subprocess execution is not supported on this platform"
        }
    }
}

public protocol GitTreeResolving: Sendable {
    func resolveTreeOID(forSubtree path: String, repositoryRoot: String) async throws -> String
    func resolveStagedTreeOID(forSubtree path: String, repositoryRoot: String) async throws -> String
}

public final class GitTreeResolver: GitTreeResolving, Sendable {
    private let limiter = BoundedProcessLimiter(maxConcurrent: 4)

    public init() {}

    public func resolveTreeOID(forSubtree path: String, repositoryRoot: String) async throws -> String {
        #if !os(iOS)
        return try await limiter.withLimit {
            let runner = ShellRunner()
            let escapedRoot = repositoryRoot.replacingOccurrences(of: "'", with: "'\\''")
            let escapedPath = path.replacingOccurrences(of: "'", with: "'\\''")
            let cmd = "git -C '\(escapedRoot)' rev-parse 'HEAD:\(escapedPath)'"
            let res = await runner.run(cmd)
            guard res.exitCode == 0 else {
                throw GitTreeError.oidResolutionFailed(res.stderr)
            }
            return res.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #else
        throw GitTreeError.unsupportedPlatform
        #endif
    }

    public func resolveStagedTreeOID(forSubtree path: String, repositoryRoot: String) async throws -> String {
        #if !os(iOS)
        return try await limiter.withLimit {
            let runner = ShellRunner()
            let escapedRoot = repositoryRoot.replacingOccurrences(of: "'", with: "'\\''")
            let escapedPath = path.replacingOccurrences(of: "'", with: "'\\''")
            let cmd = "git -C '\(escapedRoot)' write-tree --prefix='\(escapedPath)'"
            let res = await runner.run(cmd)
            guard res.exitCode == 0 else {
                throw GitTreeError.stagedTreeCreationFailed(res.stderr)
            }
            return res.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #else
        throw GitTreeError.unsupportedPlatform
        #endif
    }
}
