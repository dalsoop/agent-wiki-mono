import Foundation

struct ManagementExternalReports {
    let pathRoots: [String]
    let resolveOnPath: @Sendable (String, [String]) -> String?
    let runCLI: @Sendable (String, [String], TimeInterval) -> (exit: Int32, stdout: String)
    let source: String

    func pullAll() -> [DoctorFinding] {
        var out: [DoctorFinding] = []
        out.append(contentsOf: pullPathCLIHealth())
        out.append(contentsOf: pullAgentCLIManager())
        out.append(contentsOf: pullAgentCLIPathGap())
        out.append(contentsOf: pullAgentHostDualEntry())
        out.append(contentsOf: pullRegistryDoctor())
        out.append(contentsOf: pullSparklePending())
        out.append(contentsOf: pullSparkleFleet())
        return out
    }

    private func pullPathCLIHealth() -> [DoctorFinding] {
        guard resolveOnPath("path-cli-health", pathRoots) != nil else { return [] }
        var (code, stdout) = runCLI("path-cli-health", ["last", "--json"], 15)
        if code != 0 || stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            (code, stdout) = runCLI("path-cli-health", ["fast", "--json"], 45)
        }
        return PathCLIHealthReportMapper.map(stdout: stdout, source: source)
    }

    private func pullAgentCLIManager() -> [DoctorFinding] {
        guard resolveOnPath("agent-cli-manager", pathRoots) != nil else { return [] }
        let (code, stdout) = runCLI("agent-cli-manager", ["check", "--json"], 30)
        if code == 0, stdout.contains("\"ok\"") || stdout.contains("findings") || stdout.contains("violations")
            || stdout.contains("naming_violations") || stdout.contains("shadow")
        {
            return AgentCLIManagerReportMapper.map(stdout: stdout, source: source)
        }
        if stdout.contains("helpers dual-entry") || stdout.contains("Open the GUI")
            || stdout.localizedCaseInsensitiveContains("unknown")
            || (code != 0 && !stdout.contains("{"))
        {
            return [
                DoctorFinding(
                    category: .management,
                    severity: .fail,
                    body: .init(
                        subject: "agent-cli-manager",
                        title: "agent-cli-manager check 사용 불가 (stub/미구현 PATH)",
                        detail: "check --json 이 본문 CLI 가 아니다. dual-entry Helpers 재설치 필요. "
                            + "exit=\(code) out=\(String(stdout.prefix(200)))",
                        remedy: "app-build-manager ship apps/agent-cli-manager-swift release"
                    ),
                    source: source,
                    payload: ["cli": "agent-cli-manager", "kind": "probe_stub"]
                ),
            ]
        }
        return []
    }

    private func pullAgentCLIPathGap() -> [DoctorFinding] {
        guard resolveOnPath("agent-cli-manager", pathRoots) != nil else { return [] }
        let (code, stdout) = runCLI("agent-cli-manager", ["path-gap", "--json"], 45)
        guard !stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return AgentCLIPathGapMapper.map(stdout: stdout, exitCode: code, source: source)
    }

    private func pullAgentHostDualEntry() -> [DoctorFinding] {
        guard resolveOnPath("agent-host-doctor", pathRoots) != nil else { return [] }
        let (_, stdout) = runCLI("agent-host-doctor", ["dual-entry", "fast", "--json"], 45)
        return AgentHostDualEntryMapper.map(stdout: stdout, source: source)
    }

    private func pullRegistryDoctor() -> [DoctorFinding] {
        guard resolveOnPath("agent-app-registry", pathRoots) != nil else { return [] }
        let (_, stdout) = runCLI("agent-app-registry", ["doctor"], 20)
        return RegistryDoctorMapper.map(stdout: stdout, source: source)
    }

    private func pullSparklePending() -> [DoctorFinding] {
        guard resolveOnPath("sparkle-update-studio", pathRoots) != nil else { return [] }
        let (_, stdout) = runCLI("sparkle-update-studio", ["pending", "--json"], 45)
        return SparklePendingMapper.map(stdout: stdout, source: source)
    }

    private func pullSparkleFleet() -> [DoctorFinding] {
        guard resolveOnPath("sparkle-update-studio", pathRoots) != nil else { return [] }
        let (_, stdout) = runCLI("sparkle-update-studio", ["fleet", "--json"], 45)
        return SparkleFleetMapper.map(stdout: stdout, source: source)
    }
}
