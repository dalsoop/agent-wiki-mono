import Foundation
import InstallHealthKit

/// Maps InstallHealthKit.HealthIssue into DoctorFinding.
public enum InstallHealthBridge {
    public static func finding(from issue: HealthIssue, source: String = "install-health") -> DoctorFinding {
        let severity: DoctorSeverity = {
            switch issue.severity {
            case .error: return .fail
            case .warning: return .warn
            }
        }()
        return DoctorFinding(
            category: .install,
            severity: severity,
            body: .init(
                subject: issue.subject,
                title: issue.kind.rawValue,
                detail: issue.detail,
                remedy: issue.remedy
            ),
            source: source,
            payload: ["kind": issue.kind.rawValue, "autoFixable": issue.isAutoFixable ? "1" : "0"]
        )
    }
}

/// Provider that turns precomputed HealthIssues into findings (IO lives outside kit).
public struct InstallHealthDoctorProvider: DoctorProvider {
    public let id = "install-health"
    private let issues: @Sendable () -> [HealthIssue]

    public init(issues: @escaping @Sendable () -> [HealthIssue]) {
        self.issues = issues
    }

    public func run() async -> [DoctorFinding] {
        let list = issues()
        if list.isEmpty {
            return [DoctorFinding(
                category: .install,
                severity: .ok,
                body: .init(
                    subject: "fleet",
                    title: "Install health clean",
                    detail: "No HealthIssue from InstallHealthKit"
                ),
                source: id
            )]
        }
        return list.map { InstallHealthBridge.finding(from: $0, source: id) }
    }
}
