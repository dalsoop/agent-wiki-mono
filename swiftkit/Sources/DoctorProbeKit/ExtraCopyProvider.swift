import Foundation
import AppScanKit

/// Surfaces non-canonical .app copies (icons folder residue, etc.).
public struct ExtraCopyDoctorProvider: DoctorProvider {
    public let id = "extra-copies"
    private let bundleNames: [String]
    private let listCandidates: @Sendable ([String]) -> [String]

    public init(
        bundleNames: [String],
        listCandidates: @escaping @Sendable ([String]) -> [String] = {
            AppScan.installedBundleCandidates(bundleNames: $0)
        }
    ) {
        self.bundleNames = bundleNames
        self.listCandidates = listCandidates
    }

    public func run() async -> [DoctorFinding] {
        var out: [DoctorFinding] = []
        for name in bundleNames {
            let all = listCandidates([name])
            guard all.count > 1 else { continue }
            let extras = Array(all.dropFirst())
            for path in extras {
                out.append(DoctorFinding(
                    category: .install,
                    severity: .warn,
                    body: .init(
                        subject: name,
                        title: "Extra copy of \(name)",
                        detail: path,
                        remedy: "AppBuildManager retire-extras \(name)  (or ship)"
                    ),
                    source: id,
                    payload: ["path": path, "canonical": all[0]]
                ))
            }
        }
        if out.isEmpty {
            out.append(DoctorFinding(
                category: .install,
                severity: .ok,
                body: .init(
                    subject: "fleet",
                    title: "No extra .app copies for scanned names",
                    detail: "Checked \(bundleNames.count) names"
                ),
                source: id
            ))
        }
        return out
    }
}
