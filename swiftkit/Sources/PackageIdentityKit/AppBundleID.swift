// swift-tools-version: 6.1
import Foundation

/// 470개 앱의 번들 ID 정본(SSOT) 타입 안전 상수 및 매핑 표.
public struct AppBundleID: RawRepresentable, ExpressibleByStringLiteral, Hashable, Equatable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public var description: String { rawValue }

    public static let defaultPrefix = "net.ranode."

    /// 알려진 앱 슬러그 -> 번들 ID 매핑
    public static let slugToBundleID: [String: String] = [
        "2d-game-assets-create": "net.ranode.game-assets-studio",
        "3d-model-fbx-modify": "net.ranode.3d-model-fbx-modify",
        "3d-model-fbx-modify-swift": "net.ranode.3d-model-fbx-modify",
        "agent-app-manual-factory": "net.ranode.agent-app-manual-factory",
        "agent-app-manual-factory-swift": "net.ranode.agent-app-manual-factory",
        "agent-app-probe-doctor": "net.ranode.agent-app-probe-doctor",
        "agent-app-probe-doctor-swift": "net.ranode.agent-app-probe-doctor",
        "agent-app-registry": "net.ranode.agent-app-registry",
        "agent-app-registry-swift": "net.ranode.agent-app-registry",
        "agent-batch-codemod": "net.ranode.agent-batch-codemod",
        "agent-batch-codemod-swift": "net.ranode.agent-batch-codemod",
        "agent-board": "net.ranode.agent-board",
        "agent-board-ios": "net.ranode.agent-board",
        "agent-browser": "net.ranode.agentbrowser",
        "agent-browser-login-manager": "net.ranode.agent-browser-login-manager",
        "agent-browser-login-manager-swift": "net.ranode.agent-browser-login-manager",
        "agent-browser-recipe": "net.ranode.agent-browser-recipe",
        "agent-browser-recipe-swift": "net.ranode.agent-browser-recipe",
        "agent-browser-swift": "net.ranode.agentbrowser",
        "agent-capture": "net.ranode.agent-capture",
        "agent-capture-swift": "net.ranode.agent-capture",
        "agent-chat": "net.ranode.agent-chat",
        "agent-chat-swift": "net.ranode.agent-chat",
        "agent-chromium-engine": "net.ranode.agent-chromium-engine",
        "agent-chromium-engine-swift": "net.ranode.agent-chromium-engine",
        "agent-cli-manager": "net.ranode.agent-cli-manager",
        "agent-cli-manager-swift": "net.ranode.agent-cli-manager",
        "agent-cli-scaffold": "net.ranode.agent-cli-scaffold",
        "agent-cli-scaffold-swift": "net.ranode.agent-cli-scaffold",
        "agent-code-clone-detector": "net.ranode.agent-code-clone-detector",
        "agent-code-clone-detector-swift": "net.ranode.agent-code-clone-detector",
        "agent-code-review": "net.ranode.agent-code-review",
        "agent-code-review-swift": "net.ranode.agent-code-review",
        "agent-colony-observatory": "net.ranode.agent-colony-observatory",
        "agent-colony-observatory-swift": "net.ranode.agent-colony-observatory",
        "agent-company": "net.ranode.agent-company",
        "agent-company-swift": "net.ranode.agent-company",
        "agent-context-hub": "net.ranode.agent-context-hub",
        "agent-context-hub-swift": "net.ranode.agent-context-hub",
        "agent-contract-harness": "net.ranode.AgentContractHarness",
        "agent-contract-harness-swift": "net.ranode.AgentContractHarness",
        "agent-control-plane": "net.ranode.agentcontrolplane",
        "agent-control-plane-swift": "net.ranode.agentcontrolplane",
        "agent-deck": "net.ranode.agentdeck",
        "agent-deck-console": "net.ranode.agent-deck-console",
        "agent-deck-console-swift": "net.ranode.agent-deck-console",
        "agent-deck-swift": "net.ranode.agentdeck",
        "agent-doc-code-drift": "net.ranode.agent-doc-code-drift",
        "agent-doc-code-drift-swift": "net.ranode.agent-doc-code-drift",
        "agent-document-usage": "net.ranode.agent-document-usage",
        "agent-document-usage-swift": "net.ranode.agent-document-usage",
        "agent-e2e-runner": "net.ranode.agent-e2e-runner",
        "agent-e2e-runner-swift": "net.ranode.agent-e2e-runner",
        "agent-employee-roster": "net.ranode.agent-employee-roster",
        "agent-employee-roster-swift": "net.ranode.agent-employee-roster",
        "agent-feature-coordinator": "net.ranode.agent-feature-coordinator",
        "agent-feature-coordinator-swift": "net.ranode.agent-feature-coordinator",
        "agent-fleet-daily-report": "net.ranode.agent-fleet-daily-report",
        "agent-fleet-daily-report-swift": "net.ranode.agent-fleet-daily-report",
        "agent-fleet-map": "net.ranode.agent-fleet-map",
        "agent-fleet-map-swift": "net.ranode.agent-fleet-map",
        "agent-fleet-query": "net.ranode.agent-fleet-query",
        "agent-fleet-query-swift": "net.ranode.agent-fleet-query",
        "agent-game-godot-ops": "net.ranode.agent-game-godot-ops",
        "agent-game-godot-ops-swift": "net.ranode.agent-game-godot-ops",
        "agent-guardrail-manager": "net.ranode.agent-guardrail-manager",
        "agent-guardrail-manager-swift": "net.ranode.agent-guardrail-manager",
        "agent-handoff": "net.ranode.agent-handoff",
        "agent-handoff-swift": "net.ranode.agent-handoff",
        "agent-hooks-status": "net.ranode.agent-hooks-status",
        "agent-hooks-status-swift": "net.ranode.agent-hooks-status",
        "agent-host-config-checker": "net.ranode.agent-host-config-checker",
        "agent-host-config-checker-swift": "net.ranode.agent-host-config-checker",
        "agent-host-doctor": "net.ranode.agent-host-doctor",
        "agent-host-doctor-swift": "net.ranode.agent-host-doctor",
        "agent-identity-audit": "net.ranode.agent-identity-audit",
        "agent-identity-audit-swift": "net.ranode.agent-identity-audit",
        "agent-infra-coordinator": "net.ranode.agent-infra-coordinator",
        "agent-infra-coordinator-swift": "net.ranode.agent-infra-coordinator",
        "agent-invocation-refiner": "net.ranode.agent-invocation-refiner",
        "agent-invocation-refiner-swift": "net.ranode.agent-invocation-refiner",
        "agent-invocation-review-pipeline": "ai.gujo.agent-invocation-review-pipeline",
        "agent-invocation-review-pipeline-swift": "ai.gujo.agent-invocation-review-pipeline",
        "agent-lint-autofix": "net.ranode.agent-lint-autofix",
        "agent-lint-autofix-swift": "net.ranode.agent-lint-autofix",
        "agent-lint-batch-runner": "net.ranode.agent-lint-batch-runner",
        "agent-lint-batch-runner-swift": "net.ranode.agent-lint-batch-runner",
        "agent-lint-catalog": "net.ranode.agent-lint-catalog",
        "agent-lint-catalog-swift": "net.ranode.agent-lint-catalog",
        "agent-login-pipeline-manager": "net.ranode.agent-login-pipeline-manager",
        "agent-login-pipeline-manager-swift": "net.ranode.agent-login-pipeline-manager",
        "agent-md-ssot-manager": "net.ranode.agent-md-ssot-manager",
        "agent-md-ssot-manager-swift": "net.ranode.agent-md-ssot-manager",
        "agent-memory-manager": "net.ranode.agent-memory-manager",
        "agent-memory-manager-swift": "net.ranode.agent-memory-manager",
        "agent-model-registry": "net.ranode.agent-model-registry",
        "agent-model-registry-swift": "net.ranode.agent-model-registry",
        "agent-monorepo-studio": "net.ranode.agent-monorepo-studio",
        "agent-monorepo-studio-swift": "net.ranode.agent-monorepo-studio",
        "agent-ops-monitor": "net.ranode.agent-ops-monitor",
        "agent-ops-monitor-swift": "net.ranode.agent-ops-monitor",
        "agent-orchestration-deck": "net.ranode.agent-orchestration-deck",
        "agent-orchestration-deck-swift": "net.ranode.agent-orchestration-deck",
        "agent-plugin-catalog": "net.ranode.agent-plugin-catalog",
        "agent-plugin-catalog-swift": "net.ranode.agent-plugin-catalog",
        "agent-profile-monitor": "net.ranode.agent-profile-monitor",
        "agent-profile-monitor-swift": "net.ranode.agent-profile-monitor",
        "agent-project-board": "net.ranode.agent-project-board",
        "agent-project-board-swift": "net.ranode.agent-project-board",
        "agent-proxy-broker": "net.ranode.agent-proxy-broker",
        "agent-proxy-broker-swift": "net.ranode.agent-proxy-broker",
        "agent-quality-coordinator": "net.ranode.agent-quality-coordinator",
        "agent-quality-coordinator-swift": "net.ranode.agent-quality-coordinator",
        "agent-queue-doctor": "net.ranode.agent-queue-doctor",
        "agent-queue-doctor-swift": "net.ranode.agent-queue-doctor",
        "agent-reach-repair": "net.ranode.agent-reach-repair",
        "agent-reach-repair-swift": "net.ranode.agent-reach-repair",
        "agent-reach-watch": "net.ranode.agent-reach-watch",
        "agent-reach-watch-swift": "net.ranode.agent-reach-watch",
        "agent-registry-manager": "net.ranode.agent-registry-manager",
        "agent-registry-manager-swift": "net.ranode.agent-registry-manager",
        "agent-remote-terminal": "net.ranode.agent-remote-terminal",
        "agent-remote-terminal-ios": "net.ranode.agent-remote-terminal",
        "agent-remote-terminal-swift": "net.ranode.agent-remote-terminal",
        "agent-request": "net.ranode.agent-request",
        "agent-request-ledger": "net.ranode.agent-request-ledger",
        "agent-request-ledger-swift": "net.ranode.agent-request-ledger",
        "agent-request-swift": "net.ranode.agent-request",
        "agent-review-reporter": "net.ranode.agent-review-reporter",
        "agent-review-reporter-swift": "net.ranode.agent-review-reporter",
        "agent-room-monitor": "net.ranode.agent-room-monitor",
        "agent-room-monitor-swift": "net.ranode.agent-room-monitor",
        "agent-room-terminal": "net.ranode.agent-room-terminal",
        "agent-room-terminal-swift": "net.ranode.agent-room-terminal",
        "agent-room-worktree": "net.ranode.agent-room-worktree",
        "agent-room-worktree-swift": "net.ranode.agent-room-worktree",
        "agent-schedule-dispatcher": "net.ranode.agent-schedule-dispatcher",
        "agent-schedule-dispatcher-swift": "net.ranode.agent-schedule-dispatcher",
        "agent-search-engine": "net.ranode.agent-search-engine",
        "agent-search-engine-swift": "net.ranode.agent-search-engine",
        "agent-seat-manager": "net.ranode.agent-seat-manager",
        "agent-seat-manager-swift": "net.ranode.agent-seat-manager",
        "agent-session-archive": "net.ranode.agent-session-archive",
        "agent-session-archive-swift": "net.ranode.agent-session-archive",
        "agent-session-context-ledger": "net.ranode.agent-session-context-ledger",
        "agent-session-context-ledger-swift": "net.ranode.agent-session-context-ledger",
        "agent-session-replay": "net.ranode.agent-session-replay",
        "agent-session-replay-swift": "net.ranode.agent-session-replay",
        "agent-session-task-runner": "net.ranode.agent-session-task-runner",
        "agent-session-task-runner-swift": "net.ranode.agent-session-task-runner",
        "agent-session-timeline": "net.ranode.agent-session-timeline",
        "agent-session-timeline-swift": "net.ranode.agent-session-timeline",
        "agent-skill-build-system": "net.ranode.agent-skill-build-system",
        "agent-skill-build-system-swift": "net.ranode.agent-skill-build-system",
        "agent-skill-catalog": "net.ranode.agent-skill-catalog",
        "agent-skill-catalog-swift": "net.ranode.agent-skill-catalog",
        "agent-skills": "net.ranode.agent-skills",
        "agent-skills-swift": "net.ranode.agent-skills",
        "agent-ssot": "net.ranode.agent-ssot",
        "agent-ssot-swift": "net.ranode.agent-ssot",
        "agent-surface-reach": "net.ranode.agent-surface-reach",
        "agent-surface-reach-swift": "net.ranode.agent-surface-reach",
        "agent-tenant-isolation-manager": "net.ranode.agent-tenant-isolation-manager",
        "agent-tenant-isolation-manager-swift": "net.ranode.agent-tenant-isolation-manager",
        "agent-ui-driver": "net.ranode.agent-ui-driver",
        "agent-ui-driver-swift": "net.ranode.agent-ui-driver",
        "agent-ui-monitor": "net.ranode.agent-ui-monitor",
        "agent-ui-monitor-swift": "net.ranode.agent-ui-monitor",
        "agent-vault": "net.ranode.agentvault",
        "agent-vault-swift": "net.ranode.agentvault",
        "agent-wiki-global": "net.ranode.agent-wiki-global",
        "agent-wiki-global-swift": "net.ranode.agent-wiki-global",
        "agent-wiki-graph": "net.ranode.agent-wiki-graph",
        "agent-wiki-graph-reaper": "net.ranode.agent-wiki-graph-reaper",
        "agent-wiki-graph-reaper-swift": "net.ranode.agent-wiki-graph-reaper",
        "agent-wiki-graph-studio": "net.ranode.agent-wiki-graph-studio",
        "agent-wiki-graph-studio-swift": "net.ranode.agent-wiki-graph-studio",
        "agent-wiki-graph-swift": "net.ranode.agent-wiki-graph",
        "agent-wiki-local": "net.ranode.agent-wiki-local",
        "agent-wiki-local-swift": "net.ranode.agent-wiki-local",
        "agent-wiki-reader": "net.ranode.agent-wiki-reader",
        "agent-wiki-reader-swift": "net.ranode.agent-wiki-reader",
        "agent-wiki-studio": "net.ranode.agent-wiki-studio",
        "agent-wiki-studio-swift": "net.ranode.agent-wiki-studio",
        "agent-window-control": "net.ranode.agent-window-control",
        "agent-window-control-swift": "net.ranode.agent-window-control",
        "agent-work-monitor": "net.ranode.agent-work-monitor",
        "agent-work-monitor-swift": "net.ranode.agent-work-monitor",
        "agent-work-report": "net.ranode.agent-work-report",
        "agent-work-report-swift": "net.ranode.agent-work-report",
        "agent-work-todo": "net.ranode.agent-work-todo",
        "agent-worker-orchestrator": "net.ranode.agent-worker-orchestrator",
        "agent-worker-orchestrator-swift": "net.ranode.agent-worker-orchestrator",
        "agent-worktree-control-terminal": "net.ranode.agent-worktree-control-terminal",
        "agent-worktree-control-terminal-swift": "net.ranode.agent-worktree-control-terminal",
        "agent-worktree-doctor": "net.ranode.agent-worktree-doctor",
        "agent-worktree-doctor-swift": "net.ranode.agent-worktree-doctor",
        "ai-agent-configuration-manager": "net.ranode.ai-agent-configuration-manager",
        "ai-agent-configuration-manager-swift": "net.ranode.ai-agent-configuration-manager",
        "ai-cli-account-manager": "net.ranode.ai-cli-account-manager",
        "ai-cli-account-manager-swift": "net.ranode.ai-cli-account-manager",
        "ai-cli-launcher": "net.ranode.ai-cli-launcher",
        "ai-cli-launcher-swift": "net.ranode.ai-cli-launcher",
        "ai-cli-proxy-broker": "net.ranode.ai-cli-proxy-broker",
        "ai-cli-proxy-broker-swift": "net.ranode.ai-cli-proxy-broker",
        "ai-cli-router": "net.ranode.ai-cli-router",
        "ai-cli-router-swift": "net.ranode.ai-cli-router",
        "android-adb-manager": "net.ranode.android-adb-manager",
        "android-adb-manager-swift": "net.ranode.android-adb-manager",
        "android-app-store": "net.ranode.androidappstore",
        "android-app-store-swift": "net.ranode.androidappstore",
        "android-settings-manual": "net.ranode.android-settings-manual",
        "android-settings-manual-swift": "net.ranode.android-settings-manual",
        "android-transfer": "net.ranode.androidtransfer",
        "android-transfer-swift": "net.ranode.androidtransfer",
        "api-qa-gujo-api": "net.ranode.api-qa-gujo-api",
        "api-qa-gujo-api-swift": "net.ranode.api-qa-gujo-api",
        "app-build-manager": "net.ranode.appbuildmanager",
        "app-build-manager-swift": "net.ranode.appbuildmanager",
        "app-changelog-manager": "net.ranode.app-changelog-manager",
        "app-changelog-manager-swift": "net.ranode.app-changelog-manager",
        "app-debug-console": "net.ranode.appdebugconsole",
        "app-debug-console-swift": "net.ranode.appdebugconsole",
        "app-distribution-manager": "ai.gujo.app-distribution-manager",
        "app-distribution-manager-swift": "ai.gujo.app-distribution-manager",
        "app-fleet-browser": "net.ranode.app-fleet-browser",
        "app-fleet-browser-swift": "net.ranode.app-fleet-browser",
        "app-fleet-city": "net.ranode.app-fleet-city",
        "app-fleet-city-swift": "net.ranode.app-fleet-city",
        "app-fleet-doctor": "net.ranode.app-fleet-doctor",
        "app-fleet-doctor-swift": "net.ranode.app-fleet-doctor",
        "app-fleet-quality-auditor": "net.ranode.app-fleet-quality-auditor",
        "app-fleet-quality-auditor-swift": "net.ranode.app-fleet-quality-auditor",
        "app-fleet-security": "net.ranode.app-fleet-security",
        "app-fleet-security-swift": "net.ranode.app-fleet-security",
        "app-health-guard": "net.ranode.apphealthguard",
        "app-health-guard-swift": "net.ranode.apphealthguard",
        "app-i18n-inspector": "net.ranode.app-i18n-inspector",
        "app-i18n-inspector-swift": "net.ranode.app-i18n-inspector",
        "app-icon-forge": "net.ranode.app-icon-forge",
        "app-icon-forge-swift": "net.ranode.app-icon-forge",
        "app-launch-doctor": "net.ranode.app-launch-doctor",
        "app-launch-doctor-swift": "net.ranode.app-launch-doctor",
        "app-lifecycle-index": "net.ranode.app-lifecycle-index",
        "app-lifecycle-index-swift": "net.ranode.app-lifecycle-index",
        "app-lifecycle-pipeline-manager": "net.ranode.app-lifecycle-pipeline-manager",
        "app-lifecycle-pipeline-manager-swift": "net.ranode.app-lifecycle-pipeline-manager",
        "app-marketability-studio": "net.ranode.app-marketability-studio",
        "app-notary-manager": "net.ranode.app-notary-manager",
        "app-notary-manager-swift": "net.ranode.app-notary-manager",
        "app-relaunch-watch": "net.ranode.app-relaunch-watch",
        "app-relaunch-watch-swift": "net.ranode.app-relaunch-watch",
        "app-release-propagation": "net.ranode.app-release-propagation",
        "app-release-propagation-swift": "net.ranode.app-release-propagation",
        "app-repair-ledger": "net.ranode.app-repair-ledger",
        "app-repair-ledger-swift": "net.ranode.app-repair-ledger",
        "app-sales-manager": "net.ranode.app-sales-manager",
        "app-sales-manager-swift": "net.ranode.app-sales-manager",
        "app-saves": "net.ranode.app-saves",
        "app-saves-swift": "net.ranode.app-saves",
        "app-search-root-locator": "net.ranode.agent-apps-bar",
        "app-search-root-locator-swift": "net.ranode.agent-apps-bar",
        "app-ship-manager": "net.ranode.app-ship-manager",
        "app-ship-manager-swift": "net.ranode.app-ship-manager",
        "app-signature-integrity-checker": "net.ranode.app-signature-integrity-checker",
        "app-signature-integrity-checker-swift": "net.ranode.app-signature-integrity-checker",
        "app-store-asset-forge": "net.ranode.app-store-asset-forge",
        "app-usability-scorer": "net.ranode.app-usability-scorer",
        "app-usability-scorer-swift": "net.ranode.app-usability-scorer",
        "apple-developer-identity": "net.ranode.appledeveloperidentity",
        "apple-developer-identity-swift": "net.ranode.appledeveloperidentity",
        "awo-k8s-bridge": "net.ranode.awo-k8s-bridge",
        "awo-k8s-bridge-swift": "net.ranode.awo-k8s-bridge",
        "background-job-console": "net.ranode.backgroundjobconsole",
        "background-job-console-swift": "net.ranode.backgroundjobconsole",
        "backup-duplicate-manager": "net.ranode.backup-duplicate-manager",
        "backup-duplicate-manager-swift": "net.ranode.backup-duplicate-manager",
        "backup-to-nas": "net.ranode.backuptonas",
        "backup-to-nas-swift": "net.ranode.backuptonas",
        "battery-guard": "net.ranode.battery-guard",
        "battery-guard-swift": "net.ranode.battery-guard",
        "block-editor": "net.ranode.block-editor",
        "block-editor-swift": "net.ranode.block-editor",
        "brain-life": "net.ranode.brain-life",
        "brain-life-swift": "net.ranode.brain-life",
        "browser-mcp-dashboard": "net.ranode.browsermcpdashboard",
        "browser-mcp-dashboard-swift": "net.ranode.browsermcpdashboard",
        "browser-profile-manager": "net.ranode.browser-profile-manager",
        "browser-profile-manager-swift": "net.ranode.browser-profile-manager",
        "browser-window-locator": "net.ranode.browser-window-locator",
        "browser-window-locator-swift": "net.ranode.browser-window-locator",
        "build-queue-manager": "net.ranode.build-queue-manager",
        "build-queue-manager-swift": "net.ranode.build-queue-manager",
        "build-run-monitor": "net.ranode.build-run-monitor",
        "build-run-monitor-swift": "net.ranode.build-run-monitor",
        "business-accounting-ledger": "net.ranode.business-accounting-ledger",
        "business-accounting-ledger-swift": "net.ranode.business-accounting-ledger",
        "business-api": "net.ranode.business-api",
        "business-api-swift": "net.ranode.business-api",
        "business-contacts": "net.ranode.business-contacts",
        "business-contacts-ios": "net.ranode.business-contacts",
        "business-contacts-swift": "net.ranode.business-contacts",
        "business-documents": "net.ranode.business-documents",
        "business-documents-ios": "net.ranode.business-documents",
        "business-documents-swift": "net.ranode.business-documents",
        "business-entity": "net.ranode.business-entity",
        "business-entity-ios": "net.ranode.business-entity",
        "business-ledger": "net.ranode.business-ledger",
        "business-ledger-swift": "net.ranode.business-ledger",
        "business-loan-manager": "net.ranode.business-loan-manager",
        "business-loan-manager-swift": "net.ranode.business-loan-manager",
        "business-people": "net.ranode.business-people",
        "business-people-swift": "net.ranode.business-people",
        "business-projects": "net.ranode.business-projects",
        "business-projects-swift": "net.ranode.business-projects",
        "business-quote-manager": "net.ranode.business-quote-manager",
        "business-quote-manager-swift": "net.ranode.business-quote-manager",
        "business-request-intake": "net.ranode.business-request-intake",
        "business-request-intake-swift": "net.ranode.business-request-intake",
        "business-schedule": "net.ranode.business-schedule",
        "business-schedule-swift": "net.ranode.business-schedule",
        "business-service-catalog": "net.ranode.business-service-catalog",
        "business-service-catalog-swift": "net.ranode.business-service-catalog",
        "business-tax-evidence-ledger": "net.ranode.business-tax-evidence-ledger",
        "business-tax-evidence-ledger-swift": "net.ranode.business-tax-evidence-ledger",
        "business-tax-filing-manager": "net.ranode.business-tax-filing-manager",
        "business-tax-filing-manager-swift": "net.ranode.business-tax-filing-manager",
        "business-tax-records": "net.ranode.business-tax-records",
        "business-tax-records-swift": "net.ranode.business-tax-records",
        "cardbackup": "net.ranode.cardbackup",
        "cardbackup-swift": "net.ranode.cardbackup",
        "cardnews-gen": "net.ranode.cardnewsgen",
        "cardnews-gen-swift": "net.ranode.cardnewsgen",
        "cdn-storage-manager": "net.ranode.cdn-storage-manager",
        "cdn-storage-manager-swift": "net.ranode.cdn-storage-manager",
        "certificate-manager": "net.ranode.certificate-manager",
        "certificate-manager-swift": "net.ranode.certificate-manager",
        "chromium-runtime-manager": "net.ranode.chromium-runtime-manager",
        "chromium-runtime-manager-swift": "net.ranode.chromium-runtime-manager",
        "clamshell-mode": "net.ranode.clamshell-mode",
        "clamshell-mode-swift": "net.ranode.clamshell-mode",
        "cli-catalog": "net.ranode.clicatalog",
        "cli-catalog-swift": "net.ranode.clicatalog",
        "clipboard-cloudkit-sync-poc": "net.ranode.clipboard-sync-poc",
        "clipboard-history": "net.ranode.clipboardhistoryswift",
        "clipboard-history-swift": "net.ranode.clipboardhistoryswift",
        "clipboard-ios-capture-poc": "net.ranode.clipboard-sync-poc",
        "clipboard-relay": "net.ranode.clipboard-relay",
        "clipboard-relay-ios": "net.ranode.clipboard-relay",
        "cloudflare-deploy-manager": "net.ranode.cloudflare-deploy-manager",
        "cloudflare-deploy-manager-swift": "net.ranode.cloudflare-deploy-manager",
        "code-sign-helper": "net.ranode.codesignhelper",
        "code-sign-helper-swift": "net.ranode.codesignhelper",
        "codebase-porter": "net.ranode.codebase-porter",
        "codebase-porter-swift": "net.ranode.codebase-porter",
        "comfyui-studio": "net.ranode.comfyui-studio",
        "comfyui-studio-swift": "net.ranode.comfyui-studio",
        "container-browser-emulator": "net.ranode.containerbrowseremulator",
        "container-browser-emulator-swift": "net.ranode.containerbrowseremulator",
        "container-manager": "net.ranode.container-manager",
        "container-manager-swift": "net.ranode.container-manager",
        "context-characters": "net.ranode.context-characters",
        "context-characters-swift": "net.ranode.context-characters",
        "cpu-usage-monitor": "net.ranode.cpuusagemonitor",
        "cpu-usage-monitor-swift": "net.ranode.cpuusagemonitor",
        "creative-source-bridge": "net.ranode.creative-source-bridge",
        "creative-source-bridge-swift": "net.ranode.creative-source-bridge",
        "credential-manager": "net.ranode.credential-manager",
        "credential-manager-swift": "net.ranode.credential-manager",
        "customer-feedback-studio": "net.ranode.customer-feedback-studio",
        "customer-feedback-studio-swift": "net.ranode.customer-feedback-studio",
        "dal-asof-derive": "net.ranode.dal-asof-derive",
        "dal-asof-derive-swift": "net.ranode.dal-asof-derive",
        "dal-chem-ledger": "net.ranode.dal-chem-ledger",
        "dal-chem-ledger-swift": "net.ranode.dal-chem-ledger",
        "dal-chem-system": "net.ranode.dal-chem-system",
        "dal-chem-system-swift": "net.ranode.dal-chem-system",
        "dal-conception": "net.ranode.dal-conception",
        "dal-conception-swift": "net.ranode.dal-conception",
        "dal-cortex-scribe": "net.ranode.dal-cortex-scribe",
        "dal-cortex-scribe-swift": "net.ranode.dal-cortex-scribe",
        "dal-dream-consolidate": "net.ranode.dal-dream-consolidate",
        "dal-dream-consolidate-swift": "net.ranode.dal-dream-consolidate",
        "dal-energy-organ": "net.ranode.dal-energy-organ",
        "dal-energy-organ-swift": "net.ranode.dal-energy-organ",
        "dal-ganglia-select": "net.ranode.dal-ganglia-select",
        "dal-ganglia-select-swift": "net.ranode.dal-ganglia-select",
        "dal-hippocampus-recall": "net.ranode.dal-hippocampus-recall",
        "dal-hippocampus-recall-swift": "net.ranode.dal-hippocampus-recall",
        "dal-persona": "net.ranode.dal-persona",
        "dal-persona-swift": "net.ranode.dal-persona",
        "dal-space-coords": "net.ranode.dal-space-coords",
        "dal-space-coords-swift": "net.ranode.dal-space-coords",
        "databaseviewer": "net.ranode.databaseviewer",
        "databaseviewer-swift": "net.ranode.databaseviewer",
        "design-component-library": "net.ranode.design-component-library",
        "design-component-library-swift": "net.ranode.design-component-library",
        "design-system-studio": "net.ranode.designsystemstudio",
        "design-system-studio-swift": "net.ranode.designsystemstudio",
        "detailpage-stages": "net.ranode.detailpage-stages",
        "dev-clean": "net.ranode.devclean",
        "dev-clean-swift": "net.ranode.devclean",
        "device-deck": "net.ranode.device-deck",
        "device-deck-swift": "net.ranode.device-deck",
        "discord-channel-reader": "net.ranode.discord-channel-reader",
        "discord-channel-reader-swift": "net.ranode.discord-channel-reader",
        "disk-space-analyzer": "net.ranode.disk-space-analyzer",
        "disk-space-analyzer-swift": "net.ranode.disk-space-analyzer",
        "disk-usage-analyzer": "net.ranode.disk-usage-analyzer",
        "disk-usage-analyzer-swift": "net.ranode.disk-usage-analyzer",
        "dns-guard": "net.ranode.dns-guard",
        "dns-guard-swift": "net.ranode.dns-guard",
        "dns-switcher": "net.ranode.dnsswitcher",
        "dns-switcher-swift": "net.ranode.dnsswitcher",
        "dns-zone-manager": "net.ranode.dnszonemanager",
        "dns-zone-manager-swift": "net.ranode.dnszonemanager",
        "domain-registry": "net.ranode.domain-registry",
        "domain-registry-swift": "net.ranode.domain-registry",
        "dub-stages": "net.ranode.dub-stages",
        "emulator-vnc-session-controller": "net.ranode.emulator-vnc-session-controller",
        "emulator-vnc-session-controller-swift": "net.ranode.emulator-vnc-session-controller",
        "env-vault": "net.ranode.envvault",
        "env-vault-swift": "net.ranode.envvault",
        "excalidraw": "net.ranode.excalidraw",
        "excalidraw-ios": "net.ranode.excalidraw-ipad",
        "excalidraw-swift": "net.ranode.excalidraw",
        "feature-backlog-studio": "net.ranode.feature-backlog-studio",
        "feature-backlog-studio-swift": "net.ranode.feature-backlog-studio",
        "fee-calculation-records": "net.ranode.fee-calculation-records",
        "fee-calculation-records-swift": "net.ranode.fee-calculation-records",
        "file-arrival-watcher": "net.ranode.file-arrival-watcher",
        "file-arrival-watcher-swift": "net.ranode.file-arrival-watcher",
        "film-project-catalog": "net.ranode.film-project-catalog",
        "film-project-catalog-swift": "net.ranode.film-project-catalog",
        "fleet-app-catalog": "net.ranode.fleetappcatalog",
        "fleet-app-catalog-swift": "net.ranode.fleetappcatalog",
        "fleet-dock": "net.ranode.fleet-dock",
        "fleet-dock-swift": "net.ranode.fleet-dock",
        "flow-stages": "net.ranode.flow-stages",
        "flowlog": "net.ranode.flowlog",
        "flowlog-swift": "net.ranode.flowlog",
        "git-repository-archive-manager": "net.ranode.git-repository-archive-manager",
        "git-repository-archive-manager-swift": "net.ranode.git-repository-archive-manager",
        "github-status-ui": "net.ranode.github-status-ui",
        "github-status-ui-swift": "net.ranode.github-status-ui",
        "gitlab-admin": "net.ranode.gitlab-admin",
        "gitlab-admin-swift": "net.ranode.gitlab-admin",
        "gitlab-board": "net.ranode.gitlab-board",
        "gitlab-board-ios": "net.ranode.gitlab-board",
        "gitlab-manager": "net.ranode.gitlab-status-ui",
        "gitlab-manager-swift": "net.ranode.gitlab-status-ui",
        "gitlab-project-viewer": "net.ranode.gitlab-project-viewer",
        "gitlab-project-viewer-swift": "net.ranode.gitlab-project-viewer",
        "gitlab-mr-review": "net.ranode.gitlab-mr-review",
        "gitlab-mr-review-swift": "net.ranode.gitlab-mr-review",
        "gitlab-token-monitor": "net.ranode.gitlab-token-monitor",
        "gitlab-token-monitor-swift": "net.ranode.gitlab-token-monitor",
        "government-support-application-tracker": "net.ranode.government-support-application-tracker",
        "government-support-application-tracker-swift": "net.ranode.government-support-application-tracker",
        "government-support-company-profile": "net.ranode.government-support-company-profile",
        "government-support-company-profile-swift": "net.ranode.government-support-company-profile",
        "government-support-hwp-form-filler": "net.ranode.government-support-hwp-form-filler",
        "government-support-hwp-form-filler-swift": "net.ranode.government-support-hwp-form-filler",
        "government-support-idea-brainstorm": "net.ranode.government-support-idea-brainstorm",
        "government-support-idea-brainstorm-swift": "net.ranode.government-support-idea-brainstorm",
        "government-support-program-catalog": "net.ranode.government-support-program-catalog",
        "government-support-program-catalog-swift": "net.ranode.government-support-program-catalog",
        "government-support-program-matcher": "net.ranode.government-support-program-matcher",
        "government-support-program-matcher-swift": "net.ranode.government-support-program-matcher",
        "government-support-source-sites": "net.ranode.government-support-source-sites",
        "government-support-source-sites-swift": "net.ranode.government-support-source-sites",
        "gpu-server-manager": "net.ranode.gpu-server-manager",
        "gpu-server-manager-swift": "net.ranode.gpu-server-manager",
        "gpu-video-studio": "net.ranode.gpu-video-studio",
        "gpu-video-studio-swift": "net.ranode.gpu-video-studio",
        "grafana-fleet-monitor": "net.ranode.grafana-fleet-monitor",
        "grafana-fleet-monitor-swift": "net.ranode.grafana-fleet-monitor",
        "gui-tree-explorer": "net.ranode.gui-tree-explorer",
        "gui-tree-explorer-swift": "net.ranode.gui-tree-explorer",
        "gujo-account-manager": "net.ranode.gujo-account-manager",
        "gujo-account-manager-swift": "net.ranode.gujo-account-manager",
        "gujo-ad-message-sender": "net.ranode.gujo-ad-message-sender",
        "gujo-ad-message-sender-swift": "net.ranode.gujo-ad-message-sender",
        "gujo-asset-studio": "net.ranode.gujo-asset-studio",
        "gujo-asset-studio-swift": "net.ranode.gujo-asset-studio",
        "gujo-catalog-manager": "net.ranode.gujo-catalog-manager",
        "gujo-catalog-manager-swift": "net.ranode.gujo-catalog-manager",
        "gujo-cf-email-manager": "net.ranode.gujo-cf-email-manager",
        "gujo-cf-email-manager-swift": "net.ranode.gujo-cf-email-manager",
        "gujo-cloud-apps": "net.ranode.gujo-cloud-apps",
        "gujo-cloud-apps-swift": "net.ranode.gujo-cloud-apps",
        "gujo-commerce-desk": "net.ranode.gujo-commerce-desk",
        "gujo-commerce-desk-swift": "net.ranode.gujo-commerce-desk",
        "gujo-coupon-manager": "net.ranode.gujo-coupon-manager",
        "gujo-coupon-manager-swift": "net.ranode.gujo-coupon-manager",
        "gujo-customer-manager": "net.ranode.gujo-customer-manager",
        "gujo-customer-manager-swift": "net.ranode.gujo-customer-manager",
        "gujo-design-gallery-manager": "net.ranode.gujo-design-gallery-manager",
        "gujo-design-gallery-manager-swift": "net.ranode.gujo-design-gallery-manager",
        "gujo-download-pipeline-auditor": "net.ranode.gujo-download-pipeline-auditor",
        "gujo-download-pipeline-auditor-swift": "net.ranode.gujo-download-pipeline-auditor",
        "gujo-laravel-operations": "net.ranode.gujo-laravel-operations",
        "gujo-laravel-operations-swift": "net.ranode.gujo-laravel-operations",
        "gujo-laravel-scheduler": "net.ranode.gujo-laravel-scheduler",
        "gujo-laravel-scheduler-swift": "net.ranode.gujo-laravel-scheduler",
        "gujo-managed-adoption-manager": "net.ranode.gujo-managed-adoption-manager",
        "gujo-managed-adoption-manager-swift": "net.ranode.gujo-managed-adoption-manager",
        "gujo-newsletter-sender": "net.ranode.gujo-newsletter-sender",
        "gujo-newsletter-sender-swift": "net.ranode.gujo-newsletter-sender",
        "gujo-payment-tester": "net.ranode.gujo-payment-tester",
        "gujo-payment-tester-swift": "net.ranode.gujo-payment-tester",
        "gujo-product-gate": "net.ranode.gujo-product-gate",
        "gujo-product-gate-swift": "net.ranode.gujo-product-gate",
        "gujo-product-studio": "net.ranode.gujo-product-proof-studio",
        "gujo-product-studio-swift": "net.ranode.gujo-product-proof-studio",
        "gujo-service-mailer": "net.ranode.gujo-service-mailer",
        "gujo-service-mailer-swift": "net.ranode.gujo-service-mailer",
        "gujo-service-qa": "net.ranode.gujo-service-qa",
        "gujo-service-qa-swift": "net.ranode.gujo-service-qa",
        "gujo-skill-publisher": "net.ranode.gujo-skill-publisher",
        "gujo-skill-publisher-swift": "net.ranode.gujo-skill-publisher",
        "gujo-skill-store": "net.ranode.gujo-skill-store",
        "gujo-skill-store-swift": "net.ranode.gujo-skill-store",
        "gujo-store-listing-manager": "net.ranode.gujo-store-listing-manager",
        "gujo-store-listing-manager-swift": "net.ranode.gujo-store-listing-manager",
        "gujo-store-ops": "net.ranode.gujo-store-ops",
        "gujo-store-ops-ios": "net.ranode.gujo-store-ops-ios",
        "gujo-store-ops-swift": "net.ranode.gujo-store-ops",
        "gujo-support-desk": "net.ranode.gujo-support-desk",
        "gujo-support-desk-swift": "net.ranode.gujo-support-desk",
        "helm-release-manager": "net.ranode.helmreleasemanager",
        "helm-release-manager-swift": "net.ranode.helmreleasemanager",
        "hermes": "net.ranode.hermes",
        "hermes-swift": "net.ranode.hermes",
        "home-control-dashboard": "net.ranode.home-control-dashboard",
        "home-control-dashboard-swift": "net.ranode.home-control-dashboard",
        "host-settings-ledger": "net.ranode.host-settings-ledger",
        "host-settings-ledger-swift": "net.ranode.host-settings-ledger",
        "http-api-client": "net.ranode.http-api-client",
        "http-api-client-swift": "net.ranode.http-api-client",
        "human-gate-ops": "net.ranode.human-gate-ops",
        "human-gate-ops-swift": "net.ranode.human-gate-ops",
        "hwpx-viewer": "net.ranode.hwpx-viewer",
        "hwpx-viewer-swift": "net.ranode.hwpx-viewer",
        "icon-preview-composer": "net.ranode.icon-preview-composer.viewer",
        "icon-preview-composer-swift": "net.ranode.icon-preview-composer.viewer",
        "identity-document-registry": "net.ranode.identity-document-registry",
        "identity-document-registry-swift": "net.ranode.identity-document-registry",
        "identity-install-ledger": "net.ranode.agent-identity-install-ledger",
        "identity-install-ledger-swift": "net.ranode.agent-identity-install-ledger",
        "image-generation": "net.ranode.imagegeneration",
        "image-generation-studio": "net.ranode.imagegenerationstudio",
        "image-generation-studio-swift": "net.ranode.imagegenerationstudio",
        "image-generation-swift": "net.ranode.imagegeneration",
        "infisical": "net.ranode.infisical",
        "infisical-certs": "net.ranode.infisicalcerts",
        "infisical-certs-swift": "net.ranode.infisicalcerts",
        "infisical-swift": "net.ranode.infisical",
        "infra-alert-receiver": "net.ranode.infra-alert-receiver",
        "infra-alert-receiver-swift": "net.ranode.infra-alert-receiver",
        "infra-ops-dashboard": "net.ranode.infra-ops-dashboard",
        "infra-ops-dashboard-swift": "net.ranode.infra-ops-dashboard",
        "ipad-clipboard-history": "net.ranode.ipad-clipboard-history",
        "iptime-router": "net.ranode.iptime-router",
        "iptime-router-swift": "net.ranode.iptime-router",
        "joint-certificate-manager": "net.ranode.joint-certificate-manager",
        "joint-certificate-manager-swift": "net.ranode.joint-certificate-manager",
        "json-inspector": "net.ranode.json-inspector",
        "json-inspector-swift": "net.ranode.json-inspector",
        "keep-awake": "net.ranode.keep-awake",
        "keep-awake-swift": "net.ranode.keep-awake",
        "keyboard-coding-typer": "net.ranode.keyboard-coding-typer",
        "keyboard-coding-typer-swift": "net.ranode.keyboard-coding-typer",
        "keyboard-settings-manager": "net.ranode.keyboard-settings-manager",
        "keyboard-typer": "net.ranode.keyboardtyper",
        "keyboard-typer-swift": "net.ranode.keyboardtyper",
        "knowledge-base-wiki": "net.ranode.memo-citation-ledger",
        "knowledge-base-wiki-swift": "net.ranode.memo-citation-ledger",
        "knowledge-graph-studio": "net.ranode.knowledgegraphstudio",
        "knowledge-graph-studio-swift": "net.ranode.knowledgegraphstudio",
        "kube-status-ui": "net.ranode.kube-status-ui",
        "kube-status-ui-swift": "net.ranode.kube-status-ui",
        "kubernetes-emulator-fleet-controller": "net.ranode.kubernetes-emulator-fleet-controller",
        "kubernetes-emulator-fleet-controller-swift": "net.ranode.kubernetes-emulator-fleet-controller",
        "laravel-architecture-graph": "net.ranode.laravel-architecture-graph",
        "laravel-architecture-graph-swift": "net.ranode.laravel-architecture-graph",
        "laravel-backend-test-graph": "net.ranode.laravel-backend-test-graph",
        "laravel-backend-test-graph-swift": "net.ranode.laravel-backend-test-graph",
        "laravel-browser-e2e-manager": "net.ranode.laravel-browser-e2e-manager",
        "laravel-browser-e2e-manager-swift": "net.ranode.laravel-browser-e2e-manager",
        "laravel-frontend-inspect-graph": "net.ranode.laravel-frontend-inspect-graph",
        "laravel-frontend-inspect-graph-swift": "net.ranode.laravel-frontend-inspect-graph",
        "laravel-frontend-test-graph": "net.ranode.laravel-frontend-test-graph",
        "laravel-frontend-test-graph-swift": "net.ranode.laravel-frontend-test-graph",
        "laravel-local-development-setup": "net.ranode.laravel-local-development-setup",
        "laravel-local-development-setup-swift": "net.ranode.laravel-local-development-setup",
        "laravel-ops-monitor": "net.ranode.laravel-ops-monitor",
        "laravel-ops-monitor-swift": "net.ranode.laravel-ops-monitor",
        "lecture-materials": "net.ranode.lecture-materials",
        "lecture-materials-swift": "net.ranode.lecture-materials",
        "lecture-production-studio": "net.ranode.lecture-production-studio",
        "lecture-production-studio-swift": "net.ranode.lecture-production-studio",
        "lecture-students": "net.ranode.lecture-students",
        "lecture-students-swift": "net.ranode.lecture-students",
        "lecture-tools": "net.ranode.lecture-tools",
        "lecture-tools-swift": "net.ranode.lecture-tools",
        "license-entitlement-manager": "net.ranode.license-entitlement-manager",
        "license-entitlement-manager-swift": "net.ranode.license-entitlement-manager",
        "linux-server-operations-manager": "net.ranode.linuxserveroperationsmanager",
        "linux-server-operations-manager-swift": "net.ranode.linuxserveroperationsmanager",
        "live-translate": "net.ranode.livetranslateswift",
        "live-translate-swift": "net.ranode.livetranslateswift",
        "llm-playground": "net.ranode.llm-playground",
        "llm-playground-ios": "net.ranode.llm-playground",
        "llm-route-manager": "net.ranode.llmroutemanager",
        "llm-route-manager-swift": "net.ranode.llmroutemanager",
        "llm-workflow-studio": "net.ranode.llmworkflowstudio",
        "llm-workflow-studio-swift": "net.ranode.llmworkflowstudio",
        "llmwiki-editor": "net.ranode.llmwiki-editor",
        "llmwiki-editor-swift": "net.ranode.llmwiki-editor",
        "local-account-privilege-manager": "net.ranode.local-account-privilege-manager",
        "local-account-privilege-manager-swift": "net.ranode.local-account-privilege-manager",
        "local-secrets": "net.ranode.local-secrets",
        "local-secrets-swift": "net.ranode.local-secrets",
        "local-video-player": "net.ranode.local-video-player",
        "local-video-player-swift": "net.ranode.local-video-player",
        "loop-feedback": "net.ranode.loop-feedback",
        "loop-feedback-swift": "net.ranode.loop-feedback",
        "mac-ai-installer": "net.ranode.macaiinstaller",
        "mac-ai-installer-swift": "net.ranode.macaiinstaller",
        "mac-android-link": "net.ranode.mac-android-link",
        "mac-android-link-swift": "net.ranode.mac-android-link",
        "mac-installer": "net.ranode.macinstaller",
        "mac-installer-swift": "net.ranode.macinstaller",
        "mac-machine-backup-manager": "net.ranode.mac-machine-backup-manager",
        "mac-machine-backup-manager-swift": "net.ranode.mac-machine-backup-manager",
        "mac-performance-monitor": "net.ranode.macperformancemonitor",
        "mac-performance-monitor-swift": "net.ranode.macperformancemonitor",
        "mac-permission-administrator": "net.ranode.mac-permission-administrator",
        "mac-permission-administrator-swift": "net.ranode.mac-permission-administrator",
        "mac-permission-monitor": "net.ranode.mac-permission-monitor",
        "mac-permission-monitor-swift": "net.ranode.mac-permission-monitor",
        "mac-permissions-manager": "net.ranode.macpermissionsmanager",
        "mac-permissions-manager-swift": "net.ranode.macpermissionsmanager",
        "mac-recorder": "net.ranode.macrecorder",
        "mac-recorder-swift": "net.ranode.macrecorder",
        "mac-remote-desktop": "net.ranode.macremotedesktop",
        "mac-remote-desktop-swift": "net.ranode.macremotedesktop",
        "mac-screen-sharing-client": "net.ranode.mac-screen-sharing-client",
        "mac-screen-sharing-client-swift": "net.ranode.mac-screen-sharing-client",
        "mailsmstester": "net.ranode.mailsmstester",
        "mailsmstester-swift": "net.ranode.mailsmstester",
        "mcp-manager": "net.ranode.mcpmanager",
        "mcp-manager-swift": "net.ranode.mcpmanager",
        "md-lineage-viewer": "net.ranode.md-lineage-viewer",
        "md-lineage-viewer-swift": "net.ranode.md-lineage-viewer",
        "meaning-spacetime": "net.ranode.meaning-spacetime",
        "meaning-spacetime-swift": "net.ranode.meaning-spacetime",
        "media-prompt-ledger": "net.ranode.media-prompt-ledger",
        "media-prompt-ledger-swift": "net.ranode.media-prompt-ledger",
        "mem0-controller": "net.ranode.mem0-controller",
        "mem0-controller-swift": "net.ranode.mem0-controller",
        "memo-vault": "net.ranode.memo-vault",
        "memo-vault-ios": "net.ranode.memo-vault",
        "memo-vault-swift": "net.ranode.memo-vault",
        "memory-core-cockpit": "net.ranode.memory-core-cockpit",
        "memory-core-cockpit-swift": "net.ranode.memory-core-cockpit",
        "menu-fold": "net.ranode.menu-fold",
        "menu-fold-swift": "net.ranode.menu-fold",
        "menubar-below-notch": "net.ranode.menubar-below-notch",
        "menubar-below-notch-swift": "net.ranode.menubar-below-notch",
        "mermaid-viewer": "net.ranode.mermaid-viewer",
        "mermaid-viewer-swift": "net.ranode.mermaid-viewer",
        "model-convert": "net.ranode.modelconvert",
        "model-convert-swift": "net.ranode.modelconvert",
        "money-source-government-program-lookup": "net.ranode.money-source-government-program-lookup",
        "money-source-government-program-lookup-swift": "net.ranode.money-source-government-program-lookup",
        "money-source-loan-lookup": "net.ranode.money-source-loan-lookup",
        "money-source-loan-lookup-swift": "net.ranode.money-source-loan-lookup",
        "money-source-subsidy-lookup": "net.ranode.money-source-subsidy-lookup",
        "money-source-subsidy-lookup-swift": "net.ranode.money-source-subsidy-lookup",
        "money-source-tax-benefit-lookup": "net.ranode.money-source-tax-benefit-lookup",
        "money-source-tax-benefit-lookup-swift": "net.ranode.money-source-tax-benefit-lookup",
        "monorepo-git-forge": "net.ranode.monorepo-git-forge",
        "monorepo-git-forge-swift": "net.ranode.monorepo-git-forge",
        "mounter": "net.ranode.mounter",
        "mounter-swift": "net.ranode.mounter",
        "multiformat-image-viewer": "net.ranode.multiformat-image-viewer",
        "multiformat-image-viewer-swift": "net.ranode.multiformat-image-viewer",
        "nas-cutoff-transfer-manager": "net.ranode.nas-cutoff-transfer-manager",
        "nas-cutoff-transfer-manager-swift": "net.ranode.nas-cutoff-transfer-manager",
        "net-share-client": "net.ranode.net-share-client",
        "net-share-client-ios": "kr.internal.netshare.client",
        "net-share-client-swift": "net.ranode.net-share-client",
        "network-debug-console": "net.ranode.networkdebugconsole",
        "network-debug-console-swift": "net.ranode.networkdebugconsole",
        "network-failover-manager": "net.ranode.network-failover-manager",
        "network-failover-manager-swift": "net.ranode.network-failover-manager",
        "network-topology-map": "net.ranode.network-topology-map",
        "network-topology-map-swift": "net.ranode.network-topology-map",
        "neural-phase-inspector": "net.ranode.neural-phase-inspector",
        "neural-phase-inspector-swift": "net.ranode.neural-phase-inspector",
        "oauth-token-vault": "net.ranode.oauthtokenvault",
        "oauth-token-vault-swift": "net.ranode.oauthtokenvault",
        "online-opportunity-radar": "net.ranode.online-opportunity-radar",
        "online-opportunity-radar-swift": "net.ranode.online-opportunity-radar",
        "open-source-app-publisher": "net.ranode.open-source-app-publisher",
        "open-source-app-publisher-swift": "net.ranode.open-source-app-publisher",
        "opencodex-account-manager": "net.ranode.opencodex-account-manager",
        "opencodex-account-manager-swift": "net.ranode.opencodex-account-manager",
        "opencodex-dashboard": "net.ranode.opencodex-dashboard",
        "opencodex-dashboard-swift": "net.ranode.opencodex-dashboard",
        "opportunity-analyzer": "net.ranode.opportunity-analyzer",
        "opportunity-analyzer-swift": "net.ranode.opportunity-analyzer",
        "opportunity-crawler": "net.ranode.opportunity-crawler",
        "opportunity-crawler-swift": "net.ranode.opportunity-crawler",
        "output-archive-manager": "net.ranode.output-archive-manager",
        "output-archive-manager-swift": "net.ranode.output-archive-manager",
        "package-wiki-bridge": "net.ranode.package-wiki-bridge",
        "package-wiki-bridge-swift": "net.ranode.package-wiki-bridge",
        "party-room-release-manager": "net.ranode.party-room-release-manager",
        "party-room-release-manager-swift": "net.ranode.party-room-release-manager",
        "path-cli-health": "net.ranode.path-cli-health",
        "path-cli-health-swift": "net.ranode.path-cli-health",
        "pdf-editor": "net.ranode.pdf-editor",
        "pdf-editor-ios": "net.ranode.pdf-editor-ipad",
        "pdf-editor-swift": "net.ranode.pdf-editor",
        "personal-ledger": "net.ranode.personal-ledger",
        "personal-ledger-swift": "net.ranode.personal-ledger",
        "pg-merchant-ops": "net.ranode.pg-merchant-ops",
        "pg-merchant-ops-swift": "net.ranode.pg-merchant-ops",
        "photo-classification-map": "net.ranode.photo-classification-map",
        "photo-classification-map-swift": "net.ranode.photo-classification-map",
        "photo-face-index": "net.ranode.photo-face-index",
        "photo-face-index-swift": "net.ranode.photo-face-index",
        "photo-origin-ledger": "net.ranode.photo-origin-ledger",
        "photo-origin-ledger-swift": "net.ranode.photo-origin-ledger",
        "photo-participants": "net.ranode.photo-participants",
        "photo-participants-swift": "net.ranode.photo-participants",
        "photo-picks": "net.ranode.photo-picks",
        "photo-picks-swift": "net.ranode.photo-picks",
        "photo-reach-delivery": "net.ranode.photo-reach-delivery",
        "photo-reach-delivery-swift": "net.ranode.photo-reach-delivery",
        "photo-work-status": "net.ranode.photo-work-status",
        "photo-work-status-swift": "net.ranode.photo-work-status",
        "pikvm-console": "net.ranode.pikvm-console",
        "pikvm-console-swift": "net.ranode.pikvm-console",
        "pim-agenda": "net.ranode.pimagenda",
        "pim-agenda-swift": "net.ranode.pimagenda",
        "pim-calendar": "net.ranode.pimcalendar",
        "pim-calendar-ios": "net.ranode.pim-calendar",
        "pim-calendar-swift": "net.ranode.pimcalendar",
        "pim-contacts": "net.ranode.pimcontacts",
        "pim-contacts-swift": "net.ranode.pimcontacts",
        "pim-mail": "net.ranode.pimmail",
        "pim-mail-automation": "net.ranode.pim-mail-automation",
        "pim-mail-automation-swift": "net.ranode.pim-mail-automation",
        "pim-mail-swift": "net.ranode.pimmail",
        "pim-notes": "net.ranode.pimnotes",
        "pim-notes-swift": "net.ranode.pimnotes",
        "pim-person-profile": "net.ranode.pim-person-profile",
        "pim-person-profile-swift": "net.ranode.pim-person-profile",
        "pim-search": "net.ranode.pimsearch",
        "pim-search-swift": "net.ranode.pimsearch",
        "pim-todo": "net.ranode.pimtodo",
        "pim-todo-swift": "net.ranode.pimtodo",
        "pim-workspace": "net.ranode.pim-workspace",
        "pim-workspace-swift": "net.ranode.pim-workspace",
        "pipeline-profiler": "net.ranode.pipelineprofiler",
        "pipeline-profiler-swift": "net.ranode.pipelineprofiler",
        "pipeline-status-ui": "net.ranode.pipeline-status-ui",
        "pipeline-status-ui-swift": "net.ranode.pipeline-status-ui",
        "playbook-installer": "net.ranode.playbookinstaller",
        "playbook-installer-swift": "net.ranode.playbookinstaller",
        "pptx-editor": "net.ranode.pptx-editor",
        "pptx-editor-swift": "net.ranode.pptx-editor",
        "product-competitor-pricing": "net.ranode.product-competitor-pricing",
        "product-competitor-pricing-swift": "net.ranode.product-competitor-pricing",
        "product-definition-workspace": "net.ranode.productdefinitionworkspace",
        "product-definition-workspace-swift": "net.ranode.productdefinitionworkspace",
        "product-evaluation-studio": "net.ranode.productevaluationstudio",
        "product-evaluation-studio-swift": "net.ranode.productevaluationstudio",
        "product-showcase-studio": "net.ranode.product-showcase-studio",
        "product-showcase-studio-swift": "net.ranode.product-showcase-studio",
        "proxmox-monitor": "net.ranode.proxmox-ipad",
        "proxmox-monitor-ios": "net.ranode.proxmox-ipad",
        "proxmox-operations-manager": "net.ranode.proxmoxoperationsmanager",
        "proxmox-operations-manager-swift": "net.ranode.proxmoxoperationsmanager",
        "raster-image-editor": "net.ranode.raster-image-editor",
        "raster-image-editor-swift": "net.ranode.raster-image-editor",
        "raw-library": "net.ranode.raw-library",
        "raw-library-swift": "net.ranode.raw-library",
        "receipt-ocr": "net.ranode.receipt-ocr",
        "receipt-ocr-swift": "net.ranode.receipt-ocr",
        "record-timelabs-mono": "net.ranode.record-timelabs-mono",
        "reference-board": "net.ranode.refboard",
        "reference-board-swift": "net.ranode.refboard",
        "remote-access-mac": "net.ranode.remoteaccessmac",
        "remote-access-mac-swift": "net.ranode.remoteaccessmac",
        "remote-docker-manager": "net.ranode.remote-docker-manager",
        "remote-docker-manager-swift": "net.ranode.remote-docker-manager",
        "remote-mac-bottleneck-analyzer": "net.ranode.remote-mac-bottleneck-analyzer",
        "remote-mac-bottleneck-analyzer-swift": "net.ranode.remote-mac-bottleneck-analyzer",
        "remote-server-terminal-manager": "net.ranode.remote-server-terminal-manager",
        "remote-server-terminal-manager-swift": "net.ranode.remote-server-terminal-manager",
        "repo-ci-overhead-auditor": "net.ranode.repo-ci-overhead-auditor",
        "repo-ci-overhead-auditor-swift": "net.ranode.repo-ci-overhead-auditor",
        "repo-fleet-manager": "net.ranode.repo-fleet-manager",
        "repo-fleet-manager-swift": "net.ranode.repo-fleet-manager",
        "repository-readiness-governor": "net.ranode.repository-readiness-governor",
        "repository-readiness-governor-swift": "net.ranode.repository-readiness-governor",
        "research-inbox": "net.ranode.researchinbox",
        "research-inbox-swift": "net.ranode.researchinbox",
        "rightclick": "net.ranode.rightclick",
        "rightclick-swift": "net.ranode.rightclick",
        "scheduler": "net.ranode.scheduler",
        "scheduler-swift": "net.ranode.scheduler",
        "screen-ocr": "net.ranode.screen-ocr",
        "screen-ocr-swift": "net.ranode.screen-ocr",
        "screenshot": "net.ranode.screenshotswift",
        "screenshot-ios": "net.ranode.screenshot-studio",
        "screenshot-swift": "net.ranode.screenshotswift",
        "screenshotswift": "net.ranode.screenshotswift",
        "search-agent-menubar": "net.ranode.search-agent-menubar",
        "search-agent-menubar-swift": "net.ranode.search-agent-menubar",
        "service-page-capture-index": "net.ranode.service-page-capture-index",
        "service-page-capture-index-swift": "net.ranode.service-page-capture-index",
        "service-terms-manager": "net.ranode.service-terms-manager",
        "service-terms-manager-swift": "net.ranode.service-terms-manager",
        "session-keep-alive": "net.ranode.session-keep-alive",
        "session-keep-alive-swift": "net.ranode.session-keep-alive",
        "sidecar-tablet": "net.ranode.sidecartablet",
        "sidecar-tablet-swift": "net.ranode.sidecartablet",
        "skill-generator": "net.ranode.skill-generator",
        "skill-generator-swift": "net.ranode.skill-generator",
        "social-connect-console": "net.ranode.social-connect-console",
        "social-connect-console-swift": "net.ranode.social-connect-console",
        "social-draft": "net.ranode.socialdraft",
        "social-draft-swift": "net.ranode.socialdraft",
        "sound-source-inspector": "net.ranode.soundsourceinspector",
        "sound-source-inspector-swift": "net.ranode.soundsourceinspector",
        "sparkle-update-studio": "net.ranode.sparkleupdatestudio",
        "sparkle-update-studio-swift": "net.ranode.sparkleupdatestudio",
        "sprite-animator": "net.ranode.sprite-animator",
        "sprite-animator-swift": "net.ranode.sprite-animator",
        "sprite-forge": "net.ranode.sprite-forge",
        "sprite-forge-swift": "net.ranode.sprite-forge",
        "sqlite-query-runner": "net.ranode.sqlite-query-runner",
        "sqlite-query-runner-swift": "net.ranode.sqlite-query-runner",
        "ssh-terminal": "net.ranode.ssh-terminal-ipad",
        "ssh-terminal-ios": "net.ranode.ssh-terminal-ipad",
        "star-map": "net.ranode.starmap",
        "star-map-ios": "net.ranode.starmap-ipad",
        "star-map-swift": "net.ranode.starmap",
        "store-app-batch-upgrader": "net.ranode.store-app-batch-upgrader",
        "store-app-batch-upgrader-swift": "net.ranode.store-app-batch-upgrader",
        "store-inventory-manager": "net.ranode.store-inventory-manager",
        "store-inventory-manager-swift": "net.ranode.store-inventory-manager",
        "subdomain-session": "net.ranode.subdomainsession",
        "subdomain-session-swift": "net.ranode.subdomainsession",
        "subscription-ledger": "net.ranode.subscription-ledger",
        "subscription-ledger-swift": "net.ranode.subscription-ledger",
        "swift-app-devtools-hub": "net.ranode.swift-app-devtools-hub",
        "swift-app-devtools-hub-swift": "net.ranode.swift-app-devtools-hub",
        "swift-app-router": "net.ranode.swiftapprouter",
        "swift-app-router-swift": "net.ranode.swiftapprouter",
        "swift-library-kit-manager": "net.ranode.swiftlibrarykitmanager",
        "swift-library-kit-manager-swift": "net.ranode.swiftlibrarykitmanager",
        "swift-view-dev-selector": "net.ranode.swiftviewdevselector",
        "swift-view-dev-selector-swift": "net.ranode.swiftviewdevselector",
        "swiftkit-migration": "net.ranode.swiftkit-migration",
        "swiftkit-migration-swift": "net.ranode.swiftkit-migration",
        "sync-manager": "net.ranode.sync-manager",
        "sync-manager-swift": "net.ranode.sync-manager",
        "synology-storage-manager": "net.ranode.synology-storage-manager",
        "synology-storage-manager-swift": "net.ranode.synology-storage-manager",
        "system-ports": "net.ranode.systemports",
        "system-ports-swift": "net.ranode.systemports",
        "telemetry-dashboard": "net.ranode.telemetry-dashboard",
        "telemetry-dashboard-swift": "net.ranode.telemetry-dashboard",
        "terraform-infrastructure-control": "net.ranode.terraform-infrastructure-control",
        "terraform-infrastructure-control-swift": "net.ranode.terraform-infrastructure-control",
        "token-usage-menubar": "net.ranode.llm-token-status-manager",
        "token-usage-menubar-swift": "net.ranode.llm-token-status-manager",
        "tracelite": "net.ranode.tracelite",
        "tracelite-swift": "net.ranode.tracelite",
        "trend-deck": "net.ranode.trenddeck",
        "trend-deck-swift": "net.ranode.trenddeck",
        "truenas-storage-manager": "net.ranode.truenas-storage-manager",
        "truenas-storage-manager-swift": "net.ranode.truenas-storage-manager",
        "ui-prototype-harness": "net.ranode.ui-prototype-harness",
        "ui-prototype-harness-swift": "net.ranode.ui-prototype-harness",
        "unused-asset-inspector": "net.ranode.unused-asset-inspector",
        "unused-asset-inspector-swift": "net.ranode.unused-asset-inspector",
        "unused-view-inspector": "net.ranode.unused-view-inspector",
        "unused-view-inspector-swift": "net.ranode.unused-view-inspector",
        "usb-iso-burnner": "net.ranode.usbisoburner",
        "usb-iso-burnner-swift": "net.ranode.usbisoburner",
        "vaultwarden-client": "net.ranode.vaultwarden-client",
        "vaultwarden-client-swift": "net.ranode.vaultwarden-client",
        "vibecode-custom-cli": "net.ranode.vibecodecli",
        "vibecode-custom-cli-swift": "net.ranode.vibecodecli",
        "virtual-buyer-journey-improvement-studio": "net.ranode.virtual-buyer-journey-improvement-studio",
        "virtual-buyer-journey-improvement-studio-swift": "net.ranode.virtual-buyer-journey-improvement-studio",
        "virtual-buyer-journey-sim-core": "net.ranode.virtual-buyer-journey-sim-core",
        "virtual-buyer-journey-simulator-runner": "net.ranode.virtual-buyer-journey-simulator-runner",
        "virtual-buyer-journey-simulator-runner-swift": "net.ranode.virtual-buyer-journey-simulator-runner",
        "virtual-buyer-journey-simulator-studio": "net.ranode.virtual-buyer-journey-simulator-studio",
        "virtual-buyer-journey-simulator-studio-swift": "net.ranode.virtual-buyer-journey-simulator-studio",
        "voice-scribe": "net.ranode.voicescribe",
        "voice-scribe-swift": "net.ranode.voicescribe",
        "volume-controller": "net.ranode.volume-controller",
        "volume-controller-swift": "net.ranode.volume-controller",
        "vpn-wireguard": "net.ranode.wireguard",
        "vpn-wireguard-ios": "net.ranode.wireguard.ios",
        "vpn-wireguard-swift": "net.ranode.wireguard",
        "vscode-extension-runaway-monitor": "net.ranode.vscodeextensionrunawaymonitor",
        "vscode-extension-runaway-monitor-swift": "net.ranode.vscodeextensionrunawaymonitor",
        "walkthrough-recorder": "net.ranode.walkthroughrecorder",
        "walkthrough-recorder-swift": "net.ranode.walkthroughrecorder",
        "win-harbor": "net.ranode.win-harbor",
        "win-harbor-swift": "net.ranode.win-harbor",
        "window-snap": "net.ranode.window-snap",
        "window-snap-swift": "net.ranode.window-snap",
        "wireguard": "net.ranode.wireguard",
        "wordpress-console": "net.ranode.wordpress-console",
        "wordpress-console-swift": "net.ranode.wordpress-console",
        "workflow-skill-compiler": "net.ranode.workflow-skill-compiler",
        "workflow-skill-compiler-swift": "net.ranode.workflow-skill-compiler",
        "worktree-lifecycle": "net.ranode.worktree-lifecycle",
        "worktree-lifecycle-swift": "net.ranode.worktree-lifecycle",
        "worktree-status-ui": "net.ranode.worktree-status-ui",
        "worktree-status-ui-swift": "net.ranode.worktree-status-ui",
        "x-trend-deck": "net.ranode.x-trend-deck",
        "x-trend-deck-swift": "net.ranode.x-trend-deck",
        "xlsx-viewer": "net.ranode.xlsx-viewer",
        "xlsx-viewer-swift": "net.ranode.xlsx-viewer",
    ]

    private static let knownBundleIDPrefixes = ["net.ranode.", "ai.gujo.", "kr.internal."]

    private static func isBundleIDPrefix(_ slug: String) -> Bool {
        knownBundleIDPrefixes.contains { slug.hasPrefix($0) }
    }

    private static func stripKnownSuffix(_ slug: String) -> String {
        let suffixes = ["-swift", "-ios"]
        for suffix in suffixes where slug.hasSuffix(suffix) {
            return String(slug.dropLast(suffix.count))
        }
        return slug
    }

    /// 슬러그 또는 디렉터리명으로부터 번들 ID 정본을 반환한다.
    public static func bundleID(forSlug slug: String) -> String {
        let trimmed = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return defaultPrefix
        }
        guard !isBundleIDPrefix(trimmed) else {
            return trimmed
        }
        if let mapped = slugToBundleID[trimmed] {
            return mapped
        }
        let stem = stripKnownSuffix(trimmed)
        return slugToBundleID[stem] ?? (defaultPrefix + stem)
    }

    public static func forSlug(_ slug: String) -> AppBundleID {
        AppBundleID(rawValue: bundleID(forSlug: slug))
    }

    // MARK: - Known App Bundle IDs
    public static let _2dGameAssetsCreate: AppBundleID = "net.ranode.game-assets-studio"
    public static let _3dModelFbxModify: AppBundleID = "net.ranode.3d-model-fbx-modify"
    public static let _3dModelFbxModifySwift: AppBundleID = "net.ranode.3d-model-fbx-modify"
    public static let agentAppManualFactory: AppBundleID = "net.ranode.agent-app-manual-factory"
    public static let agentAppManualFactorySwift: AppBundleID = "net.ranode.agent-app-manual-factory"
    public static let agentAppProbeDoctor: AppBundleID = "net.ranode.agent-app-probe-doctor"
    public static let agentAppProbeDoctorSwift: AppBundleID = "net.ranode.agent-app-probe-doctor"
    public static let agentAppRegistry: AppBundleID = "net.ranode.agent-app-registry"
    public static let agentAppRegistrySwift: AppBundleID = "net.ranode.agent-app-registry"
    public static let agentBatchCodemod: AppBundleID = "net.ranode.agent-batch-codemod"
    public static let agentBatchCodemodSwift: AppBundleID = "net.ranode.agent-batch-codemod"
    public static let agentBoardIOS: AppBundleID = "net.ranode.agent-board"
    public static let agentBoardIos: AppBundleID = "net.ranode.agent-board"
    public static let agentBrowser: AppBundleID = "net.ranode.agentbrowser"
    public static let agentBrowserLoginManager: AppBundleID = "net.ranode.agent-browser-login-manager"
    public static let agentBrowserLoginManagerSwift: AppBundleID = "net.ranode.agent-browser-login-manager"
    public static let agentBrowserRecipe: AppBundleID = "net.ranode.agent-browser-recipe"
    public static let agentBrowserRecipeSwift: AppBundleID = "net.ranode.agent-browser-recipe"
    public static let agentBrowserSwift: AppBundleID = "net.ranode.agentbrowser"
    public static let agentCapture: AppBundleID = "net.ranode.agent-capture"
    public static let agentCaptureSwift: AppBundleID = "net.ranode.agent-capture"
    public static let agentChat: AppBundleID = "net.ranode.agent-chat"
    public static let agentChatSwift: AppBundleID = "net.ranode.agent-chat"
    public static let agentChromiumEngine: AppBundleID = "net.ranode.agent-chromium-engine"
    public static let agentChromiumEngineSwift: AppBundleID = "net.ranode.agent-chromium-engine"
    public static let agentCliManager: AppBundleID = "net.ranode.agent-cli-manager"
    public static let agentCliManagerSwift: AppBundleID = "net.ranode.agent-cli-manager"
    public static let agentCliScaffold: AppBundleID = "net.ranode.agent-cli-scaffold"
    public static let agentCliScaffoldSwift: AppBundleID = "net.ranode.agent-cli-scaffold"
    public static let agentCodeCloneDetector: AppBundleID = "net.ranode.agent-code-clone-detector"
    public static let agentCodeCloneDetectorSwift: AppBundleID = "net.ranode.agent-code-clone-detector"
    public static let agentCodeReview: AppBundleID = "net.ranode.agent-code-review"
    public static let agentCodeReviewSwift: AppBundleID = "net.ranode.agent-code-review"
    public static let agentColonyObservatory: AppBundleID = "net.ranode.agent-colony-observatory"
    public static let agentColonyObservatorySwift: AppBundleID = "net.ranode.agent-colony-observatory"
    public static let agentCompany: AppBundleID = "net.ranode.agent-company"
    public static let agentCompanySwift: AppBundleID = "net.ranode.agent-company"
    public static let agentContextHub: AppBundleID = "net.ranode.agent-context-hub"
    public static let agentContextHubSwift: AppBundleID = "net.ranode.agent-context-hub"
    public static let agentContractHarness: AppBundleID = "net.ranode.AgentContractHarness"
    public static let agentContractHarnessSwift: AppBundleID = "net.ranode.AgentContractHarness"
    public static let agentControlPlane: AppBundleID = "net.ranode.agentcontrolplane"
    public static let agentControlPlaneSwift: AppBundleID = "net.ranode.agentcontrolplane"
    public static let agentDeck: AppBundleID = "net.ranode.agentdeck"
    public static let agentDeckConsole: AppBundleID = "net.ranode.agent-deck-console"
    public static let agentDeckConsoleSwift: AppBundleID = "net.ranode.agent-deck-console"
    public static let agentDeckSwift: AppBundleID = "net.ranode.agentdeck"
    public static let agentDocCodeDrift: AppBundleID = "net.ranode.agent-doc-code-drift"
    public static let agentDocCodeDriftSwift: AppBundleID = "net.ranode.agent-doc-code-drift"
    public static let agentDocumentUsage: AppBundleID = "net.ranode.agent-document-usage"
    public static let agentDocumentUsageSwift: AppBundleID = "net.ranode.agent-document-usage"
    public static let agentE2eRunner: AppBundleID = "net.ranode.agent-e2e-runner"
    public static let agentE2eRunnerSwift: AppBundleID = "net.ranode.agent-e2e-runner"
    public static let agentEmployeeRoster: AppBundleID = "net.ranode.agent-employee-roster"
    public static let agentEmployeeRosterSwift: AppBundleID = "net.ranode.agent-employee-roster"
    public static let agentFeatureCoordinator: AppBundleID = "net.ranode.agent-feature-coordinator"
    public static let agentFeatureCoordinatorSwift: AppBundleID = "net.ranode.agent-feature-coordinator"
    public static let agentFleetDailyReport: AppBundleID = "net.ranode.agent-fleet-daily-report"
    public static let agentFleetDailyReportSwift: AppBundleID = "net.ranode.agent-fleet-daily-report"
    public static let agentFleetMap: AppBundleID = "net.ranode.agent-fleet-map"
    public static let agentFleetMapSwift: AppBundleID = "net.ranode.agent-fleet-map"
    public static let agentFleetQuery: AppBundleID = "net.ranode.agent-fleet-query"
    public static let agentFleetQuerySwift: AppBundleID = "net.ranode.agent-fleet-query"
    public static let agentGameGodotOps: AppBundleID = "net.ranode.agent-game-godot-ops"
    public static let agentGameGodotOpsSwift: AppBundleID = "net.ranode.agent-game-godot-ops"
    public static let agentGuardrailManager: AppBundleID = "net.ranode.agent-guardrail-manager"
    public static let agentGuardrailManagerSwift: AppBundleID = "net.ranode.agent-guardrail-manager"
    public static let agentHandoff: AppBundleID = "net.ranode.agent-handoff"
    public static let agentHandoffSwift: AppBundleID = "net.ranode.agent-handoff"
    public static let agentHooksStatus: AppBundleID = "net.ranode.agent-hooks-status"
    public static let agentHooksStatusSwift: AppBundleID = "net.ranode.agent-hooks-status"
    public static let agentHostConfigChecker: AppBundleID = "net.ranode.agent-host-config-checker"
    public static let agentHostConfigCheckerSwift: AppBundleID = "net.ranode.agent-host-config-checker"
    public static let agentHostDoctor: AppBundleID = "net.ranode.agent-host-doctor"
    public static let agentHostDoctorSwift: AppBundleID = "net.ranode.agent-host-doctor"
    public static let agentIdentityAudit: AppBundleID = "net.ranode.agent-identity-audit"
    public static let agentIdentityAuditSwift: AppBundleID = "net.ranode.agent-identity-audit"
    public static let agentInfraCoordinator: AppBundleID = "net.ranode.agent-infra-coordinator"
    public static let agentInfraCoordinatorSwift: AppBundleID = "net.ranode.agent-infra-coordinator"
    public static let agentInvocationRefiner: AppBundleID = "net.ranode.agent-invocation-refiner"
    public static let agentInvocationRefinerSwift: AppBundleID = "net.ranode.agent-invocation-refiner"
    public static let agentInvocationReviewPipeline: AppBundleID = "ai.gujo.agent-invocation-review-pipeline"
    public static let agentInvocationReviewPipelineSwift: AppBundleID = "ai.gujo.agent-invocation-review-pipeline"
    public static let agentLintAutofix: AppBundleID = "net.ranode.agent-lint-autofix"
    public static let agentLintAutofixSwift: AppBundleID = "net.ranode.agent-lint-autofix"
    public static let agentLintBatchRunner: AppBundleID = "net.ranode.agent-lint-batch-runner"
    public static let agentLintBatchRunnerSwift: AppBundleID = "net.ranode.agent-lint-batch-runner"
    public static let agentLintCatalog: AppBundleID = "net.ranode.agent-lint-catalog"
    public static let agentLintCatalogSwift: AppBundleID = "net.ranode.agent-lint-catalog"
    public static let agentLoginPipelineManager: AppBundleID = "net.ranode.agent-login-pipeline-manager"
    public static let agentLoginPipelineManagerSwift: AppBundleID = "net.ranode.agent-login-pipeline-manager"
    public static let agentMdSsotManager: AppBundleID = "net.ranode.agent-md-ssot-manager"
    public static let agentMdSsotManagerSwift: AppBundleID = "net.ranode.agent-md-ssot-manager"
    public static let agentMemoryManager: AppBundleID = "net.ranode.agent-memory-manager"
    public static let agentMemoryManagerSwift: AppBundleID = "net.ranode.agent-memory-manager"
    public static let agentModelRegistry: AppBundleID = "net.ranode.agent-model-registry"
    public static let agentModelRegistrySwift: AppBundleID = "net.ranode.agent-model-registry"
    public static let agentMonorepoStudio: AppBundleID = "net.ranode.agent-monorepo-studio"
    public static let agentMonorepoStudioSwift: AppBundleID = "net.ranode.agent-monorepo-studio"
    public static let agentOpsMonitor: AppBundleID = "net.ranode.agent-ops-monitor"
    public static let agentOpsMonitorSwift: AppBundleID = "net.ranode.agent-ops-monitor"
    public static let agentOrchestrationDeck: AppBundleID = "net.ranode.agent-orchestration-deck"
    public static let agentOrchestrationDeckSwift: AppBundleID = "net.ranode.agent-orchestration-deck"
    public static let agentPluginCatalog: AppBundleID = "net.ranode.agent-plugin-catalog"
    public static let agentPluginCatalogSwift: AppBundleID = "net.ranode.agent-plugin-catalog"
    public static let agentProfileMonitor: AppBundleID = "net.ranode.agent-profile-monitor"
    public static let agentProfileMonitorSwift: AppBundleID = "net.ranode.agent-profile-monitor"
    public static let agentProjectBoard: AppBundleID = "net.ranode.agent-project-board"
    public static let agentProjectBoardSwift: AppBundleID = "net.ranode.agent-project-board"
    public static let agentProxyBroker: AppBundleID = "net.ranode.agent-proxy-broker"
    public static let agentProxyBrokerSwift: AppBundleID = "net.ranode.agent-proxy-broker"
    public static let agentQualityCoordinator: AppBundleID = "net.ranode.agent-quality-coordinator"
    public static let agentQualityCoordinatorSwift: AppBundleID = "net.ranode.agent-quality-coordinator"
    public static let agentQueueDoctor: AppBundleID = "net.ranode.agent-queue-doctor"
    public static let agentQueueDoctorSwift: AppBundleID = "net.ranode.agent-queue-doctor"
    public static let agentReachRepair: AppBundleID = "net.ranode.agent-reach-repair"
    public static let agentReachRepairSwift: AppBundleID = "net.ranode.agent-reach-repair"
    public static let agentReachWatch: AppBundleID = "net.ranode.agent-reach-watch"
    public static let agentReachWatchSwift: AppBundleID = "net.ranode.agent-reach-watch"
    public static let agentRegistryManager: AppBundleID = "net.ranode.agent-registry-manager"
    public static let agentRegistryManagerSwift: AppBundleID = "net.ranode.agent-registry-manager"
    public static let agentRemoteTerminal: AppBundleID = "net.ranode.agent-remote-terminal"
    public static let agentRemoteTerminalIOS: AppBundleID = "net.ranode.agent-remote-terminal"
    public static let agentRemoteTerminalIos: AppBundleID = "net.ranode.agent-remote-terminal"
    public static let agentRemoteTerminalSwift: AppBundleID = "net.ranode.agent-remote-terminal"
    public static let agentRequest: AppBundleID = "net.ranode.agent-request"
    public static let agentRequestLedger: AppBundleID = "net.ranode.agent-request-ledger"
    public static let agentRequestLedgerSwift: AppBundleID = "net.ranode.agent-request-ledger"
    public static let agentRequestSwift: AppBundleID = "net.ranode.agent-request"
    public static let agentReviewReporter: AppBundleID = "net.ranode.agent-review-reporter"
    public static let agentReviewReporterSwift: AppBundleID = "net.ranode.agent-review-reporter"
    public static let agentRoomMonitor: AppBundleID = "net.ranode.agent-room-monitor"
    public static let agentRoomMonitorSwift: AppBundleID = "net.ranode.agent-room-monitor"
    public static let agentRoomTerminal: AppBundleID = "net.ranode.agent-room-terminal"
    public static let agentRoomTerminalSwift: AppBundleID = "net.ranode.agent-room-terminal"
    public static let agentRoomWorktree: AppBundleID = "net.ranode.agent-room-worktree"
    public static let agentRoomWorktreeSwift: AppBundleID = "net.ranode.agent-room-worktree"
    public static let agentScheduleDispatcher: AppBundleID = "net.ranode.agent-schedule-dispatcher"
    public static let agentScheduleDispatcherSwift: AppBundleID = "net.ranode.agent-schedule-dispatcher"
    public static let agentSearchEngine: AppBundleID = "net.ranode.agent-search-engine"
    public static let agentSearchEngineSwift: AppBundleID = "net.ranode.agent-search-engine"
    public static let agentSeatManager: AppBundleID = "net.ranode.agent-seat-manager"
    public static let agentSeatManagerSwift: AppBundleID = "net.ranode.agent-seat-manager"
    public static let agentSessionArchive: AppBundleID = "net.ranode.agent-session-archive"
    public static let agentSessionArchiveSwift: AppBundleID = "net.ranode.agent-session-archive"
    public static let agentSessionContextLedger: AppBundleID = "net.ranode.agent-session-context-ledger"
    public static let agentSessionContextLedgerSwift: AppBundleID = "net.ranode.agent-session-context-ledger"
    public static let agentSessionReplay: AppBundleID = "net.ranode.agent-session-replay"
    public static let agentSessionReplaySwift: AppBundleID = "net.ranode.agent-session-replay"
    public static let agentSessionTaskRunner: AppBundleID = "net.ranode.agent-session-task-runner"
    public static let agentSessionTaskRunnerSwift: AppBundleID = "net.ranode.agent-session-task-runner"
    public static let agentSessionTimeline: AppBundleID = "net.ranode.agent-session-timeline"
    public static let agentSessionTimelineSwift: AppBundleID = "net.ranode.agent-session-timeline"
    public static let agentSkillBuildSystem: AppBundleID = "net.ranode.agent-skill-build-system"
    public static let agentSkillBuildSystemSwift: AppBundleID = "net.ranode.agent-skill-build-system"
    public static let agentSkillCatalog: AppBundleID = "net.ranode.agent-skill-catalog"
    public static let agentSkillCatalogSwift: AppBundleID = "net.ranode.agent-skill-catalog"
    public static let agentSkills: AppBundleID = "net.ranode.agent-skills"
    public static let agentSkillsSwift: AppBundleID = "net.ranode.agent-skills"
    public static let agentSsot: AppBundleID = "net.ranode.agent-ssot"
    public static let agentSsotSwift: AppBundleID = "net.ranode.agent-ssot"
    public static let agentSurfaceReach: AppBundleID = "net.ranode.agent-surface-reach"
    public static let agentSurfaceReachSwift: AppBundleID = "net.ranode.agent-surface-reach"
    public static let agentTenantIsolationManager: AppBundleID = "net.ranode.agent-tenant-isolation-manager"
    public static let agentTenantIsolationManagerSwift: AppBundleID = "net.ranode.agent-tenant-isolation-manager"
    public static let agentUiDriver: AppBundleID = "net.ranode.agent-ui-driver"
    public static let agentUiDriverSwift: AppBundleID = "net.ranode.agent-ui-driver"
    public static let agentUiMonitor: AppBundleID = "net.ranode.agent-ui-monitor"
    public static let agentUiMonitorSwift: AppBundleID = "net.ranode.agent-ui-monitor"
    public static let agentVault: AppBundleID = "net.ranode.agentvault"
    public static let agentVaultSwift: AppBundleID = "net.ranode.agentvault"
    public static let agentWikiGlobal: AppBundleID = "net.ranode.agent-wiki-global"
    public static let agentWikiGlobalSwift: AppBundleID = "net.ranode.agent-wiki-global"
    public static let agentWikiGraph: AppBundleID = "net.ranode.agent-wiki-graph"
    public static let agentWikiGraphReaper: AppBundleID = "net.ranode.agent-wiki-graph-reaper"
    public static let agentWikiGraphReaperSwift: AppBundleID = "net.ranode.agent-wiki-graph-reaper"
    public static let agentWikiGraphStudio: AppBundleID = "net.ranode.agent-wiki-graph-studio"
    public static let agentWikiGraphStudioSwift: AppBundleID = "net.ranode.agent-wiki-graph-studio"
    public static let agentWikiGraphSwift: AppBundleID = "net.ranode.agent-wiki-graph"
    public static let agentWikiLocal: AppBundleID = "net.ranode.agent-wiki-local"
    public static let agentWikiLocalSwift: AppBundleID = "net.ranode.agent-wiki-local"
    public static let agentWikiReader: AppBundleID = "net.ranode.agent-wiki-reader"
    public static let agentWikiReaderSwift: AppBundleID = "net.ranode.agent-wiki-reader"
    public static let agentWikiStudio: AppBundleID = "net.ranode.agent-wiki-studio"
    public static let agentWikiStudioSwift: AppBundleID = "net.ranode.agent-wiki-studio"
    public static let agentWindowControl: AppBundleID = "net.ranode.agent-window-control"
    public static let agentWindowControlSwift: AppBundleID = "net.ranode.agent-window-control"
    public static let agentWorkMonitor: AppBundleID = "net.ranode.agent-work-monitor"
    public static let agentWorkMonitorSwift: AppBundleID = "net.ranode.agent-work-monitor"
    public static let agentWorkReport: AppBundleID = "net.ranode.agent-work-report"
    public static let agentWorkReportSwift: AppBundleID = "net.ranode.agent-work-report"
    public static let agentWorkTodo: AppBundleID = "net.ranode.agent-work-todo"
    public static let agentWorkerOrchestrator: AppBundleID = "net.ranode.agent-worker-orchestrator"
    public static let agentWorkerOrchestratorSwift: AppBundleID = "net.ranode.agent-worker-orchestrator"
    public static let agentWorktreeControlTerminal: AppBundleID = "net.ranode.agent-worktree-control-terminal"
    public static let agentWorktreeControlTerminalSwift: AppBundleID = "net.ranode.agent-worktree-control-terminal"
    public static let agentWorktreeDoctor: AppBundleID = "net.ranode.agent-worktree-doctor"
    public static let agentWorktreeDoctorSwift: AppBundleID = "net.ranode.agent-worktree-doctor"
    public static let aiAgentConfigurationManager: AppBundleID = "net.ranode.ai-agent-configuration-manager"
    public static let aiAgentConfigurationManagerSwift: AppBundleID = "net.ranode.ai-agent-configuration-manager"
    public static let aiCliAccountManager: AppBundleID = "net.ranode.ai-cli-account-manager"
    public static let aiCliAccountManagerSwift: AppBundleID = "net.ranode.ai-cli-account-manager"
    public static let aiCliLauncher: AppBundleID = "net.ranode.ai-cli-launcher"
    public static let aiCliLauncherSwift: AppBundleID = "net.ranode.ai-cli-launcher"
    public static let aiCliProxyBroker: AppBundleID = "net.ranode.ai-cli-proxy-broker"
    public static let aiCliProxyBrokerSwift: AppBundleID = "net.ranode.ai-cli-proxy-broker"
    public static let aiCliRouter: AppBundleID = "net.ranode.ai-cli-router"
    public static let aiCliRouterSwift: AppBundleID = "net.ranode.ai-cli-router"
    public static let androidAdbManager: AppBundleID = "net.ranode.android-adb-manager"
    public static let androidAdbManagerSwift: AppBundleID = "net.ranode.android-adb-manager"
    public static let androidAppStore: AppBundleID = "net.ranode.androidappstore"
    public static let androidAppStoreSwift: AppBundleID = "net.ranode.androidappstore"
    public static let androidSettingsManual: AppBundleID = "net.ranode.android-settings-manual"
    public static let androidSettingsManualSwift: AppBundleID = "net.ranode.android-settings-manual"
    public static let androidTransfer: AppBundleID = "net.ranode.androidtransfer"
    public static let androidTransferSwift: AppBundleID = "net.ranode.androidtransfer"
    public static let apiQaGujoApi: AppBundleID = "net.ranode.api-qa-gujo-api"
    public static let apiQaGujoApiSwift: AppBundleID = "net.ranode.api-qa-gujo-api"
    public static let appBuildManager: AppBundleID = "net.ranode.appbuildmanager"
    public static let appBuildManagerSwift: AppBundleID = "net.ranode.appbuildmanager"
    public static let appChangelogManager: AppBundleID = "net.ranode.app-changelog-manager"
    public static let appChangelogManagerSwift: AppBundleID = "net.ranode.app-changelog-manager"
    public static let appDebugConsole: AppBundleID = "net.ranode.appdebugconsole"
    public static let appDebugConsoleSwift: AppBundleID = "net.ranode.appdebugconsole"
    public static let appDistributionManager: AppBundleID = "ai.gujo.app-distribution-manager"
    public static let appDistributionManagerSwift: AppBundleID = "ai.gujo.app-distribution-manager"
    public static let appFleetBrowser: AppBundleID = "net.ranode.app-fleet-browser"
    public static let appFleetBrowserSwift: AppBundleID = "net.ranode.app-fleet-browser"
    public static let appFleetCity: AppBundleID = "net.ranode.app-fleet-city"
    public static let appFleetCitySwift: AppBundleID = "net.ranode.app-fleet-city"
    public static let appFleetDoctor: AppBundleID = "net.ranode.app-fleet-doctor"
    public static let appFleetDoctorSwift: AppBundleID = "net.ranode.app-fleet-doctor"
    public static let appFleetQualityAuditor: AppBundleID = "net.ranode.app-fleet-quality-auditor"
    public static let appFleetQualityAuditorSwift: AppBundleID = "net.ranode.app-fleet-quality-auditor"
    public static let appFleetSecurity: AppBundleID = "net.ranode.app-fleet-security"
    public static let appFleetSecuritySwift: AppBundleID = "net.ranode.app-fleet-security"
    public static let appHealthGuard: AppBundleID = "net.ranode.apphealthguard"
    public static let appHealthGuardSwift: AppBundleID = "net.ranode.apphealthguard"
    public static let appI18nInspector: AppBundleID = "net.ranode.app-i18n-inspector"
    public static let appI18nInspectorSwift: AppBundleID = "net.ranode.app-i18n-inspector"
    public static let appIconForge: AppBundleID = "net.ranode.app-icon-forge"
    public static let appIconForgeSwift: AppBundleID = "net.ranode.app-icon-forge"
    public static let appLaunchDoctor: AppBundleID = "net.ranode.app-launch-doctor"
    public static let appLaunchDoctorSwift: AppBundleID = "net.ranode.app-launch-doctor"
    public static let appLifecycleIndex: AppBundleID = "net.ranode.app-lifecycle-index"
    public static let appLifecycleIndexSwift: AppBundleID = "net.ranode.app-lifecycle-index"
    public static let appLifecyclePipelineManager: AppBundleID = "net.ranode.app-lifecycle-pipeline-manager"
    public static let appLifecyclePipelineManagerSwift: AppBundleID = "net.ranode.app-lifecycle-pipeline-manager"
    public static let appMarketabilityStudio: AppBundleID = "net.ranode.app-marketability-studio"
    public static let appNotaryManager: AppBundleID = "net.ranode.app-notary-manager"
    public static let appNotaryManagerSwift: AppBundleID = "net.ranode.app-notary-manager"
    public static let appRelaunchWatch: AppBundleID = "net.ranode.app-relaunch-watch"
    public static let appRelaunchWatchSwift: AppBundleID = "net.ranode.app-relaunch-watch"
    public static let appReleasePropagation: AppBundleID = "net.ranode.app-release-propagation"
    public static let appReleasePropagationSwift: AppBundleID = "net.ranode.app-release-propagation"
    public static let appRepairLedger: AppBundleID = "net.ranode.app-repair-ledger"
    public static let appRepairLedgerSwift: AppBundleID = "net.ranode.app-repair-ledger"
    public static let appSalesManager: AppBundleID = "net.ranode.app-sales-manager"
    public static let appSalesManagerSwift: AppBundleID = "net.ranode.app-sales-manager"
    public static let appSaves: AppBundleID = "net.ranode.app-saves"
    public static let appSavesSwift: AppBundleID = "net.ranode.app-saves"
    public static let appSearchRootLocator: AppBundleID = "net.ranode.agent-apps-bar"
    public static let appSearchRootLocatorSwift: AppBundleID = "net.ranode.agent-apps-bar"
    public static let appShipManager: AppBundleID = "net.ranode.app-ship-manager"
    public static let appShipManagerSwift: AppBundleID = "net.ranode.app-ship-manager"
    public static let appSignatureIntegrityChecker: AppBundleID = "net.ranode.app-signature-integrity-checker"
    public static let appSignatureIntegrityCheckerSwift: AppBundleID = "net.ranode.app-signature-integrity-checker"
    public static let appStoreAssetForge: AppBundleID = "net.ranode.app-store-asset-forge"
    public static let appUsabilityScorer: AppBundleID = "net.ranode.app-usability-scorer"
    public static let appUsabilityScorerSwift: AppBundleID = "net.ranode.app-usability-scorer"
    public static let appleDeveloperIdentity: AppBundleID = "net.ranode.appledeveloperidentity"
    public static let appleDeveloperIdentitySwift: AppBundleID = "net.ranode.appledeveloperidentity"
    public static let awoK8sBridge: AppBundleID = "net.ranode.awo-k8s-bridge"
    public static let awoK8sBridgeSwift: AppBundleID = "net.ranode.awo-k8s-bridge"
    public static let backgroundJobConsole: AppBundleID = "net.ranode.backgroundjobconsole"
    public static let backgroundJobConsoleSwift: AppBundleID = "net.ranode.backgroundjobconsole"
    public static let backupDuplicateManager: AppBundleID = "net.ranode.backup-duplicate-manager"
    public static let backupDuplicateManagerSwift: AppBundleID = "net.ranode.backup-duplicate-manager"
    public static let backupToNas: AppBundleID = "net.ranode.backuptonas"
    public static let backupToNasSwift: AppBundleID = "net.ranode.backuptonas"
    public static let batteryGuard: AppBundleID = "net.ranode.battery-guard"
    public static let batteryGuardSwift: AppBundleID = "net.ranode.battery-guard"
    public static let blockEditor: AppBundleID = "net.ranode.block-editor"
    public static let blockEditorSwift: AppBundleID = "net.ranode.block-editor"
    public static let brainLife: AppBundleID = "net.ranode.brain-life"
    public static let brainLifeSwift: AppBundleID = "net.ranode.brain-life"
    public static let browserMcpDashboard: AppBundleID = "net.ranode.browsermcpdashboard"
    public static let browserMcpDashboardSwift: AppBundleID = "net.ranode.browsermcpdashboard"
    public static let browserProfileManager: AppBundleID = "net.ranode.browser-profile-manager"
    public static let browserProfileManagerSwift: AppBundleID = "net.ranode.browser-profile-manager"
    public static let browserWindowLocator: AppBundleID = "net.ranode.browser-window-locator"
    public static let browserWindowLocatorSwift: AppBundleID = "net.ranode.browser-window-locator"
    public static let buildQueueManager: AppBundleID = "net.ranode.build-queue-manager"
    public static let buildQueueManagerSwift: AppBundleID = "net.ranode.build-queue-manager"
    public static let buildRunMonitor: AppBundleID = "net.ranode.build-run-monitor"
    public static let buildRunMonitorSwift: AppBundleID = "net.ranode.build-run-monitor"
    public static let businessAccountingLedger: AppBundleID = "net.ranode.business-accounting-ledger"
    public static let businessAccountingLedgerSwift: AppBundleID = "net.ranode.business-accounting-ledger"
    public static let businessApi: AppBundleID = "net.ranode.business-api"
    public static let businessApiSwift: AppBundleID = "net.ranode.business-api"
    public static let businessContacts: AppBundleID = "net.ranode.business-contacts"
    public static let businessContactsIOS: AppBundleID = "net.ranode.business-contacts"
    public static let businessContactsIos: AppBundleID = "net.ranode.business-contacts"
    public static let businessContactsSwift: AppBundleID = "net.ranode.business-contacts"
    public static let businessDocuments: AppBundleID = "net.ranode.business-documents"
    public static let businessDocumentsIOS: AppBundleID = "net.ranode.business-documents"
    public static let businessDocumentsIos: AppBundleID = "net.ranode.business-documents"
    public static let businessDocumentsSwift: AppBundleID = "net.ranode.business-documents"
    public static let businessEntityIOS: AppBundleID = "net.ranode.business-entity"
    public static let businessEntityIos: AppBundleID = "net.ranode.business-entity"
    public static let businessLedger: AppBundleID = "net.ranode.business-ledger"
    public static let businessLedgerSwift: AppBundleID = "net.ranode.business-ledger"
    public static let businessLoanManager: AppBundleID = "net.ranode.business-loan-manager"
    public static let businessLoanManagerSwift: AppBundleID = "net.ranode.business-loan-manager"
    public static let businessPeople: AppBundleID = "net.ranode.business-people"
    public static let businessPeopleSwift: AppBundleID = "net.ranode.business-people"
    public static let businessProjects: AppBundleID = "net.ranode.business-projects"
    public static let businessProjectsSwift: AppBundleID = "net.ranode.business-projects"
    public static let businessQuoteManager: AppBundleID = "net.ranode.business-quote-manager"
    public static let businessQuoteManagerSwift: AppBundleID = "net.ranode.business-quote-manager"
    public static let businessRequestIntake: AppBundleID = "net.ranode.business-request-intake"
    public static let businessRequestIntakeSwift: AppBundleID = "net.ranode.business-request-intake"
    public static let businessSchedule: AppBundleID = "net.ranode.business-schedule"
    public static let businessScheduleSwift: AppBundleID = "net.ranode.business-schedule"
    public static let businessServiceCatalog: AppBundleID = "net.ranode.business-service-catalog"
    public static let businessServiceCatalogSwift: AppBundleID = "net.ranode.business-service-catalog"
    public static let businessTaxEvidenceLedger: AppBundleID = "net.ranode.business-tax-evidence-ledger"
    public static let businessTaxEvidenceLedgerSwift: AppBundleID = "net.ranode.business-tax-evidence-ledger"
    public static let businessTaxFilingManager: AppBundleID = "net.ranode.business-tax-filing-manager"
    public static let businessTaxFilingManagerSwift: AppBundleID = "net.ranode.business-tax-filing-manager"
    public static let businessTaxRecords: AppBundleID = "net.ranode.business-tax-records"
    public static let businessTaxRecordsSwift: AppBundleID = "net.ranode.business-tax-records"
    public static let cardbackup: AppBundleID = "net.ranode.cardbackup"
    public static let cardbackupSwift: AppBundleID = "net.ranode.cardbackup"
    public static let cardnewsGen: AppBundleID = "net.ranode.cardnewsgen"
    public static let cardnewsGenSwift: AppBundleID = "net.ranode.cardnewsgen"
    public static let cdnStorageManager: AppBundleID = "net.ranode.cdn-storage-manager"
    public static let cdnStorageManagerSwift: AppBundleID = "net.ranode.cdn-storage-manager"
    public static let certificateManager: AppBundleID = "net.ranode.certificate-manager"
    public static let certificateManagerSwift: AppBundleID = "net.ranode.certificate-manager"
    public static let chromiumRuntimeManager: AppBundleID = "net.ranode.chromium-runtime-manager"
    public static let chromiumRuntimeManagerSwift: AppBundleID = "net.ranode.chromium-runtime-manager"
    public static let clamshellMode: AppBundleID = "net.ranode.clamshell-mode"
    public static let clamshellModeSwift: AppBundleID = "net.ranode.clamshell-mode"
    public static let cliCatalog: AppBundleID = "net.ranode.clicatalog"
    public static let cliCatalogSwift: AppBundleID = "net.ranode.clicatalog"
    public static let clipboardCloudkitSyncPoc: AppBundleID = "net.ranode.clipboard-sync-poc"
    public static let clipboardHistory: AppBundleID = "net.ranode.clipboardhistoryswift"
    public static let clipboardHistorySwift: AppBundleID = "net.ranode.clipboardhistoryswift"
    public static let clipboardIosCapturePoc: AppBundleID = "net.ranode.clipboard-sync-poc"
    public static let clipboardRelayIOS: AppBundleID = "net.ranode.clipboard-relay"
    public static let clipboardRelayIos: AppBundleID = "net.ranode.clipboard-relay"
    public static let cloudflareDeployManager: AppBundleID = "net.ranode.cloudflare-deploy-manager"
    public static let cloudflareDeployManagerSwift: AppBundleID = "net.ranode.cloudflare-deploy-manager"
    public static let codeSignHelper: AppBundleID = "net.ranode.codesignhelper"
    public static let codeSignHelperSwift: AppBundleID = "net.ranode.codesignhelper"
    public static let codebasePorter: AppBundleID = "net.ranode.codebase-porter"
    public static let codebasePorterSwift: AppBundleID = "net.ranode.codebase-porter"
    public static let comfyuiStudio: AppBundleID = "net.ranode.comfyui-studio"
    public static let comfyuiStudioSwift: AppBundleID = "net.ranode.comfyui-studio"
    public static let containerBrowserEmulator: AppBundleID = "net.ranode.containerbrowseremulator"
    public static let containerBrowserEmulatorSwift: AppBundleID = "net.ranode.containerbrowseremulator"
    public static let containerManager: AppBundleID = "net.ranode.container-manager"
    public static let containerManagerSwift: AppBundleID = "net.ranode.container-manager"
    public static let contextCharacters: AppBundleID = "net.ranode.context-characters"
    public static let contextCharactersSwift: AppBundleID = "net.ranode.context-characters"
    public static let cpuUsageMonitor: AppBundleID = "net.ranode.cpuusagemonitor"
    public static let cpuUsageMonitorSwift: AppBundleID = "net.ranode.cpuusagemonitor"
    public static let creativeSourceBridge: AppBundleID = "net.ranode.creative-source-bridge"
    public static let creativeSourceBridgeSwift: AppBundleID = "net.ranode.creative-source-bridge"
    public static let credentialManager: AppBundleID = "net.ranode.credential-manager"
    public static let credentialManagerSwift: AppBundleID = "net.ranode.credential-manager"
    public static let customerFeedbackStudio: AppBundleID = "net.ranode.customer-feedback-studio"
    public static let customerFeedbackStudioSwift: AppBundleID = "net.ranode.customer-feedback-studio"
    public static let dalAsofDerive: AppBundleID = "net.ranode.dal-asof-derive"
    public static let dalAsofDeriveSwift: AppBundleID = "net.ranode.dal-asof-derive"
    public static let dalChemLedger: AppBundleID = "net.ranode.dal-chem-ledger"
    public static let dalChemLedgerSwift: AppBundleID = "net.ranode.dal-chem-ledger"
    public static let dalChemSystem: AppBundleID = "net.ranode.dal-chem-system"
    public static let dalChemSystemSwift: AppBundleID = "net.ranode.dal-chem-system"
    public static let dalConception: AppBundleID = "net.ranode.dal-conception"
    public static let dalConceptionSwift: AppBundleID = "net.ranode.dal-conception"
    public static let dalCortexScribe: AppBundleID = "net.ranode.dal-cortex-scribe"
    public static let dalCortexScribeSwift: AppBundleID = "net.ranode.dal-cortex-scribe"
    public static let dalDreamConsolidate: AppBundleID = "net.ranode.dal-dream-consolidate"
    public static let dalDreamConsolidateSwift: AppBundleID = "net.ranode.dal-dream-consolidate"
    public static let dalEnergyOrgan: AppBundleID = "net.ranode.dal-energy-organ"
    public static let dalEnergyOrganSwift: AppBundleID = "net.ranode.dal-energy-organ"
    public static let dalGangliaSelect: AppBundleID = "net.ranode.dal-ganglia-select"
    public static let dalGangliaSelectSwift: AppBundleID = "net.ranode.dal-ganglia-select"
    public static let dalHippocampusRecall: AppBundleID = "net.ranode.dal-hippocampus-recall"
    public static let dalHippocampusRecallSwift: AppBundleID = "net.ranode.dal-hippocampus-recall"
    public static let dalPersona: AppBundleID = "net.ranode.dal-persona"
    public static let dalPersonaSwift: AppBundleID = "net.ranode.dal-persona"
    public static let dalSpaceCoords: AppBundleID = "net.ranode.dal-space-coords"
    public static let dalSpaceCoordsSwift: AppBundleID = "net.ranode.dal-space-coords"
    public static let databaseviewer: AppBundleID = "net.ranode.databaseviewer"
    public static let databaseviewerSwift: AppBundleID = "net.ranode.databaseviewer"
    public static let designComponentLibrary: AppBundleID = "net.ranode.design-component-library"
    public static let designComponentLibrarySwift: AppBundleID = "net.ranode.design-component-library"
    public static let designSystemStudio: AppBundleID = "net.ranode.designsystemstudio"
    public static let designSystemStudioSwift: AppBundleID = "net.ranode.designsystemstudio"
    public static let detailpageStages: AppBundleID = "net.ranode.detailpage-stages"
    public static let devClean: AppBundleID = "net.ranode.devclean"
    public static let devCleanSwift: AppBundleID = "net.ranode.devclean"
    public static let deviceDeck: AppBundleID = "net.ranode.device-deck"
    public static let deviceDeckSwift: AppBundleID = "net.ranode.device-deck"
    public static let discordChannelReader: AppBundleID = "net.ranode.discord-channel-reader"
    public static let discordChannelReaderSwift: AppBundleID = "net.ranode.discord-channel-reader"
    public static let diskSpaceAnalyzer: AppBundleID = "net.ranode.disk-space-analyzer"
    public static let diskSpaceAnalyzerSwift: AppBundleID = "net.ranode.disk-space-analyzer"
    public static let diskUsageAnalyzer: AppBundleID = "net.ranode.disk-usage-analyzer"
    public static let diskUsageAnalyzerSwift: AppBundleID = "net.ranode.disk-usage-analyzer"
    public static let dnsGuard: AppBundleID = "net.ranode.dns-guard"
    public static let dnsGuardSwift: AppBundleID = "net.ranode.dns-guard"
    public static let dnsSwitcher: AppBundleID = "net.ranode.dnsswitcher"
    public static let dnsSwitcherSwift: AppBundleID = "net.ranode.dnsswitcher"
    public static let dnsZoneManager: AppBundleID = "net.ranode.dnszonemanager"
    public static let dnsZoneManagerSwift: AppBundleID = "net.ranode.dnszonemanager"
    public static let domainRegistry: AppBundleID = "net.ranode.domain-registry"
    public static let domainRegistrySwift: AppBundleID = "net.ranode.domain-registry"
    public static let dubStages: AppBundleID = "net.ranode.dub-stages"
    public static let emulatorVncSessionController: AppBundleID = "net.ranode.emulator-vnc-session-controller"
    public static let emulatorVncSessionControllerSwift: AppBundleID = "net.ranode.emulator-vnc-session-controller"
    public static let envVault: AppBundleID = "net.ranode.envvault"
    public static let envVaultSwift: AppBundleID = "net.ranode.envvault"
    public static let excalidraw: AppBundleID = "net.ranode.excalidraw"
    public static let excalidrawIOS: AppBundleID = "net.ranode.excalidraw-ipad"
    public static let excalidrawIos: AppBundleID = "net.ranode.excalidraw-ipad"
    public static let excalidrawSwift: AppBundleID = "net.ranode.excalidraw"
    public static let featureBacklogStudio: AppBundleID = "net.ranode.feature-backlog-studio"
    public static let featureBacklogStudioSwift: AppBundleID = "net.ranode.feature-backlog-studio"
    public static let feeCalculationRecords: AppBundleID = "net.ranode.fee-calculation-records"
    public static let feeCalculationRecordsSwift: AppBundleID = "net.ranode.fee-calculation-records"
    public static let fileArrivalWatcher: AppBundleID = "net.ranode.file-arrival-watcher"
    public static let fileArrivalWatcherSwift: AppBundleID = "net.ranode.file-arrival-watcher"
    public static let filmProjectCatalog: AppBundleID = "net.ranode.film-project-catalog"
    public static let filmProjectCatalogSwift: AppBundleID = "net.ranode.film-project-catalog"
    public static let fleetAppCatalog: AppBundleID = "net.ranode.fleetappcatalog"
    public static let fleetAppCatalogSwift: AppBundleID = "net.ranode.fleetappcatalog"
    public static let fleetDock: AppBundleID = "net.ranode.fleet-dock"
    public static let fleetDockSwift: AppBundleID = "net.ranode.fleet-dock"
    public static let flowStages: AppBundleID = "net.ranode.flow-stages"
    public static let flowlog: AppBundleID = "net.ranode.flowlog"
    public static let flowlogSwift: AppBundleID = "net.ranode.flowlog"
    public static let gitRepositoryArchiveManager: AppBundleID = "net.ranode.git-repository-archive-manager"
    public static let gitRepositoryArchiveManagerSwift: AppBundleID = "net.ranode.git-repository-archive-manager"
    public static let githubStatusUi: AppBundleID = "net.ranode.github-status-ui"
    public static let githubStatusUiSwift: AppBundleID = "net.ranode.github-status-ui"
    public static let gitlabAdmin: AppBundleID = "net.ranode.gitlab-admin"
    public static let gitlabAdminSwift: AppBundleID = "net.ranode.gitlab-admin"
    public static let gitlabBoardIOS: AppBundleID = "net.ranode.gitlab-board"
    public static let gitlabBoardIos: AppBundleID = "net.ranode.gitlab-board"
    public static let gitlabManager: AppBundleID = "net.ranode.gitlab-status-ui"
    public static let gitlabManagerSwift: AppBundleID = "net.ranode.gitlab-status-ui"
    public static let gitlabMrReview: AppBundleID = "net.ranode.gitlab-mr-review"
    public static let gitlabMrReviewSwift: AppBundleID = "net.ranode.gitlab-mr-review"
    public static let gitlabTokenMonitor: AppBundleID = "net.ranode.gitlab-token-monitor"
    public static let gitlabTokenMonitorSwift: AppBundleID = "net.ranode.gitlab-token-monitor"
    public static let governmentSupportApplicationTracker: AppBundleID = "net.ranode.government-support-application-tracker"
    public static let governmentSupportApplicationTrackerSwift: AppBundleID = "net.ranode.government-support-application-tracker"
    public static let governmentSupportCompanyProfile: AppBundleID = "net.ranode.government-support-company-profile"
    public static let governmentSupportCompanyProfileSwift: AppBundleID = "net.ranode.government-support-company-profile"
    public static let governmentSupportHwpFormFiller: AppBundleID = "net.ranode.government-support-hwp-form-filler"
    public static let governmentSupportHwpFormFillerSwift: AppBundleID = "net.ranode.government-support-hwp-form-filler"
    public static let governmentSupportIdeaBrainstorm: AppBundleID = "net.ranode.government-support-idea-brainstorm"
    public static let governmentSupportIdeaBrainstormSwift: AppBundleID = "net.ranode.government-support-idea-brainstorm"
    public static let governmentSupportProgramCatalog: AppBundleID = "net.ranode.government-support-program-catalog"
    public static let governmentSupportProgramCatalogSwift: AppBundleID = "net.ranode.government-support-program-catalog"
    public static let governmentSupportProgramMatcher: AppBundleID = "net.ranode.government-support-program-matcher"
    public static let governmentSupportProgramMatcherSwift: AppBundleID = "net.ranode.government-support-program-matcher"
    public static let governmentSupportSourceSites: AppBundleID = "net.ranode.government-support-source-sites"
    public static let governmentSupportSourceSitesSwift: AppBundleID = "net.ranode.government-support-source-sites"
    public static let gpuServerManager: AppBundleID = "net.ranode.gpu-server-manager"
    public static let gpuServerManagerSwift: AppBundleID = "net.ranode.gpu-server-manager"
    public static let gpuVideoStudio: AppBundleID = "net.ranode.gpu-video-studio"
    public static let gpuVideoStudioSwift: AppBundleID = "net.ranode.gpu-video-studio"
    public static let grafanaFleetMonitor: AppBundleID = "net.ranode.grafana-fleet-monitor"
    public static let grafanaFleetMonitorSwift: AppBundleID = "net.ranode.grafana-fleet-monitor"
    public static let guiTreeExplorer: AppBundleID = "net.ranode.gui-tree-explorer"
    public static let guiTreeExplorerSwift: AppBundleID = "net.ranode.gui-tree-explorer"
    public static let gujoAccountManager: AppBundleID = "net.ranode.gujo-account-manager"
    public static let gujoAccountManagerSwift: AppBundleID = "net.ranode.gujo-account-manager"
    public static let gujoAdMessageSender: AppBundleID = "net.ranode.gujo-ad-message-sender"
    public static let gujoAdMessageSenderSwift: AppBundleID = "net.ranode.gujo-ad-message-sender"
    public static let gujoAssetStudio: AppBundleID = "net.ranode.gujo-asset-studio"
    public static let gujoAssetStudioSwift: AppBundleID = "net.ranode.gujo-asset-studio"
    public static let gujoCatalogManager: AppBundleID = "net.ranode.gujo-catalog-manager"
    public static let gujoCatalogManagerSwift: AppBundleID = "net.ranode.gujo-catalog-manager"
    public static let gujoCfEmailManager: AppBundleID = "net.ranode.gujo-cf-email-manager"
    public static let gujoCfEmailManagerSwift: AppBundleID = "net.ranode.gujo-cf-email-manager"
    public static let gujoCloudApps: AppBundleID = "net.ranode.gujo-cloud-apps"
    public static let gujoCloudAppsSwift: AppBundleID = "net.ranode.gujo-cloud-apps"
    public static let gujoCommerceDesk: AppBundleID = "net.ranode.gujo-commerce-desk"
    public static let gujoCommerceDeskSwift: AppBundleID = "net.ranode.gujo-commerce-desk"
    public static let gujoCouponManager: AppBundleID = "net.ranode.gujo-coupon-manager"
    public static let gujoCouponManagerSwift: AppBundleID = "net.ranode.gujo-coupon-manager"
    public static let gujoCustomerManager: AppBundleID = "net.ranode.gujo-customer-manager"
    public static let gujoCustomerManagerSwift: AppBundleID = "net.ranode.gujo-customer-manager"
    public static let gujoDesignGalleryManager: AppBundleID = "net.ranode.gujo-design-gallery-manager"
    public static let gujoDesignGalleryManagerSwift: AppBundleID = "net.ranode.gujo-design-gallery-manager"
    public static let gujoDownloadPipelineAuditor: AppBundleID = "net.ranode.gujo-download-pipeline-auditor"
    public static let gujoDownloadPipelineAuditorSwift: AppBundleID = "net.ranode.gujo-download-pipeline-auditor"
    public static let gujoLaravelOperations: AppBundleID = "net.ranode.gujo-laravel-operations"
    public static let gujoLaravelOperationsSwift: AppBundleID = "net.ranode.gujo-laravel-operations"
    public static let gujoLaravelScheduler: AppBundleID = "net.ranode.gujo-laravel-scheduler"
    public static let gujoLaravelSchedulerSwift: AppBundleID = "net.ranode.gujo-laravel-scheduler"
    public static let gujoManagedAdoptionManager: AppBundleID = "net.ranode.gujo-managed-adoption-manager"
    public static let gujoManagedAdoptionManagerSwift: AppBundleID = "net.ranode.gujo-managed-adoption-manager"
    public static let gujoNewsletterSender: AppBundleID = "net.ranode.gujo-newsletter-sender"
    public static let gujoNewsletterSenderSwift: AppBundleID = "net.ranode.gujo-newsletter-sender"
    public static let gujoPaymentTester: AppBundleID = "net.ranode.gujo-payment-tester"
    public static let gujoPaymentTesterSwift: AppBundleID = "net.ranode.gujo-payment-tester"
    public static let gujoProductGate: AppBundleID = "net.ranode.gujo-product-gate"
    public static let gujoProductGateSwift: AppBundleID = "net.ranode.gujo-product-gate"
    public static let gujoProductStudio: AppBundleID = "net.ranode.gujo-product-proof-studio"
    public static let gujoProductStudioSwift: AppBundleID = "net.ranode.gujo-product-proof-studio"
    public static let gujoServiceMailer: AppBundleID = "net.ranode.gujo-service-mailer"
    public static let gujoServiceMailerSwift: AppBundleID = "net.ranode.gujo-service-mailer"
    public static let gujoServiceQa: AppBundleID = "net.ranode.gujo-service-qa"
    public static let gujoServiceQaSwift: AppBundleID = "net.ranode.gujo-service-qa"
    public static let gujoSkillPublisher: AppBundleID = "net.ranode.gujo-skill-publisher"
    public static let gujoSkillPublisherSwift: AppBundleID = "net.ranode.gujo-skill-publisher"
    public static let gujoSkillStore: AppBundleID = "net.ranode.gujo-skill-store"
    public static let gujoSkillStoreSwift: AppBundleID = "net.ranode.gujo-skill-store"
    public static let gujoStoreListingManager: AppBundleID = "net.ranode.gujo-store-listing-manager"
    public static let gujoStoreListingManagerSwift: AppBundleID = "net.ranode.gujo-store-listing-manager"
    public static let gujoStoreOps: AppBundleID = "net.ranode.gujo-store-ops"
    public static let gujoStoreOpsIOS: AppBundleID = "net.ranode.gujo-store-ops-ios"
    public static let gujoStoreOpsIos: AppBundleID = "net.ranode.gujo-store-ops-ios"
    public static let gujoStoreOpsSwift: AppBundleID = "net.ranode.gujo-store-ops"
    public static let gujoSupportDesk: AppBundleID = "net.ranode.gujo-support-desk"
    public static let gujoSupportDeskSwift: AppBundleID = "net.ranode.gujo-support-desk"
    public static let helmReleaseManager: AppBundleID = "net.ranode.helmreleasemanager"
    public static let helmReleaseManagerSwift: AppBundleID = "net.ranode.helmreleasemanager"
    public static let hermes: AppBundleID = "net.ranode.hermes"
    public static let hermesSwift: AppBundleID = "net.ranode.hermes"
    public static let homeControlDashboard: AppBundleID = "net.ranode.home-control-dashboard"
    public static let homeControlDashboardSwift: AppBundleID = "net.ranode.home-control-dashboard"
    public static let hostSettingsLedger: AppBundleID = "net.ranode.host-settings-ledger"
    public static let hostSettingsLedgerSwift: AppBundleID = "net.ranode.host-settings-ledger"
    public static let httpApiClient: AppBundleID = "net.ranode.http-api-client"
    public static let httpApiClientSwift: AppBundleID = "net.ranode.http-api-client"
    public static let humanGateOps: AppBundleID = "net.ranode.human-gate-ops"
    public static let humanGateOpsSwift: AppBundleID = "net.ranode.human-gate-ops"
    public static let hwpxViewer: AppBundleID = "net.ranode.hwpx-viewer"
    public static let hwpxViewerSwift: AppBundleID = "net.ranode.hwpx-viewer"
    public static let iconPreviewComposer: AppBundleID = "net.ranode.icon-preview-composer.viewer"
    public static let iconPreviewComposerSwift: AppBundleID = "net.ranode.icon-preview-composer.viewer"
    public static let identityDocumentRegistry: AppBundleID = "net.ranode.identity-document-registry"
    public static let identityDocumentRegistrySwift: AppBundleID = "net.ranode.identity-document-registry"
    public static let identityInstallLedger: AppBundleID = "net.ranode.agent-identity-install-ledger"
    public static let identityInstallLedgerSwift: AppBundleID = "net.ranode.agent-identity-install-ledger"
    public static let imageGeneration: AppBundleID = "net.ranode.imagegeneration"
    public static let imageGenerationStudio: AppBundleID = "net.ranode.imagegenerationstudio"
    public static let imageGenerationStudioSwift: AppBundleID = "net.ranode.imagegenerationstudio"
    public static let imageGenerationSwift: AppBundleID = "net.ranode.imagegeneration"
    public static let infisical: AppBundleID = "net.ranode.infisical"
    public static let infisicalCerts: AppBundleID = "net.ranode.infisicalcerts"
    public static let infisicalCertsSwift: AppBundleID = "net.ranode.infisicalcerts"
    public static let infisicalSwift: AppBundleID = "net.ranode.infisical"
    public static let infraAlertReceiver: AppBundleID = "net.ranode.infra-alert-receiver"
    public static let infraAlertReceiverSwift: AppBundleID = "net.ranode.infra-alert-receiver"
    public static let infraOpsDashboard: AppBundleID = "net.ranode.infra-ops-dashboard"
    public static let infraOpsDashboardSwift: AppBundleID = "net.ranode.infra-ops-dashboard"
    public static let ipadClipboardHistory: AppBundleID = "net.ranode.ipad-clipboard-history"
    public static let iptimeRouter: AppBundleID = "net.ranode.iptime-router"
    public static let iptimeRouterSwift: AppBundleID = "net.ranode.iptime-router"
    public static let jointCertificateManager: AppBundleID = "net.ranode.joint-certificate-manager"
    public static let jointCertificateManagerSwift: AppBundleID = "net.ranode.joint-certificate-manager"
    public static let jsonInspector: AppBundleID = "net.ranode.json-inspector"
    public static let jsonInspectorSwift: AppBundleID = "net.ranode.json-inspector"
    public static let keepAwake: AppBundleID = "net.ranode.keep-awake"
    public static let keepAwakeSwift: AppBundleID = "net.ranode.keep-awake"
    public static let keyboardCodingTyper: AppBundleID = "net.ranode.keyboard-coding-typer"
    public static let keyboardCodingTyperSwift: AppBundleID = "net.ranode.keyboard-coding-typer"
    public static let keyboardSettingsManager: AppBundleID = "net.ranode.keyboard-settings-manager"
    public static let keyboardTyper: AppBundleID = "net.ranode.keyboardtyper"
    public static let keyboardTyperSwift: AppBundleID = "net.ranode.keyboardtyper"
    public static let knowledgeBaseWiki: AppBundleID = "net.ranode.memo-citation-ledger"
    public static let knowledgeBaseWikiSwift: AppBundleID = "net.ranode.memo-citation-ledger"
    public static let knowledgeGraphStudio: AppBundleID = "net.ranode.knowledgegraphstudio"
    public static let knowledgeGraphStudioSwift: AppBundleID = "net.ranode.knowledgegraphstudio"
    public static let kubeStatusUi: AppBundleID = "net.ranode.kube-status-ui"
    public static let kubeStatusUiSwift: AppBundleID = "net.ranode.kube-status-ui"
    public static let kubernetesEmulatorFleetController: AppBundleID = "net.ranode.kubernetes-emulator-fleet-controller"
    public static let kubernetesEmulatorFleetControllerSwift: AppBundleID = "net.ranode.kubernetes-emulator-fleet-controller"
    public static let laravelArchitectureGraph: AppBundleID = "net.ranode.laravel-architecture-graph"
    public static let laravelArchitectureGraphSwift: AppBundleID = "net.ranode.laravel-architecture-graph"
    public static let laravelBackendTestGraph: AppBundleID = "net.ranode.laravel-backend-test-graph"
    public static let laravelBackendTestGraphSwift: AppBundleID = "net.ranode.laravel-backend-test-graph"
    public static let laravelBrowserE2eManager: AppBundleID = "net.ranode.laravel-browser-e2e-manager"
    public static let laravelBrowserE2eManagerSwift: AppBundleID = "net.ranode.laravel-browser-e2e-manager"
    public static let laravelFrontendInspectGraph: AppBundleID = "net.ranode.laravel-frontend-inspect-graph"
    public static let laravelFrontendInspectGraphSwift: AppBundleID = "net.ranode.laravel-frontend-inspect-graph"
    public static let laravelFrontendTestGraph: AppBundleID = "net.ranode.laravel-frontend-test-graph"
    public static let laravelFrontendTestGraphSwift: AppBundleID = "net.ranode.laravel-frontend-test-graph"
    public static let laravelLocalDevelopmentSetup: AppBundleID = "net.ranode.laravel-local-development-setup"
    public static let laravelLocalDevelopmentSetupSwift: AppBundleID = "net.ranode.laravel-local-development-setup"
    public static let laravelOpsMonitor: AppBundleID = "net.ranode.laravel-ops-monitor"
    public static let laravelOpsMonitorSwift: AppBundleID = "net.ranode.laravel-ops-monitor"
    public static let lectureMaterials: AppBundleID = "net.ranode.lecture-materials"
    public static let lectureMaterialsSwift: AppBundleID = "net.ranode.lecture-materials"
    public static let lectureProductionStudio: AppBundleID = "net.ranode.lecture-production-studio"
    public static let lectureProductionStudioSwift: AppBundleID = "net.ranode.lecture-production-studio"
    public static let lectureStudents: AppBundleID = "net.ranode.lecture-students"
    public static let lectureStudentsSwift: AppBundleID = "net.ranode.lecture-students"
    public static let lectureTools: AppBundleID = "net.ranode.lecture-tools"
    public static let lectureToolsSwift: AppBundleID = "net.ranode.lecture-tools"
    public static let licenseEntitlementManager: AppBundleID = "net.ranode.license-entitlement-manager"
    public static let licenseEntitlementManagerSwift: AppBundleID = "net.ranode.license-entitlement-manager"
    public static let linuxServerOperationsManager: AppBundleID = "net.ranode.linuxserveroperationsmanager"
    public static let linuxServerOperationsManagerSwift: AppBundleID = "net.ranode.linuxserveroperationsmanager"
    public static let liveTranslate: AppBundleID = "net.ranode.livetranslateswift"
    public static let liveTranslateSwift: AppBundleID = "net.ranode.livetranslateswift"
    public static let llmPlaygroundIOS: AppBundleID = "net.ranode.llm-playground"
    public static let llmPlaygroundIos: AppBundleID = "net.ranode.llm-playground"
    public static let llmRouteManager: AppBundleID = "net.ranode.llmroutemanager"
    public static let llmRouteManagerSwift: AppBundleID = "net.ranode.llmroutemanager"
    public static let llmWorkflowStudio: AppBundleID = "net.ranode.llmworkflowstudio"
    public static let llmWorkflowStudioSwift: AppBundleID = "net.ranode.llmworkflowstudio"
    public static let llmwikiEditor: AppBundleID = "net.ranode.llmwiki-editor"
    public static let llmwikiEditorSwift: AppBundleID = "net.ranode.llmwiki-editor"
    public static let localAccountPrivilegeManager: AppBundleID = "net.ranode.local-account-privilege-manager"
    public static let localAccountPrivilegeManagerSwift: AppBundleID = "net.ranode.local-account-privilege-manager"
    public static let localSecrets: AppBundleID = "net.ranode.local-secrets"
    public static let localSecretsSwift: AppBundleID = "net.ranode.local-secrets"
    public static let localVideoPlayer: AppBundleID = "net.ranode.local-video-player"
    public static let localVideoPlayerSwift: AppBundleID = "net.ranode.local-video-player"
    public static let loopFeedback: AppBundleID = "net.ranode.loop-feedback"
    public static let loopFeedbackSwift: AppBundleID = "net.ranode.loop-feedback"
    public static let macAiInstaller: AppBundleID = "net.ranode.macaiinstaller"
    public static let macAiInstallerSwift: AppBundleID = "net.ranode.macaiinstaller"
    public static let macAndroidLink: AppBundleID = "net.ranode.mac-android-link"
    public static let macAndroidLinkSwift: AppBundleID = "net.ranode.mac-android-link"
    public static let macInstaller: AppBundleID = "net.ranode.macinstaller"
    public static let macInstallerSwift: AppBundleID = "net.ranode.macinstaller"
    public static let macMachineBackupManager: AppBundleID = "net.ranode.mac-machine-backup-manager"
    public static let macMachineBackupManagerSwift: AppBundleID = "net.ranode.mac-machine-backup-manager"
    public static let macPerformanceMonitor: AppBundleID = "net.ranode.macperformancemonitor"
    public static let macPerformanceMonitorSwift: AppBundleID = "net.ranode.macperformancemonitor"
    public static let macPermissionAdministrator: AppBundleID = "net.ranode.mac-permission-administrator"
    public static let macPermissionAdministratorSwift: AppBundleID = "net.ranode.mac-permission-administrator"
    public static let macPermissionMonitor: AppBundleID = "net.ranode.mac-permission-monitor"
    public static let macPermissionMonitorSwift: AppBundleID = "net.ranode.mac-permission-monitor"
    public static let macPermissionsManager: AppBundleID = "net.ranode.macpermissionsmanager"
    public static let macPermissionsManagerSwift: AppBundleID = "net.ranode.macpermissionsmanager"
    public static let macRecorder: AppBundleID = "net.ranode.macrecorder"
    public static let macRecorderSwift: AppBundleID = "net.ranode.macrecorder"
    public static let macRemoteDesktop: AppBundleID = "net.ranode.macremotedesktop"
    public static let macRemoteDesktopSwift: AppBundleID = "net.ranode.macremotedesktop"
    public static let macScreenSharingClient: AppBundleID = "net.ranode.mac-screen-sharing-client"
    public static let macScreenSharingClientSwift: AppBundleID = "net.ranode.mac-screen-sharing-client"
    public static let mailsmstester: AppBundleID = "net.ranode.mailsmstester"
    public static let mailsmstesterSwift: AppBundleID = "net.ranode.mailsmstester"
    public static let mcpManager: AppBundleID = "net.ranode.mcpmanager"
    public static let mcpManagerSwift: AppBundleID = "net.ranode.mcpmanager"
    public static let mdLineageViewer: AppBundleID = "net.ranode.md-lineage-viewer"
    public static let mdLineageViewerSwift: AppBundleID = "net.ranode.md-lineage-viewer"
    public static let meaningSpacetime: AppBundleID = "net.ranode.meaning-spacetime"
    public static let meaningSpacetimeSwift: AppBundleID = "net.ranode.meaning-spacetime"
    public static let mediaPromptLedger: AppBundleID = "net.ranode.media-prompt-ledger"
    public static let mediaPromptLedgerSwift: AppBundleID = "net.ranode.media-prompt-ledger"
    public static let mem0Controller: AppBundleID = "net.ranode.mem0-controller"
    public static let mem0ControllerSwift: AppBundleID = "net.ranode.mem0-controller"
    public static let memoVault: AppBundleID = "net.ranode.memo-vault"
    public static let memoVaultIOS: AppBundleID = "net.ranode.memo-vault"
    public static let memoVaultIos: AppBundleID = "net.ranode.memo-vault"
    public static let memoVaultSwift: AppBundleID = "net.ranode.memo-vault"
    public static let memoryCoreCockpit: AppBundleID = "net.ranode.memory-core-cockpit"
    public static let memoryCoreCockpitSwift: AppBundleID = "net.ranode.memory-core-cockpit"
    public static let menuFold: AppBundleID = "net.ranode.menu-fold"
    public static let menuFoldSwift: AppBundleID = "net.ranode.menu-fold"
    public static let menubarBelowNotch: AppBundleID = "net.ranode.menubar-below-notch"
    public static let menubarBelowNotchSwift: AppBundleID = "net.ranode.menubar-below-notch"
    public static let mermaidViewer: AppBundleID = "net.ranode.mermaid-viewer"
    public static let mermaidViewerSwift: AppBundleID = "net.ranode.mermaid-viewer"
    public static let modelConvert: AppBundleID = "net.ranode.modelconvert"
    public static let modelConvertSwift: AppBundleID = "net.ranode.modelconvert"
    public static let moneySourceGovernmentProgramLookup: AppBundleID = "net.ranode.money-source-government-program-lookup"
    public static let moneySourceGovernmentProgramLookupSwift: AppBundleID = "net.ranode.money-source-government-program-lookup"
    public static let moneySourceLoanLookup: AppBundleID = "net.ranode.money-source-loan-lookup"
    public static let moneySourceLoanLookupSwift: AppBundleID = "net.ranode.money-source-loan-lookup"
    public static let moneySourceSubsidyLookup: AppBundleID = "net.ranode.money-source-subsidy-lookup"
    public static let moneySourceSubsidyLookupSwift: AppBundleID = "net.ranode.money-source-subsidy-lookup"
    public static let moneySourceTaxBenefitLookup: AppBundleID = "net.ranode.money-source-tax-benefit-lookup"
    public static let moneySourceTaxBenefitLookupSwift: AppBundleID = "net.ranode.money-source-tax-benefit-lookup"
    public static let monorepoGitForge: AppBundleID = "net.ranode.monorepo-git-forge"
    public static let monorepoGitForgeSwift: AppBundleID = "net.ranode.monorepo-git-forge"
    public static let mounter: AppBundleID = "net.ranode.mounter"
    public static let mounterSwift: AppBundleID = "net.ranode.mounter"
    public static let multiformatImageViewer: AppBundleID = "net.ranode.multiformat-image-viewer"
    public static let multiformatImageViewerSwift: AppBundleID = "net.ranode.multiformat-image-viewer"
    public static let nasCutoffTransferManager: AppBundleID = "net.ranode.nas-cutoff-transfer-manager"
    public static let nasCutoffTransferManagerSwift: AppBundleID = "net.ranode.nas-cutoff-transfer-manager"
    public static let netShareClient: AppBundleID = "net.ranode.net-share-client"
    public static let netShareClientIOS: AppBundleID = "kr.internal.netshare.client"
    public static let netShareClientIos: AppBundleID = "kr.internal.netshare.client"
    public static let netShareClientSwift: AppBundleID = "net.ranode.net-share-client"
    public static let networkDebugConsole: AppBundleID = "net.ranode.networkdebugconsole"
    public static let networkDebugConsoleSwift: AppBundleID = "net.ranode.networkdebugconsole"
    public static let networkFailoverManager: AppBundleID = "net.ranode.network-failover-manager"
    public static let networkFailoverManagerSwift: AppBundleID = "net.ranode.network-failover-manager"
    public static let networkTopologyMap: AppBundleID = "net.ranode.network-topology-map"
    public static let networkTopologyMapSwift: AppBundleID = "net.ranode.network-topology-map"
    public static let neuralPhaseInspector: AppBundleID = "net.ranode.neural-phase-inspector"
    public static let neuralPhaseInspectorSwift: AppBundleID = "net.ranode.neural-phase-inspector"
    public static let oauthTokenVault: AppBundleID = "net.ranode.oauthtokenvault"
    public static let oauthTokenVaultSwift: AppBundleID = "net.ranode.oauthtokenvault"
    public static let onlineOpportunityRadar: AppBundleID = "net.ranode.online-opportunity-radar"
    public static let onlineOpportunityRadarSwift: AppBundleID = "net.ranode.online-opportunity-radar"
    public static let openSourceAppPublisher: AppBundleID = "net.ranode.open-source-app-publisher"
    public static let openSourceAppPublisherSwift: AppBundleID = "net.ranode.open-source-app-publisher"
    public static let opencodexAccountManager: AppBundleID = "net.ranode.opencodex-account-manager"
    public static let opencodexAccountManagerSwift: AppBundleID = "net.ranode.opencodex-account-manager"
    public static let opencodexDashboard: AppBundleID = "net.ranode.opencodex-dashboard"
    public static let opencodexDashboardSwift: AppBundleID = "net.ranode.opencodex-dashboard"
    public static let opportunityAnalyzer: AppBundleID = "net.ranode.opportunity-analyzer"
    public static let opportunityAnalyzerSwift: AppBundleID = "net.ranode.opportunity-analyzer"
    public static let opportunityCrawler: AppBundleID = "net.ranode.opportunity-crawler"
    public static let opportunityCrawlerSwift: AppBundleID = "net.ranode.opportunity-crawler"
    public static let outputArchiveManager: AppBundleID = "net.ranode.output-archive-manager"
    public static let outputArchiveManagerSwift: AppBundleID = "net.ranode.output-archive-manager"
    public static let packageWikiBridge: AppBundleID = "net.ranode.package-wiki-bridge"
    public static let packageWikiBridgeSwift: AppBundleID = "net.ranode.package-wiki-bridge"
    public static let partyRoomReleaseManager: AppBundleID = "net.ranode.party-room-release-manager"
    public static let partyRoomReleaseManagerSwift: AppBundleID = "net.ranode.party-room-release-manager"
    public static let pathCliHealth: AppBundleID = "net.ranode.path-cli-health"
    public static let pathCliHealthSwift: AppBundleID = "net.ranode.path-cli-health"
    public static let pdfEditor: AppBundleID = "net.ranode.pdf-editor"
    public static let pdfEditorIOS: AppBundleID = "net.ranode.pdf-editor-ipad"
    public static let pdfEditorIos: AppBundleID = "net.ranode.pdf-editor-ipad"
    public static let pdfEditorSwift: AppBundleID = "net.ranode.pdf-editor"
    public static let personalLedger: AppBundleID = "net.ranode.personal-ledger"
    public static let personalLedgerSwift: AppBundleID = "net.ranode.personal-ledger"
    public static let pgMerchantOps: AppBundleID = "net.ranode.pg-merchant-ops"
    public static let pgMerchantOpsSwift: AppBundleID = "net.ranode.pg-merchant-ops"
    public static let photoClassificationMap: AppBundleID = "net.ranode.photo-classification-map"
    public static let photoClassificationMapSwift: AppBundleID = "net.ranode.photo-classification-map"
    public static let photoFaceIndex: AppBundleID = "net.ranode.photo-face-index"
    public static let photoFaceIndexSwift: AppBundleID = "net.ranode.photo-face-index"
    public static let photoOriginLedger: AppBundleID = "net.ranode.photo-origin-ledger"
    public static let photoOriginLedgerSwift: AppBundleID = "net.ranode.photo-origin-ledger"
    public static let photoParticipants: AppBundleID = "net.ranode.photo-participants"
    public static let photoParticipantsSwift: AppBundleID = "net.ranode.photo-participants"
    public static let photoPicks: AppBundleID = "net.ranode.photo-picks"
    public static let photoPicksSwift: AppBundleID = "net.ranode.photo-picks"
    public static let photoReachDelivery: AppBundleID = "net.ranode.photo-reach-delivery"
    public static let photoReachDeliverySwift: AppBundleID = "net.ranode.photo-reach-delivery"
    public static let photoWorkStatus: AppBundleID = "net.ranode.photo-work-status"
    public static let photoWorkStatusSwift: AppBundleID = "net.ranode.photo-work-status"
    public static let pikvmConsole: AppBundleID = "net.ranode.pikvm-console"
    public static let pikvmConsoleSwift: AppBundleID = "net.ranode.pikvm-console"
    public static let pimAgenda: AppBundleID = "net.ranode.pimagenda"
    public static let pimAgendaSwift: AppBundleID = "net.ranode.pimagenda"
    public static let pimCalendar: AppBundleID = "net.ranode.pimcalendar"
    public static let pimCalendarIOS: AppBundleID = "net.ranode.pim-calendar"
    public static let pimCalendarIos: AppBundleID = "net.ranode.pim-calendar"
    public static let pimCalendarSwift: AppBundleID = "net.ranode.pimcalendar"
    public static let pimContacts: AppBundleID = "net.ranode.pimcontacts"
    public static let pimContactsSwift: AppBundleID = "net.ranode.pimcontacts"
    public static let pimMail: AppBundleID = "net.ranode.pimmail"
    public static let pimMailAutomation: AppBundleID = "net.ranode.pim-mail-automation"
    public static let pimMailAutomationSwift: AppBundleID = "net.ranode.pim-mail-automation"
    public static let pimMailSwift: AppBundleID = "net.ranode.pimmail"
    public static let pimNotes: AppBundleID = "net.ranode.pimnotes"
    public static let pimNotesSwift: AppBundleID = "net.ranode.pimnotes"
    public static let pimPersonProfile: AppBundleID = "net.ranode.pim-person-profile"
    public static let pimPersonProfileSwift: AppBundleID = "net.ranode.pim-person-profile"
    public static let pimSearch: AppBundleID = "net.ranode.pimsearch"
    public static let pimSearchSwift: AppBundleID = "net.ranode.pimsearch"
    public static let pimTodo: AppBundleID = "net.ranode.pimtodo"
    public static let pimTodoSwift: AppBundleID = "net.ranode.pimtodo"
    public static let pimWorkspace: AppBundleID = "net.ranode.pim-workspace"
    public static let pimWorkspaceSwift: AppBundleID = "net.ranode.pim-workspace"
    public static let pipelineProfiler: AppBundleID = "net.ranode.pipelineprofiler"
    public static let pipelineProfilerSwift: AppBundleID = "net.ranode.pipelineprofiler"
    public static let pipelineStatusUi: AppBundleID = "net.ranode.pipeline-status-ui"
    public static let pipelineStatusUiSwift: AppBundleID = "net.ranode.pipeline-status-ui"
    public static let playbookInstaller: AppBundleID = "net.ranode.playbookinstaller"
    public static let playbookInstallerSwift: AppBundleID = "net.ranode.playbookinstaller"
    public static let pptxEditor: AppBundleID = "net.ranode.pptx-editor"
    public static let pptxEditorSwift: AppBundleID = "net.ranode.pptx-editor"
    public static let productCompetitorPricing: AppBundleID = "net.ranode.product-competitor-pricing"
    public static let productCompetitorPricingSwift: AppBundleID = "net.ranode.product-competitor-pricing"
    public static let productDefinitionWorkspace: AppBundleID = "net.ranode.productdefinitionworkspace"
    public static let productDefinitionWorkspaceSwift: AppBundleID = "net.ranode.productdefinitionworkspace"
    public static let productEvaluationStudio: AppBundleID = "net.ranode.productevaluationstudio"
    public static let productEvaluationStudioSwift: AppBundleID = "net.ranode.productevaluationstudio"
    public static let productShowcaseStudio: AppBundleID = "net.ranode.product-showcase-studio"
    public static let productShowcaseStudioSwift: AppBundleID = "net.ranode.product-showcase-studio"
    public static let proxmoxMonitorIOS: AppBundleID = "net.ranode.proxmox-ipad"
    public static let proxmoxMonitorIos: AppBundleID = "net.ranode.proxmox-ipad"
    public static let proxmoxOperationsManager: AppBundleID = "net.ranode.proxmoxoperationsmanager"
    public static let proxmoxOperationsManagerSwift: AppBundleID = "net.ranode.proxmoxoperationsmanager"
    public static let rasterImageEditor: AppBundleID = "net.ranode.raster-image-editor"
    public static let rasterImageEditorSwift: AppBundleID = "net.ranode.raster-image-editor"
    public static let rawLibrary: AppBundleID = "net.ranode.raw-library"
    public static let rawLibrarySwift: AppBundleID = "net.ranode.raw-library"
    public static let receiptOcr: AppBundleID = "net.ranode.receipt-ocr"
    public static let receiptOcrSwift: AppBundleID = "net.ranode.receipt-ocr"
    public static let recordTimelabsMono: AppBundleID = "net.ranode.record-timelabs-mono"
    public static let referenceBoard: AppBundleID = "net.ranode.refboard"
    public static let referenceBoardSwift: AppBundleID = "net.ranode.refboard"
    public static let remoteAccessMac: AppBundleID = "net.ranode.remoteaccessmac"
    public static let remoteAccessMacSwift: AppBundleID = "net.ranode.remoteaccessmac"
    public static let remoteDockerManager: AppBundleID = "net.ranode.remote-docker-manager"
    public static let remoteDockerManagerSwift: AppBundleID = "net.ranode.remote-docker-manager"
    public static let remoteMacBottleneckAnalyzer: AppBundleID = "net.ranode.remote-mac-bottleneck-analyzer"
    public static let remoteMacBottleneckAnalyzerSwift: AppBundleID = "net.ranode.remote-mac-bottleneck-analyzer"
    public static let remoteServerTerminalManager: AppBundleID = "net.ranode.remote-server-terminal-manager"
    public static let remoteServerTerminalManagerSwift: AppBundleID = "net.ranode.remote-server-terminal-manager"
    public static let repoCiOverheadAuditor: AppBundleID = "net.ranode.repo-ci-overhead-auditor"
    public static let repoCiOverheadAuditorSwift: AppBundleID = "net.ranode.repo-ci-overhead-auditor"
    public static let repoFleetManager: AppBundleID = "net.ranode.repo-fleet-manager"
    public static let repoFleetManagerSwift: AppBundleID = "net.ranode.repo-fleet-manager"
    public static let repositoryReadinessGovernor: AppBundleID = "net.ranode.repository-readiness-governor"
    public static let repositoryReadinessGovernorSwift: AppBundleID = "net.ranode.repository-readiness-governor"
    public static let researchInbox: AppBundleID = "net.ranode.researchinbox"
    public static let researchInboxSwift: AppBundleID = "net.ranode.researchinbox"
    public static let rightclick: AppBundleID = "net.ranode.rightclick"
    public static let rightclickSwift: AppBundleID = "net.ranode.rightclick"
    public static let scheduler: AppBundleID = "net.ranode.scheduler"
    public static let schedulerSwift: AppBundleID = "net.ranode.scheduler"
    public static let screenOcr: AppBundleID = "net.ranode.screen-ocr"
    public static let screenOcrSwift: AppBundleID = "net.ranode.screen-ocr"
    public static let screenshot: AppBundleID = "net.ranode.screenshotswift"
    public static let screenshotIOS: AppBundleID = "net.ranode.screenshot-studio"
    public static let screenshotIos: AppBundleID = "net.ranode.screenshot-studio"
    public static let screenshotSwift: AppBundleID = "net.ranode.screenshotswift"
    public static let searchAgentMenubar: AppBundleID = "net.ranode.search-agent-menubar"
    public static let searchAgentMenubarSwift: AppBundleID = "net.ranode.search-agent-menubar"
    public static let servicePageCaptureIndex: AppBundleID = "net.ranode.service-page-capture-index"
    public static let servicePageCaptureIndexSwift: AppBundleID = "net.ranode.service-page-capture-index"
    public static let serviceTermsManager: AppBundleID = "net.ranode.service-terms-manager"
    public static let serviceTermsManagerSwift: AppBundleID = "net.ranode.service-terms-manager"
    public static let sessionKeepAlive: AppBundleID = "net.ranode.session-keep-alive"
    public static let sessionKeepAliveSwift: AppBundleID = "net.ranode.session-keep-alive"
    public static let sidecarTablet: AppBundleID = "net.ranode.sidecartablet"
    public static let sidecarTabletSwift: AppBundleID = "net.ranode.sidecartablet"
    public static let skillGenerator: AppBundleID = "net.ranode.skill-generator"
    public static let skillGeneratorSwift: AppBundleID = "net.ranode.skill-generator"
    public static let socialConnectConsole: AppBundleID = "net.ranode.social-connect-console"
    public static let socialConnectConsoleSwift: AppBundleID = "net.ranode.social-connect-console"
    public static let socialDraft: AppBundleID = "net.ranode.socialdraft"
    public static let socialDraftSwift: AppBundleID = "net.ranode.socialdraft"
    public static let soundSourceInspector: AppBundleID = "net.ranode.soundsourceinspector"
    public static let soundSourceInspectorSwift: AppBundleID = "net.ranode.soundsourceinspector"
    public static let sparkleUpdateStudio: AppBundleID = "net.ranode.sparkleupdatestudio"
    public static let sparkleUpdateStudioSwift: AppBundleID = "net.ranode.sparkleupdatestudio"
    public static let spriteAnimator: AppBundleID = "net.ranode.sprite-animator"
    public static let spriteAnimatorSwift: AppBundleID = "net.ranode.sprite-animator"
    public static let spriteForge: AppBundleID = "net.ranode.sprite-forge"
    public static let spriteForgeSwift: AppBundleID = "net.ranode.sprite-forge"
    public static let sqliteQueryRunner: AppBundleID = "net.ranode.sqlite-query-runner"
    public static let sqliteQueryRunnerSwift: AppBundleID = "net.ranode.sqlite-query-runner"
    public static let sshTerminalIOS: AppBundleID = "net.ranode.ssh-terminal-ipad"
    public static let sshTerminalIos: AppBundleID = "net.ranode.ssh-terminal-ipad"
    public static let starMap: AppBundleID = "net.ranode.starmap"
    public static let starMapIOS: AppBundleID = "net.ranode.starmap-ipad"
    public static let starMapIos: AppBundleID = "net.ranode.starmap-ipad"
    public static let starMapSwift: AppBundleID = "net.ranode.starmap"
    public static let storeAppBatchUpgrader: AppBundleID = "net.ranode.store-app-batch-upgrader"
    public static let storeAppBatchUpgraderSwift: AppBundleID = "net.ranode.store-app-batch-upgrader"
    public static let storeInventoryManager: AppBundleID = "net.ranode.store-inventory-manager"
    public static let storeInventoryManagerSwift: AppBundleID = "net.ranode.store-inventory-manager"
    public static let subdomainSession: AppBundleID = "net.ranode.subdomainsession"
    public static let subdomainSessionSwift: AppBundleID = "net.ranode.subdomainsession"
    public static let subscriptionLedger: AppBundleID = "net.ranode.subscription-ledger"
    public static let subscriptionLedgerSwift: AppBundleID = "net.ranode.subscription-ledger"
    public static let swiftAppDevtoolsHub: AppBundleID = "net.ranode.swift-app-devtools-hub"
    public static let swiftAppDevtoolsHubSwift: AppBundleID = "net.ranode.swift-app-devtools-hub"
    public static let swiftAppRouter: AppBundleID = "net.ranode.swiftapprouter"
    public static let swiftAppRouterSwift: AppBundleID = "net.ranode.swiftapprouter"
    public static let swiftLibraryKitManager: AppBundleID = "net.ranode.swiftlibrarykitmanager"
    public static let swiftLibraryKitManagerSwift: AppBundleID = "net.ranode.swiftlibrarykitmanager"
    public static let swiftViewDevSelector: AppBundleID = "net.ranode.swiftviewdevselector"
    public static let swiftViewDevSelectorSwift: AppBundleID = "net.ranode.swiftviewdevselector"
    public static let swiftkitMigration: AppBundleID = "net.ranode.swiftkit-migration"
    public static let swiftkitMigrationSwift: AppBundleID = "net.ranode.swiftkit-migration"
    public static let syncManager: AppBundleID = "net.ranode.sync-manager"
    public static let syncManagerSwift: AppBundleID = "net.ranode.sync-manager"
    public static let synologyStorageManager: AppBundleID = "net.ranode.synology-storage-manager"
    public static let synologyStorageManagerSwift: AppBundleID = "net.ranode.synology-storage-manager"
    public static let systemPorts: AppBundleID = "net.ranode.systemports"
    public static let systemPortsSwift: AppBundleID = "net.ranode.systemports"
    public static let telemetryDashboard: AppBundleID = "net.ranode.telemetry-dashboard"
    public static let telemetryDashboardSwift: AppBundleID = "net.ranode.telemetry-dashboard"
    public static let terraformInfrastructureControl: AppBundleID = "net.ranode.terraform-infrastructure-control"
    public static let terraformInfrastructureControlSwift: AppBundleID = "net.ranode.terraform-infrastructure-control"
    public static let tokenUsageMenubar: AppBundleID = "net.ranode.llm-token-status-manager"
    public static let tokenUsageMenubarSwift: AppBundleID = "net.ranode.llm-token-status-manager"
    public static let tracelite: AppBundleID = "net.ranode.tracelite"
    public static let traceliteSwift: AppBundleID = "net.ranode.tracelite"
    public static let trendDeck: AppBundleID = "net.ranode.trenddeck"
    public static let trendDeckSwift: AppBundleID = "net.ranode.trenddeck"
    public static let truenasStorageManager: AppBundleID = "net.ranode.truenas-storage-manager"
    public static let truenasStorageManagerSwift: AppBundleID = "net.ranode.truenas-storage-manager"
    public static let uiPrototypeHarness: AppBundleID = "net.ranode.ui-prototype-harness"
    public static let uiPrototypeHarnessSwift: AppBundleID = "net.ranode.ui-prototype-harness"
    public static let unusedAssetInspector: AppBundleID = "net.ranode.unused-asset-inspector"
    public static let unusedAssetInspectorSwift: AppBundleID = "net.ranode.unused-asset-inspector"
    public static let unusedViewInspector: AppBundleID = "net.ranode.unused-view-inspector"
    public static let unusedViewInspectorSwift: AppBundleID = "net.ranode.unused-view-inspector"
    public static let usbIsoBurnner: AppBundleID = "net.ranode.usbisoburner"
    public static let usbIsoBurnnerSwift: AppBundleID = "net.ranode.usbisoburner"
    public static let vaultwardenClient: AppBundleID = "net.ranode.vaultwarden-client"
    public static let vaultwardenClientSwift: AppBundleID = "net.ranode.vaultwarden-client"
    public static let vibecodeCustomCli: AppBundleID = "net.ranode.vibecodecli"
    public static let vibecodeCustomCliSwift: AppBundleID = "net.ranode.vibecodecli"
    public static let virtualBuyerJourneyImprovementStudio: AppBundleID = "net.ranode.virtual-buyer-journey-improvement-studio"
    public static let virtualBuyerJourneyImprovementStudioSwift: AppBundleID = "net.ranode.virtual-buyer-journey-improvement-studio"
    public static let virtualBuyerJourneySimCore: AppBundleID = "net.ranode.virtual-buyer-journey-sim-core"
    public static let virtualBuyerJourneySimulatorRunner: AppBundleID = "net.ranode.virtual-buyer-journey-simulator-runner"
    public static let virtualBuyerJourneySimulatorRunnerSwift: AppBundleID = "net.ranode.virtual-buyer-journey-simulator-runner"
    public static let virtualBuyerJourneySimulatorStudio: AppBundleID = "net.ranode.virtual-buyer-journey-simulator-studio"
    public static let virtualBuyerJourneySimulatorStudioSwift: AppBundleID = "net.ranode.virtual-buyer-journey-simulator-studio"
    public static let voiceScribe: AppBundleID = "net.ranode.voicescribe"
    public static let voiceScribeSwift: AppBundleID = "net.ranode.voicescribe"
    public static let volumeController: AppBundleID = "net.ranode.volume-controller"
    public static let volumeControllerSwift: AppBundleID = "net.ranode.volume-controller"
    public static let vpnWireguard: AppBundleID = "net.ranode.wireguard"
    public static let vpnWireguardIOS: AppBundleID = "net.ranode.wireguard.ios"
    public static let vpnWireguardIos: AppBundleID = "net.ranode.wireguard.ios"
    public static let vpnWireguardSwift: AppBundleID = "net.ranode.wireguard"
    public static let vscodeExtensionRunawayMonitor: AppBundleID = "net.ranode.vscodeextensionrunawaymonitor"
    public static let vscodeExtensionRunawayMonitorSwift: AppBundleID = "net.ranode.vscodeextensionrunawaymonitor"
    public static let walkthroughRecorder: AppBundleID = "net.ranode.walkthroughrecorder"
    public static let walkthroughRecorderSwift: AppBundleID = "net.ranode.walkthroughrecorder"
    public static let winHarbor: AppBundleID = "net.ranode.win-harbor"
    public static let winHarborSwift: AppBundleID = "net.ranode.win-harbor"
    public static let windowSnap: AppBundleID = "net.ranode.window-snap"
    public static let windowSnapSwift: AppBundleID = "net.ranode.window-snap"
    public static let wireguard: AppBundleID = "net.ranode.wireguard"
    public static let wordpressConsole: AppBundleID = "net.ranode.wordpress-console"
    public static let wordpressConsoleSwift: AppBundleID = "net.ranode.wordpress-console"
    public static let workflowSkillCompiler: AppBundleID = "net.ranode.workflow-skill-compiler"
    public static let workflowSkillCompilerSwift: AppBundleID = "net.ranode.workflow-skill-compiler"
    public static let worktreeLifecycle: AppBundleID = "net.ranode.worktree-lifecycle"
    public static let worktreeLifecycleSwift: AppBundleID = "net.ranode.worktree-lifecycle"
    public static let worktreeStatusUi: AppBundleID = "net.ranode.worktree-status-ui"
    public static let worktreeStatusUiSwift: AppBundleID = "net.ranode.worktree-status-ui"
    public static let xTrendDeck: AppBundleID = "net.ranode.x-trend-deck"
    public static let xTrendDeckSwift: AppBundleID = "net.ranode.x-trend-deck"
    public static let xlsxViewer: AppBundleID = "net.ranode.xlsx-viewer"
    public static let xlsxViewerSwift: AppBundleID = "net.ranode.xlsx-viewer"
}

extension AppIdentity {
    public typealias BundleID = AppBundleID

    public static let defaultBundleIDPrefix = AppBundleID.defaultPrefix

    public static func bundleID(for app: AppBundleID) -> String {
        app.rawValue
    }

    public static func bundleID(forSlug slug: String) -> String {
        AppBundleID.bundleID(forSlug: slug)
    }

    public var appBundleID: AppBundleID? {
        bundleIdentifier.map(AppBundleID.init(rawValue:))
    }

    public static var current: AppIdentity? {
        if let bundleId = Bundle.main.bundleIdentifier, !bundleId.isEmpty {
            if let infoURL = Bundle.main.url(forResource: "Info", withExtension: "plist"),
               let loaded = AppIdentity.load(plistURL: infoURL, sourceURL: Bundle.main.bundleURL) {
                return loaded
            }
            return AppIdentity(bundleIdentifier: bundleId, bundleName: Bundle.main.infoDictionary?["CFBundleName"] as? String)
        }
        let execURL = Bundle.main.executableURL ?? ProcessInfo.processInfo.arguments.first.map { URL(fileURLWithPath: $0) }
        return AppIdentityLocator.locate(executable: execURL)
    }

    public static var currentBundleID: String? {
        Bundle.main.bundleIdentifier ?? current?.bundleIdentifier
    }
}
