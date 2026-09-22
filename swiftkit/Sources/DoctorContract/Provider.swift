import Foundation

/// One source of doctor findings. Keep providers pure enough to unit-test.
public protocol DoctorProvider: Sendable {
    var id: String { get }
    func run() async -> [DoctorFinding]
}

/// Runs providers and assembles a report.
public struct DoctorOrchestrator: Sendable {
    private let providers: [any DoctorProvider]

    public init(providers: [any DoctorProvider]) {
        self.providers = providers
    }

    public func scan() async -> DoctorReport {
        var all: [DoctorFinding] = []
        for p in providers {
            let batch = await p.run()
            all.append(contentsOf: batch)
        }
        // fail first, then warn, then subject
        all.sort {
            if $0.severity != $1.severity { return $0.severity > $1.severity }
            return $0.subject < $1.subject
        }
        return DoctorReport(findings: all)
    }
}
