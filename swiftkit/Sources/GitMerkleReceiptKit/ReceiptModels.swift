import Foundation
import ISO8601DateCodecKit

// MARK: - Core Receipt Models

/// 린트 및 정적 분석의 5ms 증거 영수증 모델
public struct AnalysisReceipt: Codable, Sendable, Equatable {
    public let targetPath: String
    public let treeOID: String
    public let rulesetDigest: String
    public let toolchainHash: String
    public let verdict: Verdict
    public let violationCount: Int
    public let findingsData: Data?
    public let durationMs: Double
    public let issuedAt: Date

    public enum Verdict: String, Codable, Sendable {
        case pass = "PASS"
        case fail = "FAIL"
    }

    public init(
        targetPath: String,
        treeOID: String,
        rulesetDigest: String,
        toolchainHash: String,
        verdict: Verdict,
        violationCount: Int,
        findingsData: Data? = nil,
        durationMs: Double,
        issuedAt: Date = Date()
    ) {
        self.targetPath = targetPath
        self.treeOID = treeOID
        self.rulesetDigest = rulesetDigest
        self.toolchainHash = toolchainHash
        self.verdict = verdict
        self.violationCount = violationCount
        self.findingsData = findingsData
        self.durationMs = durationMs
        self.issuedAt = issuedAt
    }
}

/// 영수증 검증 판정 결과
public enum ReceiptVerificationResult: Sendable, Equatable {
    case valid(AnalysisReceipt)
    case stale(reason: String)
    case missing
}

// MARK: - Merkle Tree Scanner & Verifier Models

public enum GitMerkleTreeError: Error, LocalizedError, Sendable {
    case prefixNotFound(String)
    case gitFailed(exitCode: Int32, stderr: String)
    case invalidOID(String)
    case executionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .prefixNotFound(let prefix): return "Git prefix not found: \(prefix)"
        case .gitFailed(let code, let stderr): return "Git execution failed (exit \(code)): \(stderr)"
        case .invalidOID(let oid): return "Invalid Git OID: \(oid)"
        case .executionFailed(let msg): return msg
        }
    }
}

/// 앱(서브트리) 영수증 모델
public struct AppTreeReceipt: Codable, Sendable, Equatable {
    public let scope: String
    public let subtreeOID: String
    public let rulesetDigest: String
    public let verdict: String
    public let violationsCount: Int
    public let byRuleJSON: String
    public let updatedAt: String

    public init(
        scope: String,
        subtreeOID: String,
        rulesetDigest: String,
        verdict: String,
        violationsCount: Int,
        byRuleJSON: String,
        updatedAt: String = ISO8601DateCodec.format(Date())
    ) {
        self.scope = scope
        self.subtreeOID = subtreeOID
        self.rulesetDigest = rulesetDigest
        self.verdict = verdict
        self.violationsCount = violationsCount
        self.byRuleJSON = byRuleJSON
        self.updatedAt = updatedAt
    }
}

/// 레포지토리 전체(루트 트리) 영수증 모델
public struct RepoRootReceipt: Codable, Sendable, Equatable {
    public let rootTreeOID: String
    public let rulesetDigest: String
    public let totalViolations: Int
    public let byRuleJSON: String
    public let byAppJSON: String
    public let updatedAt: String

    public init(
        rootTreeOID: String,
        rulesetDigest: String,
        totalViolations: Int,
        byRuleJSON: String,
        byAppJSON: String,
        updatedAt: String = ISO8601DateCodec.format(Date())
    ) {
        self.rootTreeOID = rootTreeOID
        self.rulesetDigest = rulesetDigest
        self.totalViolations = totalViolations
        self.byRuleJSON = byRuleJSON
        self.byAppJSON = byAppJSON
        self.updatedAt = updatedAt
    }
}

/// 통합 영수증 컨테이너
public struct Receipt: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case repoRoot
        case appTree
    }

    public let repoRoot: RepoRootReceipt?
    public let appTree: AppTreeReceipt?

    public init(repoRoot: RepoRootReceipt) {
        self.repoRoot = repoRoot
        self.appTree = nil
    }

    public init(appTree: AppTreeReceipt) {
        self.repoRoot = nil
        self.appTree = appTree
    }

    public var kind: Kind {
        repoRoot != nil ? .repoRoot : .appTree
    }

    public var treeOID: String {
        repoRoot?.rootTreeOID ?? appTree?.subtreeOID ?? ""
    }

    public var violationsCount: Int {
        repoRoot?.totalViolations ?? appTree?.violationsCount ?? 0
    }

    public var verdict: String {
        if let repoRoot {
            return repoRoot.totalViolations == 0 ? "PASS" : "FAIL"
        }
        return appTree?.verdict ?? "FAIL"
    }

    public var scope: String {
        appTree?.scope ?? "repo_root"
    }

    public var isAppTree: Bool {
        appTree != nil
    }

    public var isRoot: Bool {
        repoRoot != nil
    }
}

/// 영수증 유효성 검증 판정 결과
public enum VerificationResult: Sendable, Equatable {
    case valid(Receipt)
    case invalid(reason: String, violationsCount: Int)
    case notFound
}
