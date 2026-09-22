import InteropKit
import Foundation
import LocalizationKit
import CommandKit


/// Gujo **hub** service readiness (gujo.ai download supply + multi-gate pack).
///
/// Does **not** thrash k8s pins. Runs installed CLIs on this Mac (macOS only).
/// Software store package deploy stays in `DeployPipelineProbe`.

public struct HubServiceGate: Sendable, Equatable, Identifiable, Codable {
    public let id: String
    public let title: String
    public let detail: String
    public let status: DeployStageStatus
    public let required: Bool

    public init(id: String, title: String, detail: String, status: DeployStageStatus, required: Bool) {
        self.id = id
        self.title = title
        self.detail = detail
        self.status = status
        self.required = required
    }
}

public struct HubServiceSnapshot: Sendable, Equatable {
    public let ready: Bool
    public let gates: [HubServiceGate]
    public let prescription: String?
    public let checkedAt: Date
    public let summary: String
    public let rawJSON: String?
    /// Quality-coordinator inbox item id if fail was filed (macOS).
    public let inboxNote: String?

    public init(
        ready: Bool,
        gates: [HubServiceGate],
        prescription: String?,
        checkedAt: Date = Date(),
        summary: String,
        rawJSON: String? = nil,
        inboxNote: String? = nil
    ) {
        self.ready = ready
        self.gates = gates
        self.prescription = prescription
        self.checkedAt = checkedAt
        self.summary = summary
        self.rawJSON = rawJSON
        self.inboxNote = inboxNote
    }
}

/// Decodes `gujo-download-pipeline-auditor service-pack --json`.
public struct ServicePackCLIReport: Sendable, Codable, Equatable {
    public var ok: Bool
    public var ready: Bool
    public var fetchedAt: String?
    public var gates: [ServicePackCLIGate]
    public var failGate: String?
    public var prescription: String?
}

public struct ServicePackCLIGate: Sendable, Codable, Equatable {
    public var id: String
    public var ok: Bool
    public var required: Bool
    public var skipped: Bool
    public var exitCode: Int
    public var detail: String
    public var durationMs: Int?
}

public enum HubServiceProbe {
    public static var auditorPathCandidates: [String] {
        [
            HostPlatform.cliBinPath("gujo-download-pipeline-auditor"),
            StoreOpsPaths.usrLocalCLI("gujo-download-pipeline-auditor"),
        ]
    }

    public static func probeAuditor(spec: BinaryProbeSpec = .gujoAuditorSpec) -> BinaryProbeResult {
        FastBinaryProbeEngine.probe(spec: spec)
    }

    public static func resolveAuditor() -> String? {
        probeAuditor().resolvedPath
    }

    /// `~/Library/Application Support/Gujo/service-pack/`
    public static var stateDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Gujo/service-pack", isDirectory: true)
    }

    public static var latestJSONURL: URL {
        stateDirectory.appendingPathComponent("latest.json")
    }

    public static var buyerHandoffLatestURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("VirtualBuyerJourneySimulator/handoff/personal/latest.md")
    }

    private static func describeProbeFailure(_ failure: BinaryProbeFailure?) -> (detail: String, summary: String) {
        guard let f = failure else {
            return (CLILocalization.string("HubServiceProbe.detail"), "auditor check failed")
        }
        switch f {
        case let .missing(paths):
            return ("Binary not found in candidate paths: \(paths.joined(separator: ", "))", "auditor missing")
        case let .permissionDenied(path):
            return ("Permission denied: \(path) lacks execution permission", "auditor permission denied")
        case let .architectureMismatch(path, found, req):
            return ("Architecture mismatch: \(path) has \(found), requires \(req)", "auditor arch mismatch")
        case let .versionOutdated(path, found, min):
            return ("Version outdated: \(path) is \(found), requires >= \(min)", "auditor version outdated")
        case let .probeExecutionFailed(path, code, msg):
            return ("Probe execution failed on \(path) (code \(code)): \(msg)", "auditor probe failed")
        }
    }

    /// Run full service-pack (supply + optional funnel/health/handoff).
    /// - Parameter onFailInbox: when not ready, file `agent-quality-coordinator inbox add` for @gujo-triage.
    public static func snapshot(
        skipFunnel: Bool = false,
        skipHealth: Bool = false,
        skipHandoff: Bool = false,
        timeoutSeconds: TimeInterval = 180,
        onFailInbox: Bool = false
    ) async -> HubServiceSnapshot {
        #if os(macOS)
        let probe = probeAuditor()
        guard let bin = probe.resolvedPath, probe.ok else {
            let (failureDetail, summaryDetail) = describeProbeFailure(probe.failure)
            let prescription = probe.remediation?.prescription ?? "Install gujo-download-pipeline-auditor to /opt/homebrew/bin"

            var snap = HubServiceSnapshot(
                ready: false,
                gates: [
                    HubServiceGate(
                        id: "auditor_cli",
                        title: "Auditor CLI",
                        detail: failureDetail,
                        status: .fail,
                        required: true
                    ),
                ],
                prescription: prescription,
                summary: "hub · \(summaryDetail)"
            )
            snap = await finalize(snap, onFailInbox: onFailInbox)
            return snap
        }

        var args = ["service-pack", "--json"]
        if skipFunnel { args.append("--skip-funnel") }
        if skipHealth { args.append("--skip-health") }
        if skipHandoff { args.append("--skip-handoff") }

        let run = await runProcess(bin, args: args, timeout: timeoutSeconds)
        if run.exitCode == 124 {
            let snap = HubServiceSnapshot(
                ready: false,
                gates: [
                    HubServiceGate(
                        id: "timeout",
                        title: "service-pack",
                        detail: "timeout after \(Int(timeoutSeconds))s",
                        status: .fail,
                        required: true
                    ),
                ],
                prescription: "service-pack hung — check VBJS funnel network",
                summary: "hub · timeout"
            )
            return await finalize(snap, onFailInbox: onFailInbox)
        }

        guard let data = run.stdout.data(using: .utf8),
              let report = try? JSONDecoder().decode(ServicePackCLIReport.self, from: data)
        else {
            let snip = String((run.stdout + run.stderr).prefix(280))
            let snap = HubServiceSnapshot(
                ready: false,
                gates: [
                    HubServiceGate(
                        id: "parse",
                        title: "service-pack JSON",
                        detail: "exit \(run.exitCode): \(snip)",
                        status: .fail,
                        required: true
                    ),
                ],
                prescription: "CLI failed to produce service-pack JSON",
                summary: "hub · parse fail · exit \(run.exitCode)",
                rawJSON: run.stdout.isEmpty ? nil : run.stdout
            )
            return await finalize(snap, onFailInbox: onFailInbox)
        }

        let gates: [HubServiceGate] = report.gates.map { g in
            let status: DeployStageStatus
            if g.skipped { status = .skip }
            else if g.ok { status = .ok }
            else { status = .fail }
            let title: String
            switch g.id {
            case "supply": title = "Hub download supply"
            case "funnel": title = "Buyer funnel (VBJS)"
            case "ops_health": title = "Laravel ops"
            case "handoff_surface": title = "Handoff surface"
            case "catalog_sim": title = "Catalog sim (pilot slot)"
            default: title = g.id
            }
            return HubServiceGate(
                id: g.id,
                title: title,
                detail: g.detail,
                status: status,
                required: g.required
            )
        }

        let summary = report.ready
            ? "hub · READY · \(gates.count) gates"
            : "hub · NOT READY · fail=\(report.failGate ?? "?")"

        let snap = HubServiceSnapshot(
            ready: report.ready,
            gates: gates,
            prescription: report.prescription,
            summary: summary,
            rawJSON: run.stdout
        )
        return await finalize(snap, onFailInbox: onFailInbox)
        #else
        return HubServiceSnapshot(
            ready: false,
            gates: [
                HubServiceGate(
                    id: "platform",
                    title: "Hub probe",
                    detail: "macOS only",
                    status: .skip,
                    required: false
                ),
            ],
            prescription: nil,
            summary: "hub · iOS n/a"
        )
        #endif
    }

    #if os(macOS)
    private static func finalize(_ snap: HubServiceSnapshot, onFailInbox: Bool) async -> HubServiceSnapshot {
        persistLatest(snap)
        guard !snap.ready, onFailInbox else { return snap }
        let note = await reportFailToQualityInbox(snap)
        return HubServiceSnapshot(
            ready: snap.ready,
            gates: snap.gates,
            prescription: snap.prescription,
            checkedAt: snap.checkedAt,
            summary: snap.summary,
            rawJSON: snap.rawJSON,
            inboxNote: note
        )
    }

    /// Persist last probe for seats / other tools.
    public static func persistLatest(_ snap: HubServiceSnapshot) {
        let dir = stateDirectory
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            fputs("hub persist: createDirectory failed: \(error.localizedDescription)\n", stderr)
            return
        }
        var payload: [String: Any] = [
            "ready": snap.ready,
            "summary": snap.summary,
            "checkedAt": ISO8601DateFormatter().string(from: snap.checkedAt),
            "prescription": snap.prescription as Any,
            "gates": snap.gates.map { g -> [String: Any] in
                [
                    "id": g.id,
                    "title": g.title,
                    "detail": g.detail,
                    "status": g.status.rawValue,
                    "required": g.required,
                ]
            },
        ]
        if let raw = snap.rawJSON { payload["rawJSON"] = raw }
        do {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: latestJSONURL, options: .atomic)
        } catch {
            fputs("hub persist: write failed: \(error.localizedDescription)\n", stderr)
        }
    }

    /// File a quality inbox item for triage (@gujo-triage).
    public static func reportFailToQualityInbox(_ snap: HubServiceSnapshot) async -> String {
        let inboxCLI = [
            HostPlatform.cliBinPath("agent-quality-coordinator"),
            StoreOpsPaths.usrLocalCLI("agent-quality-coordinator"),
        ].first { FileManager.default.isExecutableFile(atPath: $0) }
        guard let cli = inboxCLI else {
            return CLILocalization.string("HubServiceProbe.return")
        }
        let failIDs = snap.gates.filter { $0.status == .fail }.map(\.id).joined(separator: ",")
        let title = "Gujo hub service-pack FAIL · \(failIDs.isEmpty ? "unknown" : failIDs)"
        let body = """
        source: gujo-store-ops hub / HubServiceProbe
        seat: @gujo-triage
        summary: \(snap.summary)
        prescription: \(snap.prescription ?? "(none)")
        gates:
        \(snap.gates.map { "  - \($0.status.rawValue) \($0.id) req=\($0.required): \($0.detail)" }.joined(separator: "\n"))
        latest: \(latestJSONURL.path)
        rule: no k8s pin thrash; re-verify with `gujo-store-ops hub` after fix.
        """
        let run = await runProcess(
            cli,
            args: [
                "inbox", "add",
                "--title", title,
                "--body", body,
                "--source", "gujo-hub-service-pack",
                "--workdir", FileManager.default.currentDirectoryPath,
                "--json",
            ],
            timeout: StoreOpsLimits.processTimeout
        )
        if run.exitCode == 0 {
            let snip = run.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return snip.isEmpty ? "inbox add ok" : "inbox: \(snip.prefix(160))"
        }
        return "inbox add fail exit \(run.exitCode): \(run.stderr.prefix(120))"
    }

    private static func runProcess(
        _ path: String,
        args: [String],
        timeout: TimeInterval
    ) async -> (exitCode: Int32, stdout: String, stderr: String) {
        do {
            let result = try await SafeProcessRunner.run(
                executable: path,
                arguments: args,
                timeout: timeout
            )
            return (result.exitCode, result.stdout, result.stderr)
        } catch {
            return (127, "", String(describing: error))
        }
    }
    #endif
}

