import Foundation

/// 배포 파이프라인 단계 상태.
public enum DeployStageStatus: String, Sendable, Codable, Equatable {
    case idle
    case running
    case ok
    case fail
    case skip
}

/// 관측 가능한 배포 단계 한 칸.
public struct DeployStage: Sendable, Equatable, Identifiable, Codable {
    public let id: String
    public let title: String
    public let detail: String
    public let status: DeployStageStatus

    public init(id: String, title: String, detail: String, status: DeployStageStatus) {
        self.id = id
        self.title = title
        self.detail = detail
        self.status = status
    }
}

/// 서버 감사 이벤트.
public struct OpsAuditEvent: Sendable, Equatable, Identifiable, Codable {
    public let id: String
    public let actor: String
    public let action: String
    public let resourceType: String
    public let resourceId: String
    public let at: String?
    public let metaNote: String?

    public init(
        id: String,
        actor: String,
        action: String,
        resourceType: String,
        resourceId: String,
        at: String? = nil,
        metaNote: String? = nil
    ) {
        self.id = id
        self.actor = actor
        self.action = action
        self.resourceType = resourceType
        self.resourceId = resourceId
        self.at = at
        self.metaNote = metaNote
    }
}

/// 배포 스냅샷 — UI 타임라인 + 감사 로그.
public struct DeploySnapshot: Sendable, Equatable {
    public let stages: [DeployStage]
    public let audit: [OpsAuditEvent]
    public let opsBase: String
    public let checkedAt: Date
    public let summary: String

    public init(
        stages: [DeployStage],
        audit: [OpsAuditEvent],
        opsBase: String,
        checkedAt: Date = Date(),
        summary: String
    ) {
        self.stages = stages
        self.audit = audit
        self.opsBase = opsBase
        self.checkedAt = checkedAt
        self.summary = summary
    }

    public var allOk: Bool {
        stages.allSatisfy { $0.status == .ok || $0.status == .skip }
    }
}

/// 클라이언트에서 관측 가능한 배포 경로를 프로브한다.
///
/// Git/k8s pin 은 이 Mac 앱 밖 권한 — UI 는 **ops health · catalog · packages · publish · jobs** 축만 표시.
public enum DeployPipelineProbe {
    public static func snapshot(
        client: StoreOpsClient,
        selectedPackage: String? = nil
    ) async -> DeploySnapshot {
        var stages: [DeployStage] = []
        var audit: [OpsAuditEvent] = []
        let base = client.opsBaseURL.absoluteString

        // 1. Ops health
        var health: OpsHealth?
        do {
            health = try await client.health()
            let h = health!
            stages.append(.init(
                id: "ops_health",
                title: "Ops API",
                detail: "\(h.service) · ok=\(h.ok)",
                status: h.ok ? .ok : .fail
            ))
        } catch {
            stages.append(.init(
                id: "ops_health",
                title: "Ops API",
                detail: error.localizedDescription,
                status: .fail
            ))
        }

        // 2. Ops auth (STORE_OPS_TOKEN)
        let auth = health?.opsAuth ?? "unknown"
        let tokenOk = OpsPreferences.bearerToken != nil
        let authDetail: String
        let authStatus: DeployStageStatus
        switch auth {
        case "required":
            authDetail = tokenOk ? "Bearer required · client token set" : "Bearer required · client token MISSING"
            authStatus = tokenOk ? .ok : .fail
        case "open":
            authDetail = "auth open (local)"
            authStatus = .ok
        default:
            authDetail = auth
            authStatus = .idle
        }
        stages.append(.init(
            id: "ops_auth",
            title: "Ops auth",
            detail: authDetail,
            status: authStatus
        ))

        // 3. Catalog bridge
        let bridge = health?.catalogBridge ?? "unknown"
        stages.append(.init(
            id: "catalog_bridge",
            title: "Catalog bridge",
            detail: bridge,
            status: bridge == "up" ? .ok : (bridge == "down" ? .fail : .idle)
        ))

        // 4. Catalog publish configured
        let pub = health?.catalogPublish ?? "unknown"
        stages.append(.init(
            id: "catalog_publish",
            title: "Catalog publish",
            detail: pub == "configured"
                ? "CATALOG_PUBLISH_TOKEN ready"
                : (pub == "unconfigured" ? "token missing on server" : pub),
            status: pub == "configured" ? .ok : (pub == "unconfigured" ? .fail : .idle)
        ))

        // 4. Packages live
        var packages: [OpsPackage] = []
        do {
            packages = try await client.listPackages()
            stages.append(.init(
                id: "packages_live",
                title: "Packages live",
                detail: "\(packages.count) packages",
                status: packages.isEmpty ? .fail : .ok
            ))
        } catch {
            stages.append(.init(
                id: "packages_live",
                title: "Packages live",
                detail: error.localizedDescription,
                status: .fail
            ))
        }

        // 5. Selected / first package published
        let focus = selectedPackage.flatMap { name in packages.first { $0.packageName == name } }
            ?? packages.first
        if let pkg = focus {
            let hasInstall = pkg.installURL != nil || pkg.artifactURL != nil
            let published = pkg.status == "published" || hasInstall
            stages.append(.init(
                id: "package_ready",
                title: "Package ready",
                detail: "\(pkg.packageName) · \(pkg.versionName ?? "-") · \(pkg.status)",
                status: published ? .ok : .fail
            ))
        } else {
            stages.append(.init(
                id: "package_ready",
                title: "Package ready",
                detail: "no package",
                status: .skip
            ))
        }

        // 6. Mac runners
        do {
            let runners = try await client.listRunners()
            let online = runners.filter(\.online).count
            let fromHealth = health?.runnersOnline
            stages.append(.init(
                id: "runners",
                title: "Mac runners",
                detail: "\(online) online / \(runners.count) known"
                    + (fromHealth.map { " · health=\($0)" } ?? ""),
                status: online > 0 ? .ok : (runners.isEmpty ? .idle : .fail)
            ))
        } catch {
            stages.append(.init(
                id: "runners",
                title: "Mac runners",
                detail: error.localizedDescription,
                status: .fail
            ))
        }

        // 7. Install jobs API (ops path)
        do {
            let jobs = try await client.listInstallJobs()
            let active = jobs.filter { $0.status == .queued || $0.status == .running || $0.status == .claimed }.count
            stages.append(.init(
                id: "install_jobs",
                title: "Install jobs API",
                detail: "\(jobs.count) total · \(active) active",
                status: .ok
            ))
        } catch {
            stages.append(.init(
                id: "install_jobs",
                title: "Install jobs API",
                detail: error.localizedDescription,
                status: .fail
            ))
        }

        // 8. Audit timeline (publish + job events)
        do {
            audit = try await client.listAudit(limit: StoreOpsLimits.auditEventLimit)
            let publishEvents = audit.filter { $0.action.contains("publish") }.count
            let jobEvents = audit.filter { $0.action.contains("install_job") }.count
            stages.append(.init(
                id: "audit",
                title: "Audit timeline",
                detail: "\(audit.count) events · publish \(publishEvents) · jobs \(jobEvents)",
                status: .ok
            ))
        } catch {
            stages.append(.init(
                id: "audit",
                title: "Audit timeline",
                detail: error.localizedDescription,
                status: .fail
            ))
        }

        let okCount = stages.filter { $0.status == .ok }.count
        let failCount = stages.filter { $0.status == .fail }.count
        let summary = "\(okCount)/\(stages.count) ok · fail \(failCount) · \(base)"

        return DeploySnapshot(stages: stages, audit: audit, opsBase: base, summary: summary)
    }
}
