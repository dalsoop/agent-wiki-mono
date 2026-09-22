import Foundation
import DoctorContract

/// 영수증 유효성을 닥터 진단으로 변환하는 프로바이더
public struct ReceiptDoctorProvider: DoctorProvider, Sendable {
    public let id = "receipt-verification-doctor"
    private let ledger: ReceiptLedger
    private let targetPaths: [String]
    private let treeOIDProvider: @Sendable (String) async throws -> String
    private let rulesetDigest: String
    private let toolchainHash: String

    public init(
        ledger: ReceiptLedger,
        targetPaths: [String],
        rulesetDigest: String,
        toolchainHash: String,
        treeOIDProvider: @escaping @Sendable (String) async throws -> String
    ) {
        self.ledger = ledger
        self.targetPaths = targetPaths
        self.rulesetDigest = rulesetDigest
        self.toolchainHash = toolchainHash
        self.treeOIDProvider = treeOIDProvider
    }

    public func run() async -> [DoctorFinding] {
        var findings: [DoctorFinding] = []

        for path in targetPaths {
            guard let treeOID = try? await treeOIDProvider(path) else {
                findings.append(makeOIDFailureFinding(path: path))
                continue
            }

            let result = (try? ledger.verifyReceipt(
                targetPath: path,
                treeOID: treeOID,
                rulesetDigest: rulesetDigest,
                toolchainHash: toolchainHash
            )) ?? .missing

            if let finding = evaluateReceiptResult(result, path: path, treeOID: treeOID) {
                findings.append(finding)
            }
        }

        return findings
    }

    private func makeOIDFailureFinding(path: String) -> DoctorFinding {
        DoctorFinding(
            category: .staleSource,
            severity: .fail,
            body: .init(
                subject: path,
                title: "Git Tree OID Resolution Failed",
                detail: "Could not resolve git tree OID for target path '\(path)'.",
                remedy: "Ensure the path is a tracked directory in a valid git repository."
            ),
            source: id
        )
    }

    private func evaluateReceiptResult(_ result: ReceiptVerificationResult, path: String, treeOID: String) -> DoctorFinding? {
        switch result {
        case .valid:
            return nil
        case .stale(let reason):
            return DoctorFinding(
                category: .staleSource,
                severity: .fail,
                body: .init(
                    subject: path,
                    title: "Stale or Failed Receipt",
                    detail: "Target '\(path)' has a failing or stale receipt: \(reason)",
                    remedy: "Run agent-lint-catalog check to fix violations and reissue receipt."
                ),
                source: id
            )
        case .missing:
            return DoctorFinding(
                category: .staleSource,
                severity: .warn,
                body: .init(
                    subject: path,
                    title: "Missing Analysis Receipt",
                    detail: "No verification receipt found for target '\(path)' (Tree OID: \(treeOID)).",
                    remedy: "Run agent-lint-catalog check to issue a cryptographic verification receipt."
                ),
                source: id
            )
        }
    }
}
