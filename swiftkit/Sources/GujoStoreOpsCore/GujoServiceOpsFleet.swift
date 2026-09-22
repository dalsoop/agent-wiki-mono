import InteropKit
import Foundation
import LocalizationKit
import CommandKit


/// Gujo **service ops fleet** — seats + schedule jobs owned by Store Ops (not free-floating shell).
///
/// SSOT 문서: `docs/gujo-service-ops.md`
/// 실행 도구: `agent-schedule-dispatcher` · `agent-seat-manager` · catalog/auditor CLIs
/// 이 타입이 **등록·조회·실행** 을 Core 로 소유하고 GUI/CLI 가 같이 호출한다.

public struct GujoOpsJobSpec: Sendable, Equatable, Identifiable, Codable {
    public var id: String
    public var title: String
    public var intervalSeconds: Int
    public var script: String
    public var scriptArgs: [String]
    public var seat: String
    public var notes: String

    public init(
        id: String,
        title: String,
        intervalSeconds: Int,
        script: String,
        scriptArgs: [String],
        seat: String,
        notes: String = ""
    ) {
        self.id = id
        self.title = title
        self.intervalSeconds = intervalSeconds
        self.script = script
        self.scriptArgs = scriptArgs
        self.seat = seat
        self.notes = notes
    }
}

public struct GujoOpsJobStatus: Sendable, Equatable, Identifiable, Codable {
    public var id: String
    public var title: String
    public var registered: Bool
    public var enabled: Bool?
    public var intervalSeconds: Int
    public var intervalLabel: String
    public var seat: String
    public var detail: String
    /// 최근 dispatcher 실행 (없으면 nil)
    public var lastRunOk: Bool?
    public var lastRunAt: String?
    public var lastRunMs: Int?
    public var lastRunSummary: String?

    public init(
        id: String,
        title: String,
        registered: Bool,
        enabled: Bool?,
        intervalSeconds: Int,
        intervalLabel: String,
        seat: String,
        detail: String,
        lastRunOk: Bool? = nil,
        lastRunAt: String? = nil,
        lastRunMs: Int? = nil,
        lastRunSummary: String? = nil
    ) {
        self.id = id
        self.title = title
        self.registered = registered
        self.enabled = enabled
        self.intervalSeconds = intervalSeconds
        self.intervalLabel = intervalLabel
        self.seat = seat
        self.detail = detail
        self.lastRunOk = lastRunOk
        self.lastRunAt = lastRunAt
        self.lastRunMs = lastRunMs
        self.lastRunSummary = lastRunSummary
    }

    /// 한 줄 배지: 미등록 / 미실행 / 최근 ok|fail
    public var runBadge: String {
        if !registered { return CLILocalization.string("GujoServiceOpsFleet.return") }
        guard let ok = lastRunOk else { return CLILocalization.string("GujoServiceOpsFleet.return-2") }
        let when = lastRunAt.map { relativeRunLabel($0) } ?? ""
        return ok ? CLILocalization.format("GujoServiceOpsFleet.return-11", "\(when.isEmpty ? "" : " · \(when)")") : CLILocalization.format("GujoServiceOpsFleet.return-10", "\(when.isEmpty ? "" : " · \(when)")")
    }
}

/// ISO8601 시각 → 짧은 상대/로컬 표기.
public func relativeRunLabel(_ iso: String) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var d = f.date(from: iso)
    if d == nil {
        f.formatOptions = [.withInternetDateTime]
        d = f.date(from: iso)
    }
    guard let date = d else { return String(iso.prefix(16)) }
    let sec = Int(Date().timeIntervalSince(date))
    if sec < 60 { return CLILocalization.string("GujoServiceOpsFleet.return-3") }
    if sec < 3600 { return CLILocalization.format("GujoServiceOpsFleet.return-4", String(sec / 60)) }
    if sec < 86400 { return CLILocalization.format("GujoServiceOpsFleet.return-5", String(sec / 3600)) }
    let df = DateFormatter()
    df.locale = Locale(identifier: "ko_KR")
    df.dateFormat = "M/d HH:mm"
    return df.string(from: date)
}

public struct GujoOpsSeatStatus: Sendable, Equatable, Identifiable, Codable {
    public var id: String { handle }
    public var handle: String
    public var present: Bool
    public var tier: String?
    public var detail: String

    public init(handle: String, present: Bool, tier: String? = nil, detail: String) {
        self.handle = handle
        self.present = present
        self.tier = tier
        self.detail = detail
    }
}

public struct GujoServiceOpsFleetSnapshot: Sendable, Equatable {
    public var jobs: [GujoOpsJobStatus]
    public var seats: [GujoOpsSeatStatus]
    public var dispatcherOK: Bool
    public var seatManagerOK: Bool
    public var summary: String
    public var checkedAt: Date
    public var ensureNotes: [String]
    /// ready | degraded | missing — GUI 배지용
    public var health: String
    /// 사람이 다음에 누를 일 (한글)
    public var nextSteps: [String]

    public init(
        jobs: [GujoOpsJobStatus],
        seats: [GujoOpsSeatStatus],
        dispatcherOK: Bool,
        seatManagerOK: Bool,
        summary: String,
        checkedAt: Date = Date(),
        ensureNotes: [String] = [],
        health: String = "missing",
        nextSteps: [String] = []
    ) {
        self.jobs = jobs
        self.seats = seats
        self.dispatcherOK = dispatcherOK
        self.seatManagerOK = seatManagerOK
        self.summary = summary
        self.checkedAt = checkedAt
        self.ensureNotes = ensureNotes
        self.health = health
        self.nextSteps = nextSteps
    }

    public var allJobsRegistered: Bool { jobs.allSatisfy(\.registered) }
    public var allSeatsPresent: Bool { seats.allSatisfy(\.present) }
    public var healthTitleKO: String {
        switch health {
        case "ready": return CLILocalization.string("GujoServiceOpsFleet.return-7")
        case "degraded": return CLILocalization.string("GujoServiceOpsFleet.return-8")
        default: return CLILocalization.string("GujoServiceOpsFleet.return-9")
        }
    }

    /// 터미널 사람용 표 줄. 출력은 CLI 가 담당 (Core print 금지 — native-lint).
    public func humanLines() -> [String] {
        var lines: [String] = []
        lines.append("status  \(healthTitleKO)  (\(summary))")
        lines.append("tools   dispatcher=\(dispatcherOK ? "ok" : "missing")  seats-cli=\(seatManagerOK ? "ok" : "missing")")
        lines.append("")
        lines.append("JOBS")
        lines.append("  id                            reg    every    last           title")
        for j in jobs {
            let reg = j.registered ? "yes" : "NO"
            let last: String
            if let ok = j.lastRunOk {
                last = (ok ? "ok" : "FAIL") + (j.lastRunAt.map { " " + relativeRunLabel($0) } ?? "")
            } else {
                last = j.registered ? "never" : "-"
            }
            let idPad = j.id.padding(toLength: 28, withPad: " ", startingAt: 0)
            let regPad = reg.padding(toLength: 6, withPad: " ", startingAt: 0)
            let everyPad = j.intervalLabel.padding(toLength: 8, withPad: " ", startingAt: 0)
            let lastPad = last.padding(toLength: 14, withPad: " ", startingAt: 0)
            lines.append("  \(idPad) \(regPad) \(everyPad) \(lastPad) \(j.title)")
        }
        lines.append("")
        lines.append("SEATS")
        for s in seats {
            let h = s.handle.padding(toLength: 20, withPad: " ", startingAt: 0)
            let st = (s.present ? "ok" : "MISS").padding(toLength: 6, withPad: " ", startingAt: 0)
            lines.append("  \(h) \(st) \(s.detail)")
        }
        if !nextSteps.isEmpty {
            lines.append("")
            lines.append("NEXT")
            for (i, step) in nextSteps.enumerated() {
                lines.append("  \(i + 1). \(step)")
            }
        }
        return lines
    }

    public func jsonData() -> Data? {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        struct DTO: Encodable {
            var health: String
            var summary: String
            var dispatcherOK: Bool
            var seatManagerOK: Bool
            var jobs: [GujoOpsJobStatus]
            var seats: [GujoOpsSeatStatus]
            var nextSteps: [String]
            var ensureNotes: [String]
            var checkedAt: Date
        }
        let dto = DTO(
            health: health,
            summary: summary,
            dispatcherOK: dispatcherOK,
            seatManagerOK: seatManagerOK,
            jobs: jobs,
            seats: seats,
            nextSteps: nextSteps,
            ensureNotes: ensureNotes,
            checkedAt: checkedAt
        )
        do {
            return try enc.encode(dto)
        } catch {
            fputs("service-ops fleet encode failed: \(error.localizedDescription)\n", stderr)
            return nil
        }
    }
}

public enum GujoServiceOpsFleet {
    public static let expectedSeats = [
        "gujo-supply",
        "gujo-funnel",
        "gujo-ops-health",
        "gujo-triage",
        "gujo-admin",
    ]

    /// Canonical schedule set (docs/gujo-service-ops.md).
    public static var jobSpecs: [GujoOpsJobSpec] {
        let homebrew = HostPlatform.homebrewBin
        let auditor = "\(homebrew)/gujo-download-pipeline-auditor"
        let runner = "\(homebrew)/virtual-buyer-journey-simulator-runner"
        let catalog = "\(homebrew)/gujo-catalog-manager"
        return [
            GujoOpsJobSpec(
                id: "gujo-supply-audit",
                title: "Supply audit",
                intervalSeconds: 3600,
                script: auditor,
                scriptArgs: ["audit", "--json"],
                seat: "@gujo-supply",
                notes: "desktop download pipeline"
            ),
            GujoOpsJobSpec(
                id: "gujo-service-pack-script",
                title: "Service pack (skip live funnel)",
                intervalSeconds: 21600,
                script: auditor,
                scriptArgs: ["service-pack", "--json", "--skip-funnel"],
                seat: "@gujo-ops-health",
                notes: "supply+health+handoff+catalog_sim"
            ),
            GujoOpsJobSpec(
                id: "gujo-catalog-sim-verify",
                title: "Catalog sim verify",
                intervalSeconds: 21600,
                script: catalog,
                scriptArgs: [
                    "simulations", "run",
                    "--app", "gujo-catalog-manager-swift",
                    "--slot", "shelf-policy-list",
                ],
                seat: "@gujo-supply",
                notes: "Packaging/simulation.json pilot"
            ),
            GujoOpsJobSpec(
                id: "gujo-funnel-ops-scripted",
                title: "Funnel ops-check (scripted)",
                intervalSeconds: 86400,
                script: runner,
                scriptArgs: [
                    "ops-check", "--tenant", "personal",
                    "--scripted", "--json",
                ],
                seat: "@gujo-funnel",
                notes: "offline smoke; live is manual"
            ),
        ]
    }

    public static var dispatcherCandidates: [String] {
        [
            HostPlatform.cliBinPath("agent-schedule-dispatcher"),
            StoreOpsPaths.usrLocalCLI("agent-schedule-dispatcher"),
        ]
    }

    public static var seatManagerCandidates: [String] {
        [
            HostPlatform.cliBinPath("agent-seat-manager"),
            StoreOpsPaths.usrLocalCLI("agent-seat-manager"),
        ]
    }

    public static func resolveDispatcher() -> String? {
        dispatcherCandidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public static func resolveSeatManager() -> String? {
        seatManagerCandidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public static var monoRoot: String {
        StoreOpsPaths.resolveMonoRoot()
    }

    public static func snapshot() async -> GujoServiceOpsFleetSnapshot {
        #if os(macOS)
        return await snapshotMac()
        #else
        return GujoServiceOpsFleetSnapshot(
            jobs: [],
            seats: [],
            dispatcherOK: false,
            seatManagerOK: false,
            summary: "service ops fleet · iOS n/a"
        )
        #endif
    }

    public static func ensureJobs() async -> (snapshot: GujoServiceOpsFleetSnapshot, notes: [String]) {
        #if os(macOS)
        return await ensureJobsMac()
        #else
        return (await snapshot(), ["iOS n/a"])
        #endif
    }

    public static func runJob(id: String, timeout: TimeInterval = 600) async -> (ok: Bool, detail: String) {
        #if os(macOS)
        return await runJobMac(id: id, timeout: timeout)
        #else
        return (false, "macOS only")
        #endif
    }

    public static func runCatalogSim() async -> (ok: Bool, detail: String) {
        #if os(macOS)
        return await runCatalogSimMac()
        #else
        return (false, "macOS only")
        #endif
    }

    #if os(macOS)
    private static func snapshotMac() async -> GujoServiceOpsFleetSnapshot {
        let disp = resolveDispatcher()
        let seatsCLI = resolveSeatManager()
        var jobStatuses: [GujoOpsJobStatus] = []
        var registeredIDs = Set<String>()
        var registeredMeta: [String: (enabled: Bool?, interval: Int?)] = [:]

        var lastRuns: [String: (ok: Bool, at: String?, ms: Int?, summary: String?)] = [:]
        if let disp {
            let r = await runProcess(disp, args: ["jobs", "--json"], timeout: 20)
            if r.exitCode == 0, let data = r.stdout.data(using: .utf8),
               let arr = parseJobsJSON(data)
            {
                for j in arr {
                    if let id = j["id"] as? String {
                        registeredIDs.insert(id)
                        let en = j["enabled"] as? Bool
                        let iv = j["intervalSeconds"] as? Int
                        registeredMeta[id] = (en, iv)
                    }
                }
            }
            let rr = await runProcess(disp, args: ["runs", "--json"], timeout: 20)
            if rr.exitCode == 0, let data = rr.stdout.data(using: .utf8) {
                lastRuns = parseLatestRuns(data)
            }
        }

        for spec in jobSpecs {
            let reg = registeredIDs.contains(spec.id)
            let meta = registeredMeta[spec.id]
            let run = lastRuns[spec.id]
            jobStatuses.append(
                GujoOpsJobStatus(
                    id: spec.id,
                    title: spec.title,
                    registered: reg,
                    enabled: meta?.enabled,
                    intervalSeconds: meta?.interval ?? spec.intervalSeconds,
                    intervalLabel: intervalLabel(meta?.interval ?? spec.intervalSeconds),
                    seat: spec.seat,
                    detail: reg
                        ? (meta?.enabled == false ? CLILocalization.string("GujoServiceOpsFleet.string-12") : CLILocalization.string("GujoServiceOpsFleet.string-11"))
                        : "미등록 — ensure 필요",
                    lastRunOk: run?.ok,
                    lastRunAt: run?.at,
                    lastRunMs: run?.ms,
                    lastRunSummary: run?.summary
                )
            )
        }

        var seatStatuses: [GujoOpsSeatStatus] = []
        if let seatsCLI {
            // 동시 부하 시 seats --json 일시 실패 → 재시도 (실측 거짓 음수 방지)
            var present = Set<String>()
            var tiers: [String: String] = [:]
            var okFetch = false
            for attempt in 1...3 {
                let r = await runProcess(seatsCLI, args: ["seats", "--json"], timeout: 25)
                if r.exitCode == 0, let data = r.stdout.data(using: .utf8) {
                    present = parseSeatHandles(data)
                    tiers = parseSeatTiers(data)
                    okFetch = true
                    break
                }
                if attempt < 3 {
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 200_000_000)
                }
            }
            if okFetch {
                for h in expectedSeats {
                    let ok = present.contains(h) || present.contains("@\(h)")
                    seatStatuses.append(
                        GujoOpsSeatStatus(
                            handle: "@\(h)",
                            present: ok,
                            tier: tiers[h] ?? tiers["@\(h)"],
                            detail: ok ? CLILocalization.string("GujoServiceOpsFleet.string-10") : CLILocalization.string("GujoServiceOpsFleet.string-9")
                        )
                    )
                }
            } else {
                for h in expectedSeats {
                    seatStatuses.append(
                        GujoOpsSeatStatus(
                            handle: "@\(h)",
                            present: false,
                            detail: CLILocalization.string("GujoServiceOpsFleet.detail")
                        )
                    )
                }
            }
        } else {
            for h in expectedSeats {
                seatStatuses.append(
                    GujoOpsSeatStatus(
                        handle: "@\(h)",
                        present: false,
                        detail: CLILocalization.string("GujoServiceOpsFleet.detail-2")
                    )
                )
            }
        }

        return makeSnapshot(
            jobs: jobStatuses,
            seats: seatStatuses,
            dispatcherOK: disp != nil,
            seatManagerOK: seatsCLI != nil
        )
    }

    private static func makeSnapshot(
        jobs: [GujoOpsJobStatus],
        seats: [GujoOpsSeatStatus],
        dispatcherOK: Bool,
        seatManagerOK: Bool,
        ensureNotes: [String] = []
    ) -> GujoServiceOpsFleetSnapshot {
        let missingJobs = jobs.filter { !$0.registered }.count
        let missingSeats = seats.filter { !$0.present }.count
        let failedRuns = jobs.filter { $0.lastRunOk == false }.count
        let neverRun = jobs.filter { $0.registered && $0.lastRunOk == nil }.count
        let summary =
            CLILocalization.format("GujoServiceOpsFleet.string-8", "\(jobs.count - missingJobs)", "\(jobs.count)", "\(seats.count - missingSeats)", "\(seats.count)")
            + (failedRuns > 0 ? CLILocalization.format("GujoServiceOpsFleet.string-7", "\(failedRuns)") : "")
            + (!dispatcherOK ? CLILocalization.string("GujoServiceOpsFleet.string-6") : "")

        var steps: [String] = []
        if !dispatcherOK {
            steps.append("agent-schedule-dispatcher 설치 후 다시 새로고침")
        }
        if missingJobs > 0 {
            steps.append(CLILocalization.format("GujoServiceOpsFleet.string-5", "\(missingJobs)"))
        }
        if missingSeats > 0 {
            steps.append(CLILocalization.format("GujoServiceOpsFleet.string-4", "\(missingSeats)"))
        }
        if failedRuns > 0 {
            steps.append("실패한 잡 옆 「지금 실행」으로 재검증")
        }
        if neverRun > 0 && missingJobs == 0 {
            steps.append(CLILocalization.format("GujoServiceOpsFleet.string-3", "\(neverRun)"))
        }
        // hub CLI/GUI 프로브 또는 스케줄 service-pack 최근 성공 → 이미 커버됨
        let hubFresh = ServiceOpsContext.hubReadyWithin(minutes: StoreOpsLimits.hubReadyWindowMinutes)
        let packFresh = jobSucceededWithin(
            jobs: jobs,
            id: "gujo-service-pack-script",
            hours: 7
        )
        let packCovered = hubFresh || packFresh
        let tokenOK = OpsPreferences.bearerToken != nil
        if !tokenOK {
            steps.append("배포 API 용: Keychain net.ranode.gujo / staff")
        }
        if steps.isEmpty {
            if packCovered {
                steps.append("함대·service-pack 정상 — 스케줄러 유지하면 됨")
                steps.append("배포/폰 설치는 「운영」탭 · 배포 API는 doctor 의 deploy 축")
            } else {
                steps.append("「전체 점검」(hub) 으로 service-pack 프로브")
                steps.append("이상 없으면 스케줄러 tick 유지")
            }
        }

        let health: String
        if !dispatcherOK || missingJobs > 0 || missingSeats > 0 {
            health = "missing"
        } else if failedRuns > 0 {
            health = "degraded"
        } else {
            health = "ready"
        }

        ServiceOpsContext.recordFleet(health: health)

        return GujoServiceOpsFleetSnapshot(
            jobs: jobs,
            seats: seats,
            dispatcherOK: dispatcherOK,
            seatManagerOK: seatManagerOK,
            summary: summary,
            ensureNotes: ensureNotes,
            health: health,
            nextSteps: steps
        )
    }

    /// 잡 최근 성공이 hours 이내인지 (ISO lastRunAt 기준).
    private static func jobSucceededWithin(
        jobs: [GujoOpsJobStatus],
        id: String,
        hours: Int
    ) -> Bool {
        guard let j = jobs.first(where: { $0.id == id }),
              j.lastRunOk == true,
              let at = j.lastRunAt
        else { return false }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var d = f.date(from: at)
        if d == nil {
            f.formatOptions = [.withInternetDateTime]
            d = f.date(from: at)
        }
        guard let date = d else { return true } // 파싱 실패 시 ok 플래그만 신뢰
        return Date().timeIntervalSince(date) < Double(hours * 3600)
    }

    private static func ensureJobsMac() async -> (snapshot: GujoServiceOpsFleetSnapshot, notes: [String]) {
        guard let disp = resolveDispatcher() else {
            let snap = await snapshotMac()
            let notes = ["agent-schedule-dispatcher 미설치"]
            return (
                makeSnapshot(
                    jobs: snap.jobs,
                    seats: snap.seats,
                    dispatcherOK: false,
                    seatManagerOK: snap.seatManagerOK,
                    ensureNotes: notes
                ),
                notes
            )
        }
        var notes: [String] = []
        let before = await snapshotMac()
        for spec in jobSpecs where !before.jobs.contains(where: { $0.id == spec.id && $0.registered }) {
            var args = [
                "job", "add",
                spec.title,
                monoRoot,
                "Gujo service ops · \(spec.id) · \(spec.notes)",
                "--id", spec.id,
                "--every", "\(spec.intervalSeconds)",
                "--script", spec.script,
            ]
            for a in spec.scriptArgs {
                args.append(contentsOf: ["--script-arg", a])
            }
            let r = await runProcess(disp, args: args, timeout: StoreOpsLimits.processTimeout)
            if r.exitCode == 0 {
                notes.append(CLILocalization.format("GujoServiceOpsFleet.string-2", "\(spec.id)"))
            } else {
                notes.append(CLILocalization.format("GujoServiceOpsFleet.string", "\(spec.id)", "\(r.exitCode)", "\(String((r.stderr + r.stdout).prefix(120)))"))
            }
        }
        if notes.isEmpty { notes.append("이미 전부 등록됨") }
        let after = await snapshotMac()
        return (
            makeSnapshot(
                jobs: after.jobs,
                seats: after.seats,
                dispatcherOK: after.dispatcherOK,
                seatManagerOK: after.seatManagerOK,
                ensureNotes: notes
            ),
            notes
        )
    }

    private static func runJobMac(id: String, timeout: TimeInterval) async -> (ok: Bool, detail: String) {
        guard let disp = resolveDispatcher() else {
            return (false, "agent-schedule-dispatcher 미설치")
        }
        let r = await runProcess(disp, args: ["run", id], timeout: timeout)
        let snip = String((r.stdout + r.stderr).trimmingCharacters(in: .whitespacesAndNewlines).prefix(400))
        return (r.exitCode == 0, snip.isEmpty ? "exit \(r.exitCode)" : snip)
    }

    private static func runCatalogSimMac() async -> (ok: Bool, detail: String) {
        let bin = [
            HostPlatform.cliBinPath("gujo-catalog-manager"),
            StoreOpsPaths.usrLocalCLI("gujo-catalog-manager"),
        ].first { FileManager.default.isExecutableFile(atPath: $0) }
        guard let bin else { return (false, "gujo-catalog-manager 미설치") }
        let r = await runProcess(
            bin,
            args: [
                "simulations", "run",
                "--app", "gujo-catalog-manager-swift",
                "--slot", "shelf-policy-list",
            ],
            timeout: StoreOpsLimits.catalogSimTimeout
        )
        let snip = String((r.stdout + r.stderr).trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        return (r.exitCode == 0, snip.isEmpty ? "exit \(r.exitCode)" : snip)
    }

    // MARK: - parse helpers

    /// runs --json 배열에서 jobID 별 최신 1건.
    private static func parseLatestRuns(_ data: Data) -> [String: (ok: Bool, at: String?, ms: Int?, summary: String?)] {
        var out: [String: (ok: Bool, at: String?, ms: Int?, summary: String?)] = [:]
        guard let root = StoreOpsJSON.raw(from: data) else { return out }
        let arr: [[String: Any]]
        if let a = root as? [[String: Any]] {
            arr = a
        } else if let d = root as? [String: Any], let a = d["runs"] as? [[String: Any]] {
            arr = a
        } else if let d = root as? [String: Any], let r = d["result"] as? [[String: Any]] {
            arr = r
        } else {
            arr = []
        }
        // 최신이 앞이라고 가정 — 이미 있으면 skip
        for row in arr {
            let id = (row["jobID"] as? String) ?? (row["jobId"] as? String) ?? (row["jobName"] as? String)
            guard let id, out[id] == nil else { continue }
            let ok = (row["ok"] as? Bool) ?? ((row["exitCode"] as? Int) == 0)
            let at = (row["endedAt"] as? String) ?? (row["startedAt"] as? String)
            let ms = row["ms"] as? Int
            let summary = row["summary"] as? String
            let short = summary.map { String($0.prefix(120)).replacingOccurrences(of: "\n", with: " ") }
            out[id] = (ok, at, ms, short)
        }
        return out
    }

    private static func parseJobsJSON(_ data: Data) -> [[String: Any]]? {
        guard let root = StoreOpsJSON.raw(from: data) else { return nil }
        if let arr = root as? [[String: Any]] { return arr }
        if let d = root as? [String: Any] {
            if let arr = d["jobs"] as? [[String: Any]] { return arr }
            if let r = d["result"] as? [String: Any], let arr = r["jobs"] as? [[String: Any]] { return arr }
            if let r = d["result"] as? [[String: Any]] { return r }
        }
        return nil
    }

    private static func parseSeatHandles(_ data: Data) -> Set<String> {
        var out = Set<String>()
        guard let root = StoreOpsJSON.raw(from: data) else { return out }
        let seats: [[String: Any]]
        if let arr = root as? [[String: Any]] {
            seats = arr
        } else if let d = root as? [String: Any] {
            if let arr = d["seats"] as? [[String: Any]] {
                seats = arr
            } else if let r = d["result"] as? [String: Any], let arr = r["seats"] as? [[String: Any]] {
                seats = arr
            } else if let r = d["result"] as? [[String: Any]] {
                seats = r
            } else {
                seats = []
            }
        } else {
            seats = []
        }
        for s in seats {
            if let h = s["handle"] as? String {
                out.insert(h)
                out.insert(h.hasPrefix("@") ? String(h.dropFirst()) : h)
            }
        }
        return out
    }

    private static func parseSeatTiers(_ data: Data) -> [String: String] {
        var out: [String: String] = [:]
        guard let root = StoreOpsJSON.raw(from: data) else { return out }
        let seats: [[String: Any]]
        if let arr = root as? [[String: Any]] {
            seats = arr
        } else if let d = root as? [String: Any] {
            if let arr = d["seats"] as? [[String: Any]] {
                seats = arr
            } else if let r = d["result"] as? [String: Any], let arr = r["seats"] as? [[String: Any]] {
                seats = arr
            } else {
                seats = []
            }
        } else {
            seats = []
        }
        for s in seats {
            guard let h = s["handle"] as? String else { continue }
            if let t = s["tier"] as? String { out[h] = t }
        }
        return out
    }

    private static func intervalLabel(_ sec: Int) -> String {
        if sec >= 86400 { return "\(sec / 86400)d" }
        if sec >= 3600 { return "\(sec / 3600)h" }
        if sec >= 60 { return "\(sec / 60)m" }
        return "\(sec)s"
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

