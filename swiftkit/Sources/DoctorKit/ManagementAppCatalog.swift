import Foundation
import InteropKit

// MARK: - Catalog

/// One fleet-management app agents must use before ad-hoc shell repair.
///
/// These own dual-entry / PATH CLI / ship / registry — not random apps.
public struct ManagementAppSpec: Sendable, Codable, Equatable, Identifiable {
    public var id: String
    public var cli: String
    public var displayName: String
    /// Short ownership sentence (why this exists).
    public var role: String
    /// Possible `/Applications/<name>.app` basenames (without .app).
    public var appBundleNames: [String]
    /// Missing this tool is a hard fail for agent hygiene.
    public var critical: Bool
    /// Prefer Helpers symlink dual-entry (plain PATH copy = stale).
    public var expectsHelpersSymlink: Bool

    public init(
        id: String,
        cli: String,
        displayName: String,
        role: String,
        appBundleNames: [String],
        critical: Bool = true,
        expectsHelpersSymlink: Bool = true
    ) {
        self.id = id
        self.cli = cli
        self.displayName = displayName
        self.role = role
        self.appBundleNames = appBundleNames
        self.critical = critical
        self.expectsHelpersSymlink = expectsHelpersSymlink
    }
}

public enum ManagementAppCatalog {
    /// 관리 도구 ownership SSOT.
    ///
    /// 에이전트·사람이 "어떤 CLI 관리 앱을 써야 하나" 를 찾을 때 이 목록이 정본이다.
    /// 관측 합성은 `app-fleet-doctor managers` — 수리 실행은 각 소유 CLI.
    public static let builtIn: [ManagementAppSpec] = [
        ManagementAppSpec(
            id: "app-fleet-doctor",
            cli: "app-fleet-doctor",
            displayName: "App Fleet Doctor",
            role: "관리 도구 SSOT 합성기 — managers 로 전부 점검 (이 카탈로그 소비자)",
            appBundleNames: ["AppFleetDoctor", "App Fleet Doctor", "App Set Doctor"]
        ),
        ManagementAppSpec(
            id: "path-cli-health",
            cli: "path-cli-health",
            displayName: "Path CLI Health",
            role: "PATH dual-entry 건강 · 낡은 사본 · GUI 심링크 (repair-copies/hygiene) 정본",
            appBundleNames: ["PathCLIHealth", "Path CLI Health"]
        ),
        ManagementAppSpec(
            id: "agent-cli-manager",
            cli: "agent-cli-manager",
            displayName: "Agent CLI Manager",
            role: "에이전트용 앱 CLI 카탈로그 · naming · PATH shadow · path-gap 정본",
            appBundleNames: ["AgentCLIManager", "Agent CLI Manager"]
        ),
        ManagementAppSpec(
            id: "agent-host-doctor",
            cli: "agent-host-doctor",
            displayName: "Agent Host Doctor",
            role: "호스트 생존 정책 · dual-entry · lag/hooks",
            appBundleNames: ["Agent Host Doctor", "AgentHostDoctor"]
        ),
        ManagementAppSpec(
            id: "app-build-manager",
            cli: "app-build-manager",
            displayName: "App Build Manager",
            role: "함대 소스 freshness · ship · ship-queue · rollout. 발행·수신 아님",
            appBundleNames: ["AppBuildManager", "App Build Manager"]
        ),
        ManagementAppSpec(
            id: "agent-app-registry",
            cli: "agent-app-registry",
            displayName: "Agent App Registry",
            role: "함대 목록 SSOT (~/.agent-apps/registry.json) · search/doctor",
            appBundleNames: ["Agent App Registry", "AgentAppRegistry"]
        ),
        ManagementAppSpec(
            id: "app-health-guard",
            cli: "app-health-guard",
            displayName: "App Health Guard",
            role: "install-health 상시 감시",
            appBundleNames: ["App Health Guard", "AppHealthGuard"],
            critical: false
        ),
        ManagementAppSpec(
            id: "app-fleet-quality-auditor",
            cli: "app-fleet-quality-auditor",
            displayName: "App Set Quality Auditor",
            role: "소스/설치 품질 감사 (launch-contract 확정 등)",
            appBundleNames: [
                "App Set Quality Auditor",
                "AppFleetQualityAuditor",
                "App Fleet Quality Auditor",
                "app-fleet-quality-auditor",
            ],
            critical: false
        ),
        ManagementAppSpec(
            id: "gujo-store-ops",
            cli: "gujo-store-ops",
            displayName: "Gujo Store Ops",
            role: "Gujo 공개 store/ops 허브 · hub/service-pack 운영 표면",
            appBundleNames: ["GujoStoreOps", "Gujo Store Ops"],
            critical: false
        ),
        ManagementAppSpec(
            id: "gujo-download-pipeline-auditor",
            cli: "gujo-download-pipeline-auditor",
            displayName: "Gujo Download Pipeline Auditor",
            role: "Gujo download supply · service-pack 게이트 (결정론 검증, LLM 자기평가 금지)",
            appBundleNames: [],
            critical: false,
            expectsHelpersSymlink: false
        ),
        ManagementAppSpec(
            id: "fleet-health-check",
            cli: "fleet-health-check",
            displayName: "Fleet Health Check",
            role: "함대 헬스 스크립트/CLI (legacy)",
            appBundleNames: [],
            critical: false,
            expectsHelpersSymlink: false
        ),
        // --- meta platform (optional but thrash-prone) ---
        ManagementAppSpec(
            id: "gujo-managed-adoption-manager",
            cli: "gujo-managed-adoption-manager",
            displayName: "Gujo Managed Adoption Manager",
            role: "Cloud Apps / .gujoManaged 채택 스캔 정본",
            appBundleNames: ["GujoManagedAdoptionManager", "Gujo Managed Adoption Manager"],
            critical: false
        ),
        ManagementAppSpec(
            id: "agent-control-plane",
            cli: "agent-control-plane",
            displayName: "Agent Control Plane",
            role: "라이브 실행·세션 라우팅·worktree 매핑",
            appBundleNames: ["AgentControlPlane", "Agent Control Plane"],
            critical: false
        ),
        ManagementAppSpec(
            id: "app-launch-doctor",
            cli: "app-launch-doctor",
            displayName: "App Launch Doctor",
            role: "아이콘 런치·launch-contract 진단",
            appBundleNames: ["AppLaunchDoctor", "App Launch Doctor"],
            critical: false
        ),
        ManagementAppSpec(
            id: "gujo-cloud-apps",
            cli: "gujo-cloud-apps",
            displayName: "Gujo Cloud Apps",
            role: "구매자 CDN 수신 (software update). 함대 소스 재설치·appcast 발행 아님",
            appBundleNames: ["Gujo Cloud Apps", "GujoCloudApps"]
        ),
        ManagementAppSpec(
            id: "sparkle-update-studio",
            cli: "sparkle-update-studio",
            displayName: "Gujo Updates",
            role: "Sparkle CDN 발행 (publish/pending/fleet/audit). 수신·로컬 ship 아님",
            appBundleNames: ["SparkleUpdateStudio", "Gujo Updates"]
        ),
        ManagementAppSpec(
            id: "app-notary-manager",
            cli: "app-notary-manager",
            displayName: "App Notary Manager",
            role: "공증 제출 정본. 로컬 80 한도는 게이트가 아님",
            appBundleNames: ["AppNotaryManager", "App Notary Manager"]
        ),
        ManagementAppSpec(
            id: "app-ship-manager",
            cli: "app-ship-manager",
            displayName: "App Ship Manager",
            role: "ship-queue GUI. 실행 정본은 app-build-manager",
            appBundleNames: ["AppShipManager", "App Ship Manager"],
            critical: false
        ),
        ManagementAppSpec(
            id: "agent-surface-reach",
            cli: "agent-surface-reach",
            displayName: "Agent Surface Reach",
            role: "에이전트 가시화 행렬 정본. matrix --slug --strict. 함대 --gaps 는 게이트 아님",
            appBundleNames: ["AgentSurfaceReach", "Agent Surface Reach"],
            critical: false
        ),
        ManagementAppSpec(
            id: "agent-cli-scaffold",
            cli: "agent-cli-scaffold",
            displayName: "Agent CLI Scaffold",
            role: "앱 생성·레일·pipeline next. ship 뒤 next 는 surface-reach matrix --strict",
            appBundleNames: ["AgentCliScaffold", "Agent CLI Scaffold"],
            critical: false
        ),
        ManagementAppSpec(
            id: "code-sign-helper",
            cli: "code-sign-helper",
            displayName: "Code Sign Helper",
            role: "코드서명 스크립트 정규화 보조",
            appBundleNames: ["CodeSignHelper", "Code Sign Helper"],
            critical: false
        ),
        ManagementAppSpec(
            id: "agent-registry-manager",
            cli: "agent-registry-manager",
            displayName: "Agent Registry Manager",
            role: "레지스트리 운영 GUI (목록 SSOT 는 agent-app-registry)",
            appBundleNames: ["AgentRegistryManager", "Agent Registry Manager"],
            critical: false
        ),
    ]

    /// SSOT 카탈로그 JSON (agents: `app-fleet-doctor managers list --json`).
    public static func exportJSON(pretty: Bool = true) throws -> Data {
        struct Envelope: Encodable {
            let ssot: String
            let note: String
            let count: Int
            let apps: [ManagementAppSpec]
        }
        let enc = JSONEncoder()
        if pretty { enc.outputFormatting = [.prettyPrinted, .sortedKeys] }
        return try enc.encode(
            Envelope(
                ssot: "DoctorKit.ManagementAppCatalog.builtIn",
                note: "관리 도구 ownership 정본. 관측=app-fleet-doctor managers · 수리는 각 소유 CLI.",
                count: builtIn.count,
                apps: builtIn
            )
        )
    }
}
