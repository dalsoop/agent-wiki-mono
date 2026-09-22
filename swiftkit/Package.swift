// swift-tools-version: 6.1
import PackageDescription

// 로컬 명령 메뉴바 앱들이 공유하는 작은 Kit 모음.
// 앱은 .package(path: "../../swiftkit") 로 참조한다.
let package = Package(
    name: "swiftkit",
    defaultLocalization: "en",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "PluginKit", targets: ["PluginKit"]),
        .library(name: "CommandKit", targets: ["CommandKit"]),
        .library(name: "JSONLJournalKit", targets: ["JSONLJournalKit"]),
        .library(name: "HostGovernanceKit", targets: ["HostGovernanceKit"]),
        .library(name: "CommandKitTesting", targets: ["CommandKitTesting"]),
        .library(name: "TestingAdapterKit", targets: ["TestingAdapterKit"]),
        .library(name: "StoreAssetKit", targets: ["StoreAssetKit"]),
        .library(name: "ContentAddressedAssetKit", targets: ["ContentAddressedAssetKit"]),
        .library(name: "WorkflowPipelineKit", targets: ["WorkflowPipelineKit"]),
        .library(name: "WorktreeKit", targets: ["WorktreeKit"]),
        .library(name: "PrivilegedKit", targets: ["PrivilegedKit"]),
        .library(name: "LocalizationKit", targets: ["LocalizationKit"]),
        .library(name: "AppErrorKit", targets: ["AppErrorKit"]),
        .library(name: "InstallerKit", targets: ["InstallerKit"]),
        .library(name: "AppScanKit", targets: ["AppScanKit"]),
        .library(name: "UnusedInspectionKit", targets: ["UnusedInspectionKit"]),
        .library(name: "MCPSupport", targets: ["MCPSupport"]),
        .library(name: "LaunchAtLoginKit", targets: ["LaunchAtLoginKit"]),
        // SMAppService.daemon 수명주기: ping 실패 시 unregister 후 register.
        .library(name: "PrivilegedHelperKit", targets: ["PrivilegedHelperKit"]),
        .library(name: "SingleInstanceKit", targets: ["SingleInstanceKit"]),
        .library(name: "StandardExtensionsKit", targets: ["StandardExtensionsKit"]),
        .library(name: "FastSQLiteKit", targets: ["FastSQLiteKit"]),
        .library(name: "ProcessLifecycleKit", targets: ["ProcessLifecycleKit"]),
        .library(name: "EphemeralLeaseKit", targets: ["EphemeralLeaseKit"]),
        .library(name: "NotificationKit", targets: ["NotificationKit"]),
        .library(name: "TerminalLauncherKit", targets: ["TerminalLauncherKit"]),
        .library(name: "InstallHealthKit", targets: ["InstallHealthKit"]),
        // GUI/CLI dual-entry hang 예방 (PATH→MacOS 금지, Helpers 계약, diagnose).
        .library(name: "DualEntryKit", targets: ["DualEntryKit"]),
        // App install/uninstall attaches coding-agent skills/agents (Orca-style surface).
        .library(name: "AgentSurfaceKit", targets: ["AgentSurfaceKit"]),
        // Host/Orca/Fleet doctor 공용: findings·scan·catalog·quarantine providers.
        .library(name: "DoctorContract", targets: ["DoctorContract"]),
        .library(name: "DoctorKit", targets: ["DoctorKit"]),
        .library(name: "ProcessAppIdentityKit", targets: ["ProcessAppIdentityKit"]),
        .library(name: "ProcessTerminationKit", targets: ["ProcessTerminationKit"]),
        .library(name: "PermissionKit", targets: ["PermissionKit"]),
        // AppKit 없는 코어 — CLI·데몬이 권한 상태만 읽을 때 쓴다(AppKit 을 끌어오면 CLI 가
        // 종료되지 않는다: dual-entry hang).
        .library(name: "PermissionCore", targets: ["PermissionCore"]),
        .library(name: "PermissionDialogKit", targets: ["PermissionDialogKit"]),
        .library(name: "InspectorKit", targets: ["InspectorKit"]),
        .library(name: "PromptKit", targets: ["PromptKit"]),
        .library(name: "InspectorState", targets: ["InspectorState"]),
        .library(name: "VaultwardenKit", targets: ["VaultwardenKit"]),
        .library(name: "VaultwardenClientKit", targets: ["VaultwardenClientKit"]),
        .library(name: "VaultwardenCryptoKit", targets: ["VaultwardenCryptoKit"]),
        .library(name: "VaultwardenBridgeKit", targets: ["VaultwardenBridgeKit"]),
        // Swift App Store 플랫폼 공용 모듈.
        .library(name: "AppWindowKit", targets: ["AppWindowKit"]),
        // 카탈로그형 창: 사이드바 + 목록 + 검사 칸. HSplitView 를 NavigationSplitView 안에
        // 겹치면 칸이 0폭으로 접힌다 — 이 키트가 그 셸을 한곳에 둔다.
        .library(name: "WindowChromeKit", targets: ["WindowChromeKit"]),
        // 함대 Dock 타일: 책상 허용 목록만 .regular, 나머지는 이 프로세스가 accessory.
        .library(name: "FleetDeskKit", targets: ["FleetDeskKit"]),
        // "설치본이 소스 대비 최신인지" 진단 도구. 업데이터가 아니다.
        // 자동업데이트는 swiftkit-sparkle(Sparkle)로 이관됐고, UpdateKit 모듈은 제거됐다.
        .library(name: "FreshnessKit", targets: ["FreshnessKit"]),
        .library(name: "StealthKit", targets: ["StealthKit"]),
        .library(name: "CDPCredentialFilterKit", targets: ["CDPCredentialFilterKit"]),
        .library(name: "ChromiumCDPEndpointKit", targets: ["ChromiumCDPEndpointKit"]),
        .library(name: "BehaviorSimulatorKit", targets: ["BehaviorSimulatorKit"]),
        // 파일 id — 내용은 안 읽고 size+mtime(+상대경로). DirectoryFingerprint 와 같은 철학.
        .library(name: "FileIdentityKit", targets: ["FileIdentityKit"]),
        // Swift 소스 주석/문자열 공백 치환. UTF-8 O(N). agent-lint-catalog · batch-codemod 공유.
        .library(name: "SwiftSourceKit", targets: ["SwiftSourceKit"]),
        // 앱 identity 및 Info.plist 해석 단일 정본. Foundation 만 의존.
        .library(name: "PackageIdentityKit", targets: ["PackageIdentityKit"]),
        // 범용 방향 그래프 엔진(도메인 무관). 위키·함대·세션 그래프의 공유 기판.
        .library(name: "GraphEngineKit", targets: ["GraphEngineKit"]),
        // 결정론적 force-directed 2D 레이아웃(순수 계산, 렌더러 무관). 외부 SPM 의존 없이
        // agent-fleet-map-swift·agent-session-replay-swift 가 공유(각 5·3 사용처, Grape 대체).
        .library(name: "GraphLayoutKit", targets: ["GraphLayoutKit"]),
        // CodeCity 규칙: 구역=모듈, 건물=클래스/페이지, 씀/안 씀은 자리 위 색.
        .library(name: "ArchitectureCityKit", targets: ["ArchitectureCityKit"]),
        .library(name: "ArchitectureCityUIKit", targets: ["ArchitectureCityUIKit"]),
        .library(name: "RadialGraphUIKit", targets: ["RadialGraphUIKit"]),
        .library(name: "TimelineGraphUIKit", targets: ["TimelineGraphUIKit"]),
        // Agent Wiki 원장 read 모델(파서 + 노드/엣지). GraphEngineKit 위의 도메인 층.
        .library(name: "WikiLedgerKit", targets: ["WikiLedgerKit"]),
        // 관계 인식 검색(GraphRAG) — 어떤 그래프 위에서든. GraphEngineKit 위.
        .library(name: "GraphRAGKit", targets: ["GraphRAGKit"]),
        // ErrorReportKit 삭제됨 (v3 M2: 의존 앱 0, import 0)
        .library(name: "TelemetryKit", targets: ["TelemetryKit"]),
        .library(name: "PhotoLedgerKit", targets: ["PhotoLedgerKit"]),
        .library(name: "MailSendKit", targets: ["MailSendKit"]),
        .library(name: "SettingsKit", targets: ["SettingsKit"]),
        .library(name: "SettingsUIKit", targets: ["SettingsUIKit"]),
        .library(name: "ClipboardActionUIKit", targets: ["ClipboardActionUIKit"]),
        .library(name: "NoticeBannerUIKit", targets: ["NoticeBannerUIKit"]),
        .library(name: "StatusIndicatorUIKit", targets: ["StatusIndicatorUIKit"]),
        .library(name: "CIPipelineUIKit", targets: ["CIPipelineUIKit"]),
        .library(name: "MenuBarPopoverUIKit", targets: ["MenuBarPopoverUIKit"]),
        .library(name: "MoneyInflowUIKit", targets: ["MoneyInflowUIKit"]),
        // 첫 실행 온보딩: 체크리스트 · 소개 카드 · 다단계 껍데기.
        .library(name: "OnboardingKit", targets: ["OnboardingKit"]),
        .library(name: "OnboardingUIKit", targets: ["OnboardingUIKit"]),
        .library(name: "GameAsset2DKit", targets: ["GameAsset2DKit"]),
        .library(name: "GameUIAssetKit", targets: ["GameUIAssetKit"]),
        .library(name: "GameUIRuntimeKit", targets: ["GameUIRuntimeKit"]),
        // 타깃만 있고 product 가 없으면 **앱이 import 할 수 없다** — 같은 패키지 안에서만
        // 보인다. 아래 넷이 그 상태였고, game-fantasy-territory-management 가 main 에서
        // 컴파일 불가였던 원인이다(2026-07-27 전수 빌드 스윕).
        .library(name: "GameSimulationStateKit", targets: ["GameSimulationStateKit"]),
        .library(name: "GameSimulationReducerKit", targets: ["GameSimulationReducerKit"]),
        .library(name: "GameSimulationProtocolKit", targets: ["GameSimulationProtocolKit"]),
        .library(name: "GameSimulationRuntimeKit", targets: ["GameSimulationRuntimeKit"]),
        // 방치형 오프라인 정산(경과 산출·재정산 방지·단조 누적·디바운스 저장).
        .library(name: "GameIdleSettlementKit", targets: ["GameIdleSettlementKit"]),
        .library(name: "GameUIRuntimeTreeKit", targets: ["GameUIRuntimeTreeKit"]),
        .library(name: "GameDepthEngineKit", targets: ["GameDepthEngineKit"]),
        .library(name: "GameDepthEngineControlKit", targets: ["GameDepthEngineControlKit"]),
        .executable(name: "game-ui-manifest-check", targets: ["GameUIManifestCheck"]),
        .library(name: "game-realtime-state-kit", targets: ["GameRealtimeStateKit"]),
        .library(name: "game-realtime-protocol-kit", targets: ["GameRealtimeProtocolKit"]),
        .library(name: "game-realtime-simulation-kit", targets: ["GameRealtimeSimulationKit"]),
        .library(name: "game-realtime-runtime-kit", targets: ["GameRealtimeRuntimeKit"]),
        .library(name: "game-realtime-engine-kit", targets: ["GameRealtimeEngineKit"]),
        .library(name: "game-realtime-debug-kit", targets: ["GameRealtimeDebugKit"]),
        .executable(name: "game-realtime-benchmark", targets: ["GameRealtimeBenchmark"]),
        .library(name: "PixelKit", targets: ["PixelKit"]),
        .library(name: "StateMirrorKit", targets: ["StateMirrorKit"]),
        .library(name: "OrchestratorClientKit", targets: ["OrchestratorClientKit"]),
        .library(name: "SeatReaderKit", targets: ["SeatReaderKit"]),
        .library(name: "SeatKit", targets: ["SeatKit"]),
        .library(name: "BacklogClientKit", targets: ["BacklogClientKit"]),
        .library(name: "BacklogKit", targets: ["BacklogKit"]),
        // 미리보기 통합 스튜디오 공유 엔진 및 UI 뷰포트
        .library(name: "PreviewEngineKit", targets: ["PreviewEngineKit"]),
        .library(name: "PreviewUIKit", targets: ["PreviewUIKit"]),
        // 상태 루트 단일 진입점 — env(SWIFT_APP_STATE_ROOT) 오버라이드 + 테스트 러너 자동
        // 격리 + 기본 홈. 앱이 상태 경로를 조립할 때 NSHomeDirectory()/
        // homeDirectoryForCurrentUser 를 직접 쓰지 않게 한다. StateMirrorKit 이 이 kit 을
        // 재사용해 isRunningUnderTest 를 합친다.
        .library(name: "StateRootKit", targets: ["StateRootKit"]),
        // 규칙을 텍스트 검출이 아니라 타입으로 세우는 자리. `PluginAction` 은 점 찍힌
        // 가상 명령을, `BorrowedStateRoot` 는 어댑터의 상태 루트 대입을 각각
        // 컴파일 단계에서 불가능하게 만든다 — 린트는 들어온 뒤에 짖고, 이건 못 들어온다.
        .library(name: "OrganKit", targets: ["OrganKit"]),
        // gujo 서버 주소 단일 설정 원장 — env 오버라이드 → endpoints.json → 내장 폴백 표.
        .library(name: "EndpointRouterKit", targets: ["EndpointRouterKit"]),
        .library(name: "LicenseCacheKit", targets: ["LicenseCacheKit"]),
        .library(name: "LicenseKeyWalletKit", targets: ["LicenseKeyWalletKit"]),
        .library(name: "LicenseStorageKit", targets: ["LicenseStorageKit"]),
        .library(name: "LicenseKit", targets: ["LicenseKit"]),
        .library(name: "LicenseAuthorityKit", targets: ["LicenseKit"]),
        .library(name: "EntitlementKit", targets: ["EntitlementKit"]),
        .library(name: "BusinessEntityKit", targets: ["BusinessEntityKit"]),
        // dal-* 장기 앱 공용: 테넌트 정규화·1/3인칭·함대 doctor(주장↔실측).
        .library(name: "DalKit", targets: ["DalKit"]),
        // 앱이 자기 계약을 임시 픽스처로 증명하는 표준 계약 — `self-test` 하위명령.
        // 실측 2026-08-11: 도구의 "성공" 보고가 9번 거짓이었다. 앱이 스스로 판정해야 한다.
        .library(name: "SelfTestKit", targets: ["SelfTestKit"]),
        // Laravel 지식 파이프라인(Graphify · architecture-graph · gujo wiki) StateMirror 종합.
        // 앱 품질 감사와 무관한 도메인 — 소비처가 URL/env/기본 경로를 주입한다.
        .library(name: "LaravelKnowledgePipelineKit", targets: ["LaravelKnowledgePipelineKit"]),
        // Git remote 정규화 + repo-sha256 identity의 단일 버전 구현.
        .library(name: "RepositoryIdentityKit", targets: ["RepositoryIdentityKit"]),
        // 메뉴바 상주 앱(*-bar-swift) 공용: 간격 새로고침 타이머 + StateMirror 게시 루프.
        .library(name: "MenuBarKit", targets: ["MenuBarKit"]),
        // databaseviewer-* 앱 공용: 드라이버 무관 코어(모델·store·SQLSafety·TSVParser·명령 러너 seam).
        .library(name: "DBViewerKit", targets: ["DBViewerKit"]),
        .library(name: "DBViewerUIKit", targets: ["DBViewerUIKit"]),
        // ssh/원격 실행 공용: ~/.ssh/config 파싱 + system-ssh 러너(CommandKit 기반).
        .library(name: "RemoteExecKit", targets: ["RemoteExecKit"]),
        .library(name: "SandboxKit", targets: ["SandboxKit"]),
        .library(name: "ArchitectureIRKit", targets: ["ArchitectureIRKit"]),
        .library(name: "VPNKit", targets: ["VPNKit"]),
        // GPU 패널 비디오 생성 API 공용 클라이언트 표면 (gpu-server-manager · gpu-video-studio 공유).
        .library(name: "GpuVideoKit", targets: ["GpuVideoKit"]),
        // MCP stdio 서버 공용: JSON-RPC 전송 + tools/list·tools/call 디스패치 루프.
        // 앱 홈 디렉터리 해석 + Codable 원자적 JSON state store 공용.
        .library(name: "AppPathsKit", targets: ["AppPathsKit"]),
        // 멀티에이전트 계층별 모델/effort 정책 SSOT(meta/coordinator/worker/verifier).
        .library(name: "AgentTierKit", targets: ["AgentTierKit"]),
        .library(name: "AgentPolicyKit", targets: ["AgentPolicyKit"]),
        .library(name: "FileBrowserKit", targets: ["FileBrowserKit"]),
        .library(name: "FileStorageKit", targets: ["FileStorageKit"]),
        // ScreenCaptureKit(SCScreenshotManager) 기반 디스플레이/영역/윈도우 캡처 공용. (Apple SCK 와 이름 충돌 회피)
        .library(name: "ScreenGrabKit", targets: ["ScreenGrabKit"]),
        // 접근성(AXUIElement) 트리 읽기 공용 primitive.
        .library(name: "AXTreeKit", targets: ["AXTreeKit"]),
        .library(name: "InteropKit", targets: ["InteropKit"]),
        // gujo.ai 구매자 계통 정본 — 라이브러리·설치·다운로드·자격 모델.
        // gujo(판매자 셸)와 gujo-cloud-apps(구매자 허브)가 함께 쓴다. 앱끼리 직접 참조하지 않는다.
        .library(name: "GujoCoreKit", targets: ["GujoCoreKit"]),
        // 회원(고객) 모델·검색·기기·구독 요약 뷰모델. 네트워크 없음.
        .library(name: "GujoMemberKit", targets: ["GujoMemberKit"]),
        // Gujo Store Ops 공유 코어 — staff 토큰 공급 + 스킬 발행/폐기 + 다운로드 파이프라인 감사.
        .library(name: "GujoStoreOpsCore", targets: ["GujoStoreOpsCore"]),
        // 함대 마케팅 버전 거절 정본. Foundation 만 — Linux lint 와 macOS ship 이 공유.
        .library(name: "MarketingVersionKit", targets: ["MarketingVersionKit"]),
        .library(name: "CompletionKit", targets: ["CompletionKit"]),
        .library(name: "PimKit", targets: ["PimKit"]),
        // 재무 원장 제품군(business-ledger 사업 · personal-ledger 개인) 공용 도메인 킷:
        // 계좌·카드·구독·입출금 원장(sqlite)·CSV 가져오기·리포트·Vaultwarden 민감정보 연동.
        // 우산 — 소비 앱은 이거 한 줄로 예전 표면을 받는다. 경계는 아래 5개 타깃이 강제.
        .library(name: "MoneyLedgerKit", targets: ["MoneyLedgerKit"]),
        // 순수 도메인 값(Money*, BusinessProfile, AttachmentRecord/Error, ContentHash,
        // ImportBatch, LedgerContext, LedgerDate). macOS-only(Keychain·Vaultwarden·
        // CommandKit·SQLite) 의존이 없어 business-api 컨테이너 서버가 이것만 링크한다.
        .library(name: "MoneyLedgerModels", targets: ["MoneyLedgerModels"]),
        // sqlite 원장 소유.
        .library(name: "MoneyLedgerStoreKit", targets: ["MoneyLedgerStoreKit"]),
        // CSV 수입(한국 은행 CSV 인코딩 자동판별 포함).
        .library(name: "MoneyLedgerImportKit", targets: ["MoneyLedgerImportKit"]),
        // 저장 행 위의 순수 리포트 — 통화 버킷을 절대 합치지 않는다(환율 없음 원칙).
        .library(name: "MoneyLedgerReportKit", targets: ["MoneyLedgerReportKit"]),
        // 첨부 본체·Vaultwarden 민감정보 연동.
        .library(name: "MoneyLedgerVaultKit", targets: ["MoneyLedgerVaultKit"]),
        // 두 앱 CLI 가 공유하는 서브커맨드 라우터 — 각 앱 main.swift 는 scope 만 주고 위임.
        .library(name: "MoneyLedgerCLIKit", targets: ["MoneyLedgerCLIKit"]),
        // 두 앱 GUI 가 공유하는 SwiftUI 대시보드 — CLI 타깃에는 절대 링크하지 않는다(dual-entry).
        .library(name: "MoneyLedgerUIKit", targets: ["MoneyLedgerUIKit"]),
        // 순수 회계 계산(저장소 없음) — 소득세법 간편장부 표준손익계산서 계정과목 enum ·
        // 손익 집계(매출총이익·영업이익·세전이익) · 기간 비교(basis point) · 계정 제안 표(JSON 리소스).
        .library(name: "MoneyAccountingKit", targets: ["MoneyAccountingKit"]),
        // 순수 세무 규칙(저장소 없음) — 10/110 분리 · 매입세액 공제 판정 · 장부/신고 의무 기준표 ·
        // 공휴일 이월 신고 달력. 기준 금액·업종·공휴일은 연도 키 JSON 리소스, 값마다 confidence.
        // 회계 Kit 에 의존하지 않고 계정 코드를 문자열로 받는다(위키 9261be4f).
        .library(name: "KoreanTaxRulesKit", targets: ["KoreanTaxRulesKit"]),
        .library(name: "KeychainKit", targets: ["KeychainKit"]),
        // 비밀값을 응답으로 내보내지 않는 재사용 가능한 credential profile/runner 경계.
        .library(name: "CredentialBrokerKit", targets: ["CredentialBrokerKit"]),
        // 소스는 main 에 있는데 **타깃 선언 자체가 없어서** 아무도 쓸 수 없었다
        // (2026-07-16 main/ worktree 충돌 때 선언만 유실된 것으로 보인다).
        // 이걸 요구하는 앱 4개가 그동안 컴파일 불가였다.
        .library(name: "EmulatorControlClientKit", targets: ["EmulatorControlClientKit"]),
        .library(name: "ProductPortfolioKit", targets: ["ProductPortfolioKit"]),
        .library(name: "ProductPortfolioCoreKit", targets: ["ProductPortfolioCoreKit"]),
        .library(name: "ProductPortfolioStoreKit", targets: ["ProductPortfolioStoreKit"]),
        // 공동인증서 활성 선택·hub 상태 — joint-certificate-manager 가 발행, 소비 앱이 읽는다.
        .library(name: "CertificateKit", targets: ["CertificateKit"]),
        // 자격증명 수명주기(판정·회전) 공용 SSOT — 제공자 중립.
        .library(name: "CredentialLifecycleKit", targets: ["CredentialLifecycleKit"]),
        // 자격증명 공급자→소비자 의존성 그래프·권한·안전 전달 공용 계약.
        .library(name: "CredentialDependencyKit", targets: ["CredentialDependencyKit"]),
        // 소비 앱이 AgentVault CLI의 메타데이터·권한 판정을 비밀 노출 없이 재사용하는 클라이언트.
        .library(name: "AgentVaultClientKit", targets: ["AgentVaultClientKit"]),
        .library(name: "CredentialPickerKit", targets: ["CredentialPickerKit"]),
        .library(name: "InfisicalKit", targets: ["InfisicalKit"]),
        .library(name: "HTTPClientKit", targets: ["HTTPClientKit"]),
        // Gujo 스태프 인증 계약 v1 §4 — device-code 로그인·Keychain(net.ranode.gujo)·agent-vault 폴백.
        .library(name: "GujoAuthKit", targets: ["GujoAuthKit"]),
        // 계약 §5 — commerce/support/ops/intake/skills 스태프 API 타입 클라이언트. GujoAuthKit 위.
        .library(name: "GujoStaffAPIKit", targets: ["GujoStaffAPIKit"]),
        // PiKVM(kvmd) 장비 전용 클라이언트 — `{ok,result}` 봉투·`X-KVMD-*` 헤더 인증·자체 서명 TLS.
        // 서버 무관 generic "KVM 클라이언트" 가 아니라 kvmd 계약에 고정한다.
        .library(name: "PiKVMClientKit", targets: ["PiKVMClientKit"]),
        // business-api-swift 서버 전용 클라이언트 + 동기화 엔진. typed CRUD(7 엔티티) + /sync/changes
        // pull 동기화. 서버 무관 generic 동기화가 아니라 business-api 계약(엔드포인트·봉투·content_hash)에
        // 고정. generic 추상은 HTTPClientKit(전송) 과 LocalSyncStore(로컬 저장 adapter) 만.
        .library(name: "BusinessCloudClientKit", targets: ["BusinessCloudClientKit"]),
        .library(name: "ImageCacheKit", targets: ["ImageCacheKit"]),
        .library(name: "ClipboardSyncKit", targets: ["ClipboardSyncKit"]),
        // Claude Code unified rate-limit(5h/7d) 조회 공용 SSOT — token-bar·ai-cli-account-manager 공유.
        .library(name: "ClaudeLimitsKit", targets: ["ClaudeLimitsKit"]),
        // Claude Code 런타임 자격·상태·Z.ai backend 환경변수 계약 공용.
        // 계정 UI/저장소는 각 앱에 남기고, 다른 앱도 같은 인증 정본을 소비하게 한다.
        .library(name: "ClaudeRuntimeKit", targets: ["ClaudeRuntimeKit"]),
        // accounts.json 앱 간 계약의 SSOT — 클라이언트 enum·파일 경로·행 스키마·계정 동일성.
        // 쓰기(ai-cli-account-manager)와 읽기(ai-cli-launcher)가 같은 정본을 쓰게 한다.
        .library(name: "AiCliAccountKit", targets: ["AiCliAccountKit"]),
        .library(name: "DevToolsAgentKit", targets: ["DevToolsAgentKit"]),
        // Apps, Agents, Rooms 3대 관점과 AWO 잡 파이프라인, 임차 매트릭스를 총괄하는 콕핏 관점 풀네임 키트.
        .library(name: "FleetCockpitPerspectiveKit", targets: ["FleetCockpitPerspectiveKit"]),
        .library(name: "AgentScanKit", targets: ["AgentScanKit"]),
        .library(name: "SessionKit", targets: ["SessionKit"]),
        // claude/codex/grok 세션을 **읽어** 대화·계획·파일·명령으로 증류하는 공용 리더.
        // SessionKit(발견) 위에 얹힌다. 툴마다 저장 구조가 다르고 자주 바뀌므로
        // (codex 는 한 줄이 2MB, grok 은 세션이 디렉터리) 그 지식을 여기 한 곳에 모은다.
        .library(name: "AgentSessionKit", targets: ["AgentSessionKit"]),
        .library(name: "AgentContextKit", targets: ["AgentContextKit"]),
        // 선언된(declared) 에이전트·스킬 레지스트리 SSOT — 실행 중(live)이 아니라 "무슨 에이전트/스킬이 있나".
        .library(name: "SkillRegistryKit", targets: ["SkillRegistryKit"]),
        .library(name: "AgentRegistryKit", targets: ["AgentRegistryKit"]),
        // LLM CLI(claude/codex/grok) 실행·결과해석·디스패치 통합 런타임 — 흩어진 subprocess 호출을 하나로.
        // 하위: AgentRegistryKit(정의)·CommandKit(실행)·InteropKit(봉투). 각 앱이 AgentCLIKit 으로 소비.
        .library(name: "LLMRuntimeKit", targets: ["LLMRuntimeKit"]),
        // 앱 단위 에이전트/스킬 카드 카탈로그 — 파일 SSOT(agents.json, SKILL.md)를 뷰-무관 카드로 평탄화.
        // GUI 카드뷰와 CLI --json 이 같은 catalog.cards() 를 써서 "같은 모양"을 보장한다. Foundation-only.
        .library(name: "AgentCardKit", targets: ["AgentCardKit"]),
        // 각 앱 CLI 의 agent/skill/chat 공통 서브커맨드 표면. main.swift 한 줄 위임.
        // LLMRuntimeKit(실행)·AgentCardKit(카드)·AgentScanKit(관측)·InteropKit(봉투) 위에서 동작. Foundation-only.
        .library(name: "AgentCLIKit", targets: ["AgentCLIKit"]),
        // 코딩 에이전트 CLI 브릿지 — claude/codex/grok/gemini argv·메타 파서 SSOT (스케줄 잡·Gaya 등 소비자).
        // 실행(Process)은 포함하지 않음 — CommandKit/LLMRuntimeKit/dispatcher 가 소비.
        .library(name: "CodingAgentBridgeKit", targets: ["CodingAgentBridgeKit"]),
        // ~/loops maker→checker 원장 계약 — 관제·검수 앱이 같은 모델과 파서를 공유한다.
        .library(name: "LoopLedgerKit", targets: ["LoopLedgerKit"]),
        // AWS SigV4 서명 원시체 — S3/Garage(S3Publisher·GujoBlobSync) 등이 공유.
        // 외부 셸/AWS SDK 없이 CryptoKit 으로 canonical request + HMAC 체인.
        .library(name: "SigV4Kit", targets: ["SigV4Kit"]),
        .library(name: "ShareLinkKit", targets: ["ShareLinkKit"]),
        // macOS APFS 네이티브 스냅샷 및 고속 변경 감지 엔진
        .library(name: "APFSSnapshotKit", targets: ["APFSSnapshotKit"]),
        // 고속 블록 중복제거(FastCDC) 및 소형 파일 팩파일(Packfile) 집약 엔진
        .library(name: "ChunkDedupKit", targets: ["ChunkDedupKit"]),
        // 의존성 0 zip 리더/라이터 — Apple Compression 으로 raw DEFLATE inflate/deflate.
        // xlsx/hwpx/pptx 등 zip+XML 컨테이너를 다루는 앱들이 공유(외부 프로세스·SPM 원격 의존 제거).
        .library(name: "ZipArchiveKit", targets: ["ZipArchiveKit"]),
        .library(name: "HwpxComposeKit", targets: ["HwpxComposeKit"]),
        // "돈 들어오는 거 찾기" 앱 가족(government-program/loan/subsidy/tax-benefit lookup)의
        // 공유 코어 — 신청자 프로필 · 소스 계약 · 결정적 매칭 엔진.
        .library(name: "MoneyInflowKit", targets: ["MoneyInflowKit"]),
        // 정부지원금(Government Support) 및 돈 유입원 패밀리 공통 도메인/크롤러/상태/카탈로그 킷
        .library(name: "MoneySourceKit", targets: ["MoneySourceKit"]),
        .library(name: "MoneyRevenueRecognitionKit", targets: ["MoneyRevenueRecognitionKit"]),
        .library(name: "MoneyFXKit", targets: ["MoneyFXKit"]),
        .library(name: "LoanScheduleKit", targets: ["LoanScheduleKit"]),
        .library(name: "BankScraperKit", targets: ["BankScraperKit"]),
        .library(name: "ThrottledParallelKit", targets: ["ThrottledParallelKit"]),
        .library(name: "IncrementalExecutionKit", targets: ["IncrementalExecutionKit"]),
        .library(name: "RoomKit", targets: ["RoomKit"]),
        .library(name: "RoomPlacementKit", targets: ["RoomPlacementKit"]),
        .library(name: "RoomSeatKit", targets: ["RoomSeatKit"]),
        // 공개 웹 크롤링 공용 기반 — 비동기 HTTP fetch + HTML 파싱 헬퍼 + 봇차단 호스트.
        // online-opportunity-radar 의 SourceFetch/BotBlockedHosts 와 money-source 크롤러의
        // HTML 파서를 일반화해 한 곳으로(각 앱이 따로 정의하던 것의 통합).
        .library(name: "WebCrawlKit", targets: ["WebCrawlKit"]),
        // 순수 Swift YAML 파서/이미터 — 외부 Yams 의존을 대체.
        .library(name: "YamlKit", targets: ["YamlKit"]),
        // 순수 Swift 선언형 기획 스펙 및 FSM 도달가능성·컴파일 엔진 (PC 1440px SSOT).
        .library(name: "PagePlanningKit", targets: ["PagePlanningKit"]),
        // 순수 Swift 전역 단축키 모듈 — 외부 KeyboardShortcuts 의존을 대체.
        // UserDefaults 저장 포맷이 KeyboardShortcuts 2.x 와 바이트 단위로 동일해
        // 사용자 기존 단축키가 마이그레이션 후에도 그대로 살아 있다.
        .library(name: "HotKeyKit", targets: ["HotKeyKit"]),
        .library(name: "TenantGuardKit", targets: ["TenantGuardKit"]),
        // OpenFeature OFREP 클라이언트 — GO Feature Flag relay proxy. 외부 의존 0 (URLSession).
        .library(name: "AgentTriageKit", targets: ["AgentTriageKit"]),
        // IPTC Photo Metadata 2025.1 AI 필드(프롬프트·모델·DigitalSourceType)를
        // 이미지에 심고 읽는다. C2PA 서명은 포함하지 않는다.
        .library(name: "GenerativeImageMetaKit", targets: ["GenerativeImageMetaKit"]),
        .library(name: "SecretMaskKit", targets: ["SecretMaskKit"]),
        .library(name: "LaunchAgentKit", targets: ["LaunchAgentKit"]),
        .library(name: "TenantDocumentVaultKit", targets: ["TenantDocumentVaultKit"]),
        .library(name: "ReleaseReceiptKit", targets: ["ReleaseReceiptKit"]),
        // APFS Sparsebundle 컨테이너 마운트·생성·언마운트·토큰 자가치유·수명주기 관리
        .library(name: "SparsebundleKit", targets: ["SparsebundleKit"]),
        // 머신 고유 식별(IOPlatformUUID/하드웨어 족보) 및 분산 저장소 키 생성기
        .library(name: "MachineIdentityKit", targets: ["MachineIdentityKit"]),
        .library(name: "FlowChartUIKit", targets: ["FlowChartUIKit"]),
        .library(name: "GanttChartUIKit", targets: ["GanttChartUIKit"]),
        .library(name: "MetricGaugeUIKit", targets: ["MetricGaugeUIKit"]),
        .library(name: "SphereViewport3DUIRuntimeKit", targets: ["SphereViewport3DUIRuntimeKit"]),
        .library(name: "InteractiveGestureHapticKit", targets: ["InteractiveGestureHapticKit"]),
        // 정부사업 및 구독 딜 공용 기회 인텔리전스 및 수집·타임라인 UI 키트
        .library(name: "OpportunityIntelKit", targets: ["OpportunityIntelKit"]),
        .library(name: "OpportunityIngestKit", targets: ["OpportunityIngestKit"]),
        .library(name: "OpportunityTimelineUIKit", targets: ["OpportunityTimelineUIKit"]),
        .library(name: "MarkdownSSOTKit", targets: ["MarkdownSSOTKit"]),
        .library(name: "AppContractTestKit", targets: ["AppContractTestKit"]),
        .library(name: "SurfaceParityKit", targets: ["SurfaceParityKit"]),
        .library(name: "ISO8601DateCodecKit", targets: ["ISO8601DateCodecKit"]),
        .library(name: "HomeostasisEngineKit", targets: ["HomeostasisEngineKit"]),
        .library(name: "FastDiskIOKit", targets: ["FastDiskIOKit"]),
        .library(name: "RuleMiningKit", targets: ["RuleMiningKit"]),
        .library(name: "CognitiveHomeostasisKit", targets: ["CognitiveHomeostasisKit"]),
        .library(name: "GujoStoreCatalogKit", targets: ["GujoStoreCatalogKit"]),
        .library(name: "GujoStoreBillingKit", targets: ["GujoStoreBillingKit"]),
        .library(name: "DoctorProbeKit", targets: ["DoctorProbeKit"]),
        .library(name: "AgentSessionStorageKit", targets: ["AgentSessionStorageKit"]),
        .library(name: "FleetPerspectiveModelKit", targets: ["FleetPerspectiveModelKit"]),
        .library(name: "RuleMiningEngineKit", targets: ["RuleMiningEngineKit"]),
        .library(name: "AppPersistenceKit", targets: ["AppPersistenceKit"]),
        .library(name: "ConcurrencyKit", targets: ["ConcurrencyKit"]),
        .library(name: "GitMerkleReceiptKit", targets: ["GitMerkleReceiptKit"]),
        .library(name: "FastLintCoreKit", targets: ["FastLintCoreKit"]),
        .library(name: "LintObservabilityKit", targets: ["LintObservabilityKit"]),
    ],
    dependencies: [
        // Linux 컨테이너(business-api)에서도 SHA256(ContentHash) 가 컴파일되게 하려고
        // swift-crypto 를 끌어온다. Apple 플랫폼에서는 `import Crypto` 가 CryptoKit 을
        // @_exported 로 재노출하므로 macOS 앱 쪽 호환성에 영향이 없다.
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(name: "ConcurrencyKit"),
        .testTarget(name: "ConcurrencyKitTests", dependencies: ["ConcurrencyKit"]),
        .target(name: "CommandKit", dependencies: ["InteropKit", "JSONLJournalKit", "StateRootKit"]),
        .target(name: "JSONLJournalKit", dependencies: ["FastDiskIOKit"]),
        .target(name: "HostGovernanceKit"),
        .testTarget(name: "HostGovernanceKitTests", dependencies: ["HostGovernanceKit"]),
        .target(name: "CommandKitTesting", dependencies: ["CommandKit"]),
        .target(name: "StoreAssetKit"),
        .testTarget(name: "StoreAssetKitTests", dependencies: ["StoreAssetKit"]),
        .testTarget(name: "OrganKitTests", dependencies: ["OrganKit"]),
        // GPU 패널 비디오 API 클라이언트 (Foundation only) — 두 앱이 같은 표면을 공유.
        .target(name: "GpuVideoKit", dependencies: ["EndpointRouterKit"]),
        .target(name: "WorktreeKit", dependencies: ["CommandKit", "FastDiskIOKit"]),
        .testTarget(name: "WorktreeKitTests", dependencies: ["WorktreeKit"]),
        // 캐시된 Keychain 저장소(앱 공용 SSOT). 읽기 인메모리 메모이즈 → SwiftUI render 경로에서
        // 불려도 securityd 시스템콜을 첫 1회로 줄인다. raw SecItemCopyMatching 반복이 근본 원인이었다.
        .target(name: "KeychainKit"),
        .target(name: "CredentialBrokerKit", dependencies: ["CommandKit", "KeychainKit"]),
        .target(name: "EmulatorControlClientKit", dependencies: [
            .target(name: "KeychainKit", condition: .when(platforms: [.macOS, .iOS])),
        ]),
        .target(name: "ProductPortfolioCoreKit", dependencies: ["StateRootKit"]),
        .target(name: "ProductPortfolioStoreKit", dependencies: ["ProductPortfolioCoreKit", "StateRootKit"]),
        .target(name: "ProductPortfolioKit", dependencies: ["ProductPortfolioCoreKit", "ProductPortfolioStoreKit", "StateRootKit"]),
        .target(name: "CertificateKit", dependencies: ["StateMirrorKit"]),
        // 회전 순서를 상태 기계로 강제한다 — 순서를 틀리면 운영이 조용히 깨진다.
        .target(name: "CredentialLifecycleKit", dependencies: ["InteropKit"]),
        .target(name: "CredentialDependencyKit"),
        .target(name: "AgentVaultClientKit", dependencies: ["CommandKit", "InteropKit"]),
        .target(name: "GujoCoreKit", dependencies: [
            "LocalizationKit", "AppPathsKit", "CommandKit", "AgentVaultClientKit",
            "StateMirrorKit", "StateRootKit", "EndpointRouterKit", "InstallHealthKit", "KeychainKit", "InteropKit",
            "FastDiskIOKit",
        ]),
        .testTarget(name: "GujoCoreKitTests", dependencies: ["GujoCoreKit", "EndpointRouterKit"]),
        // 회원 모델·PII 보존기간. Foundation only — 네트워크/Keychain 없음.
        .target(name: "GujoMemberKit"),
        .testTarget(name: "GujoMemberKitTests", dependencies: ["GujoMemberKit"]),
        .target(
            name: "GujoStoreBillingKit",
            dependencies: [
                "EndpointRouterKit",
                "InteropKit",
                "LocalizationKit",
                "ReleaseReceiptKit",
                "StateRootKit",
            ]
        ),
        .target(
            name: "GujoStoreCatalogKit",
            dependencies: [
                "GujoStoreBillingKit",
                "EndpointRouterKit",
                "PluginKit",
            ]
        ),
        .target(
            name: "GujoStoreOpsCore",
            dependencies: [
                "GujoStoreBillingKit",
                "GujoStoreCatalogKit",
                "LocalizationKit",
                "InteropKit",
                "PluginKit",
                "EndpointRouterKit",
                "StateMirrorKit",
                "StateRootKit",
                "ReleaseReceiptKit",
                "CommandKit",
            ]
        ),
        .testTarget(
            name: "GujoStoreOpsCoreTests",
            dependencies: ["GujoStoreOpsCore", "EndpointRouterKit", "PluginKit", "ReleaseReceiptKit"]
        ),
        // 소비 앱의 자격 설정 화면 정본. SecureField 없이 vault 카드를 고르기만 한다.
        .target(name: "CredentialPickerKit", dependencies: ["AgentVaultClientKit"]),
        // 공용 HTTP 주입 seam(테스트 목킹 가능) — 여러 앱이 각자 정의하던 것을 통합.
        .target(name: "HTTPClientKit"),
        // 스태프·구매자 인증(device-code). 호스트는 EndpointRouterKit `gujo-core`, 저장은 KeychainKit,
        // 러너 폴백은 AgentVaultClientKit(tenant:gujo / staff-token). env 는 읽지 않는다.
        .target(
            name: "GujoAuthKit",
            dependencies: ["HTTPClientKit", "EndpointRouterKit", "KeychainKit", "AgentVaultClientKit"]
        ),
        .testTarget(name: "GujoAuthKitTests", dependencies: ["GujoAuthKit", "HTTPClientKit"]),
        // 스태프 API 타입 클라이언트. 모든 호출이 GujoAuthKit 세션 토큰을 쓰고 403 에 부족 ability 를 싣는다.
        .target(name: "GujoStaffAPIKit", dependencies: ["GujoAuthKit", "HTTPClientKit"]),
        .testTarget(name: "GujoStaffAPIKitTests", dependencies: ["GujoStaffAPIKit", "GujoAuthKit", "HTTPClientKit"]),
        // "돈 들어오는 거 찾기" 앱 가족 공유 코어: 신청자 프로필·소스 계약·결정적 매칭 엔진.
        .target(name: "MoneyInflowKit"),
        .testTarget(name: "MoneyInflowKitTests", dependencies: ["MoneyInflowKit"]),
        // 공개 웹 크롤링 공용 기반(HTTP fetch + HTML 파싱 + 봇차단). HTTPClientKit 위.
        .target(name: "WebCrawlKit", dependencies: ["HTTPClientKit"]),
        .testTarget(name: "WebCrawlKitTests", dependencies: ["WebCrawlKit"]),
        // business-api-swift 에 유관한 typed CRUD + 동기화 클라이언트. 서버 계약(엔드포인트·봉투·
        // content_hash·커서) 에 고정 — generic 은 HTTPClientKit/InteropKit/MoneyLedgerModels 의존만.
        .target(
            name: "BusinessCloudClientKit",
            dependencies: ["HTTPClientKit", "InteropKit", "MoneyLedgerModels"]
        ),
        // Infisical(Universal Auth) 클라이언트·모델·자격 저장 — infisical-swift/agent-vault/route 공용.
        .target(name: "InfisicalKit", dependencies: ["HTTPClientKit"]),
        // PiKVM(kvmd) 장비 클라이언트. generic 의존은 HTTPClientKit(전송) 하나뿐이고,
        // 자체 서명 TLS 예외는 장비 호스트에만 적용된다(전역 ATS 예외를 열지 않는다).
        .target(name: "PiKVMClientKit", dependencies: ["HTTPClientKit"]),
        .testTarget(name: "PiKVMClientKitTests", dependencies: ["PiKVMClientKit"]),
        // 프로세스 공용 이미지 디코드 캐시(NSCache). List/ForEach 셀의 NSImage(contentsOf:) 반복 제거.
        .target(name: "ImageCacheKit"),
        .target(name: "ClipboardSyncKit"),
        .testTarget(name: "ClipboardSyncKitTests", dependencies: ["ClipboardSyncKit"]),
        .target(name: "ClaudeLimitsKit"),
        .testTarget(name: "ClaudeLimitsKitTests", dependencies: ["ClaudeLimitsKit"]),
        .target(name: "ClaudeRuntimeKit", dependencies: ["InteropKit"]),
        .testTarget(name: "ClaudeRuntimeKitTests", dependencies: ["ClaudeRuntimeKit"]),
        .target(name: "AiCliAccountKit", dependencies: ["StateRootKit"]),
        .testTarget(name: "AiCliAccountKitTests", dependencies: ["AiCliAccountKit"]),
        // 도는 claude/codex 세션 스캔·귀속 — 여러 에이전트 관제 앱이 공유.
        .target(name: "AgentScanKit"),
        .testTarget(name: "AgentScanKitTests", dependencies: ["AgentScanKit"]),
        // Antigravity CLI 세션 저장소가 sqlite(conversation_summaries.db·conversations/<id>.db)라
        // 재무 원장과 같은 방식 system SQLite3 로 읽는다(외부 ORM 금지).
        .target(
            name: "SessionKit",
            dependencies: ["FastDiskIOKit"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(
            name: "AgentSessionStorageKit",
            dependencies: ["SessionKit", "FastDiskIOKit", "ISO8601DateCodecKit"]
        ),
        .target(
            name: "AgentSessionKit",
            dependencies: ["AgentSessionStorageKit", "SessionKit", "FastDiskIOKit"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "AgentSessionKitTests",
            dependencies: ["AgentSessionKit"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        // 세션이 물은 컨텍스트(주입 지침·스킬/에이전트 md·읽은 문서·활성화)의 해석 계층.
        // 소비자가 둘 이상이라 앱이 아니라 kit 에 둔다 — Agent Session Context Ledger(세션 축)와
        // Agent Document Usage(문서 축)가 같은 원장을 서로 다른 각도로 읽는다.
        .target(name: "AgentContextKit", dependencies: ["AgentSessionKit", "SkillRegistryKit", "StateRootKit"]),
        .testTarget(name: "AgentContextKitTests", dependencies: ["AgentContextKit", "AgentSessionKit", "StateRootKit"]),
        .testTarget(name: "SessionKitTests", dependencies: ["SessionKit"]),
        // 스킬 SSOT(읽기): 여러 도구(claude/codex/…) 루트에서 스킬을 스캔해 id·경로·출처로 노출.
        .target(name: "SkillRegistryKit"),
        .testTarget(name: "SkillRegistryKitTests", dependencies: ["SkillRegistryKit"]),
        // 에이전트 SSOT: 선언된 AgentDef(페르소나·모델·권한·cwd·스킬셋)를 ~/.agent-apps/agents.json 에 영속.
        // SkillRegistryKit 에 의존(에이전트는 스킬 id 를 참조·해석).
        .target(name: "AgentRegistryKit", dependencies: ["SkillRegistryKit"]),
        .testTarget(name: "AgentRegistryKitTests", dependencies: ["AgentRegistryKit"]),
        // LLM CLI 런타임: claude/codex/grok 백엔드 + 결과 파서 + 디스패치 + 설치 스캔.
        // CommandKit(실행)·AgentRegistryKit(AgentDef) 위에서 동작. Foundation-only — AppKit/SwiftUI 끌지 않는다.
        .target(
            name: "LLMRuntimeKit",
            dependencies: ["CommandKit", "AgentRegistryKit", "InteropKit"]
        ),
        .testTarget(name: "LLMRuntimeKitTests", dependencies: ["LLMRuntimeKit"]),
        // 앱 카드 카탈로그: AgentDef/SkillRef/워크스페이스 .claude 를 CatalogCard 로 평탄화.
        .target(
            name: "AgentCardKit",
            dependencies: ["AgentRegistryKit", "SkillRegistryKit"]
        ),
        .testTarget(name: "AgentCardKitTests", dependencies: ["AgentCardKit"]),
        // agent/skill/chat 서브커맨드 디스패처. 앱 도메인 컨텍스트를 LLMRunRequest 로 묶는다.
        .target(
            name: "AgentCLIKit",
            // DoctorContract 는 Foundation only — 진단 결과를 앱마다 다른 모양으로
            // 내지 않기 위한 공용 스키마다(AppKit 을 끌어오지 않는다).
            dependencies: ["LLMRuntimeKit", "AgentCardKit", "AgentScanKit", "InteropKit", "DoctorContract", "AgentRegistryKit", "SkillRegistryKit", "StateRootKit", "AppErrorKit", "ISO8601DateCodecKit"]
        ),
        .testTarget(name: "AgentCLIKitTests", dependencies: ["AgentCLIKit", "AppErrorKit"]),
        // argv/meta only — Foundation-only, AppKit 금지.
        .target(name: "CodingAgentBridgeKit"),
        .testTarget(name: "CodingAgentBridgeKitTests", dependencies: ["CodingAgentBridgeKit"]),
        .target(name: "LoopLedgerKit", dependencies: ["StateRootKit"]),
        .testTarget(name: "LoopLedgerKitTests", dependencies: ["LoopLedgerKit"]),
        // 앱 내 devtools 파일 브리지 에이전트 — OSLog tail·heartbeat 를 ~/.swift-devtools 로 게시.
        .target(name: "DevToolsAgentKit", dependencies: ["StateRootKit"]),
        .testTarget(name: "DevToolsAgentKitTests", dependencies: ["DevToolsAgentKit"]),
        .testTarget(name: "KeychainKitTests", dependencies: ["KeychainKit"]),
        .testTarget(name: "CredentialLifecycleKitTests", dependencies: ["CredentialLifecycleKit"]),
        .testTarget(name: "CredentialDependencyKitTests", dependencies: ["CredentialDependencyKit"]),
        .testTarget(name: "AgentVaultClientKitTests", dependencies: ["AgentVaultClientKit", "CommandKit"]),
        .testTarget(name: "CredentialPickerKitTests", dependencies: ["CredentialPickerKit"]),
        .target(name: "CompletionKit"),
        .testTarget(name: "CompletionKitTests", dependencies: ["CompletionKit"]),
        .target(
            name: "PrivilegedExec",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("Security", .when(platforms: [.macOS])),
            ]
        ),
        .target(
            name: "PrivilegedKit",
            dependencies: ["CommandKit", "PrivilegedExec"]
        ),
        .target(name: "LocalizationKit"),
        .target(
            name: "AppErrorKit",
            dependencies: ["LocalizationKit"]
        ),
        .testTarget(
            name: "AppErrorKitTests",
            dependencies: ["AppErrorKit", "LocalizationKit"]
        ),
        // AWS SigV4 서명 — S3/Garage 클라이언트가 공유(publish-kit·agent-wiki-kit 중복 제거).
        // Foundation + CryptoKit 만 사용. 테스트는 AWS 공식 시그처처 벡터로 고정.
        .target(name: "SigV4Kit"),
        // BYO 저장소 공유 링크 — 여러 앱이 같은 카드/설정을 쓴다.
        .target(name: "ShareLinkKit", dependencies: ["SigV4Kit", "CredentialBrokerKit"]),
        .testTarget(name: "ShareLinkKitTests", dependencies: ["ShareLinkKit"]),
        .testTarget(name: "SigV4KitTests", dependencies: ["SigV4Kit"]),
        .target(name: "InstallerKit", dependencies: ["CommandKit"]),
        .target(name: "AppScanKit"),
        .target(name: "UnusedInspectionKit", dependencies: ["AppScanKit"]),
        .testTarget(name: "UnusedInspectionKitTests", dependencies: ["UnusedInspectionKit"]),
        .testTarget(name: "AppScanKitTests", dependencies: ["AppScanKit"]),
        // MCP 전송/인자 안전 헬퍼(크래시 방지): JSON 직렬화 가드, 정수/불리언 강제변환.
        .target(name: "MCPSupport"),
        // 로그인 시 자동 실행(SMAppService) — 상주 앱 공통 토글. 시스템 프레임워크만 사용.
        .target(name: "LaunchAtLoginKit"),
        .target(name: "PrivilegedHelperKit"),
        // 중복 실행 방지: LaunchAgent 직접 exec/`open -n` 경로에서 두 번째 인스턴스를 즉시 종료.
        .target(name: "SingleInstanceKit", dependencies: ["FastDiskIOKit", "StateRootKit"]),
        .target(name: "StandardExtensionsKit"),
        .testTarget(name: "StandardExtensionsKitTests", dependencies: ["StandardExtensionsKit"]),
        .target(name: "FastSQLiteKit"),
        .testTarget(name: "FastSQLiteKitTests", dependencies: ["FastSQLiteKit"]),
        .target(name: "ProcessLifecycleKit"),
        .testTarget(name: "ProcessLifecycleKitTests", dependencies: ["ProcessLifecycleKit"]),
        .target(name: "NotificationKit"),
        .testTarget(name: "NotificationKitTests", dependencies: ["NotificationKit"]),
        .target(name: "TerminalLauncherKit", dependencies: ["CommandKit"]),
        .testTarget(name: "TerminalLauncherKitTests", dependencies: ["TerminalLauncherKit"]),
        .testTarget(name: "SingleInstanceKitTests", dependencies: ["SingleInstanceKit"]),
        .target(name: "EphemeralLeaseKit"),
        .testTarget(name: "EphemeralLeaseKitTests", dependencies: ["EphemeralLeaseKit"]),
        // 설치·자동시작 건강 판정(중복 실행·dangling LaunchAgent·구 번들 잔재·확장 누락·PATH CLI 심링크·Sparkle rpath)의 SSOT.
        // GUI(app-health-guard)와 커밋 게이트(scripts/lint-install-health.sh)가 같은 규칙을 공유한다.
        .target(name: "InstallHealthKit", dependencies: [.target(name: "StateRootKit")]),
        .target(
            name: "DoctorContract"
        ),
        .testTarget(name: "DoctorContractTests", dependencies: ["DoctorContract"]),
        .target(
            name: "DoctorProbeKit",
            dependencies: [
                "DoctorContract",
                "AppScanKit",
                "InstallHealthKit",
                "StateMirrorKit",
                "InteropKit",
                "StateRootKit",
            ]
        ),
        .target(
            name: "DoctorKit",
            dependencies: [
                "DoctorContract",
                "DoctorProbeKit",
                "AppScanKit",
                "InstallHealthKit",
                "StateMirrorKit",
                "InteropKit",
            ]
        ),
        .testTarget(name: "InstallHealthKitTests", dependencies: ["InstallHealthKit"]),
        // 설치본 낡음 배너를 여기서 낸다 — 모든 CLI 가 이미 DualEntryKit 진입 한 줄을
        // 부르므로, 앱 300개를 고치지 않고 한 곳에서 전 함대에 적용된다.
        .target(name: "DualEntryKit", dependencies: ["InstallHealthKit", "InteropKit", "StateRootKit"], exclude: ["README.md"]),
        .target(name: "AgentSurfaceKit", dependencies: ["InteropKit", "StateRootKit"]),
        .testTarget(name: "DoctorKitTests", dependencies: ["DoctorKit", "DoctorProbeKit", "InstallHealthKit"]),
        .testTarget(name: "DualEntryKitTests", dependencies: ["DualEntryKit", "InstallHealthKit"]),
        .testTarget(name: "AgentSurfaceKitTests", dependencies: ["AgentSurfaceKit"]),
        .testTarget(name: "EmulatorControlClientKitTests", dependencies: ["EmulatorControlClientKit"]),
        .testTarget(name: "ProductPortfolioKitTests", dependencies: ["ProductPortfolioKit"]),
        // TCC 권한(화면기록·손쉬운사용·카메라·자동화) 선-게이트 + 표준 안내 alert/딥링크.
        // 문구는 코드 상수(KR/EN)라 리소스 번들 불필요 → 앱 패키징 변경 없이 채택 가능.
        .target(name: "PermissionCore", dependencies: ["LocalizationKit", "CommandKit"]),
        .target(name: "PermissionKit", dependencies: ["LocalizationKit", "PermissionCore"]),
        .target(name: "PermissionDialogKit", dependencies: ["PermissionKit", "LocalizationKit"]),
        // 지목 스냅샷(요소·로그·스크린샷 경로)의 Codable 모델 + 상태파일 IO.
        // Foundation 만 써서 GUI 앱과 headless MCP 서버가 같은 파일로 통신한다.
        .target(name: "InspectorState"),
        // SwiftUI 개발 오버레이: 화면 요소를 지목 → 소스위치(#fileID/#line)·frame·
        // 마킹 스크린샷을 AI 붙여넣기용 컨텍스트로 클립보드에 복사 + last-pick.json 저장.
        .target(name: "InspectorKit", dependencies: ["InspectorState"]),
        // Bitwarden/Vaultwarden 클라이언트 코어(크립토·HTTP·세션·Keychain·생성기).
        // EnvVault(.env) 와 Vaultwarden Client(비밀번호 매니저)가 공유. 시스템 프레임워크만.
        .target(name: "VaultwardenCryptoKit"),
        .target(
            name: "VaultwardenClientKit",
            dependencies: [
                "VaultwardenCryptoKit",
                "InteropKit",
                "FastDiskIOKit",
                "StateRootKit",
            ]
        ),
        .target(
            name: "VaultwardenKit",
            dependencies: [
                "VaultwardenCryptoKit",
                "VaultwardenClientKit",
                "InteropKit",
                "FastDiskIOKit",
                "StateRootKit",
            ]
        ),
        .target(name: "VaultwardenBridgeKit"),
        .testTarget(name: "VaultwardenBridgeKitTests", dependencies: ["VaultwardenBridgeKit"]),
        .testTarget(name: "VaultwardenKitTests", dependencies: ["VaultwardenKit", "VaultwardenClientKit", "VaultwardenCryptoKit"]),
        // Swift App Store 플랫폼 공용 모듈.
        // C constructor 는 언어 혼합 금지라 별 타깃. 최종 링크에서 Swift @_cdecl 과 만난다.
        .target(
            name: "FleetDeskHookC",
            linkerSettings: [
                .linkedFramework("AppKit", .when(platforms: [.macOS])),
            ]
        ),
        .target(
            name: "FleetDeskKit",
            dependencies: ["FleetDeskHookC", "StateRootKit"]
        ),
        .target(
            name: "AppWindowKit",
            dependencies: [
                "FleetDeskKit",
                "SingleInstanceKit",
                "RoomSeatKit",
                "AppErrorKit",
                "NoticeBannerUIKit",
                "LocalizationKit",
            ]
        ),
        .target(name: "WindowChromeKit", dependencies: ["LocalizationKit", "StateRootKit"]),
        .target(name: "FreshnessKit"),
        .target(name: "FileIdentityKit"),
        .testTarget(name: "FileIdentityKitTests", dependencies: ["FileIdentityKit"]),
        .target(name: "SwiftSourceKit"),
        .testTarget(name: "SwiftSourceKitTests", dependencies: ["SwiftSourceKit"]),
        .target(name: "PackageIdentityKit"),
        .testTarget(name: "PackageIdentityKitTests", dependencies: ["PackageIdentityKit"]),
        .target(
            name: "GenerativeImageMetaKit",
            linkerSettings: [
                .linkedFramework("ImageIO"),
                .linkedFramework("CoreGraphics"),
            ]
        ),
        .testTarget(name: "GenerativeImageMetaKitTests", dependencies: ["GenerativeImageMetaKit"]),
        .target(name: "GraphEngineKit", dependencies: ["FileIdentityKit", "FastDiskIOKit"]),
        .target(name: "GraphLayoutKit"),
        .testTarget(name: "GraphLayoutKitTests", dependencies: ["GraphLayoutKit"]),
        .target(name: "ArchitectureCityKit"),
        .testTarget(name: "ArchitectureCityKitTests", dependencies: ["ArchitectureCityKit"]),
        .target(
            name: "ArchitectureCityUIKit",
            dependencies: ["ArchitectureCityKit"],
            linkerSettings: [.linkedFramework("SceneKit", .when(platforms: [.macOS]))]
        ),
        .target(name: "RadialGraphUIKit"),
        .testTarget(name: "RadialGraphUIKitTests", dependencies: ["RadialGraphUIKit"]),
        .target(name: "TimelineGraphUIKit"),
        .testTarget(name: "TimelineGraphUIKitTests", dependencies: ["TimelineGraphUIKit"]),
        .target(name: "WikiLedgerKit", dependencies: ["GraphEngineKit"]),
        .target(name: "GraphRAGKit", dependencies: ["GraphEngineKit"]),
        .target(name: "TelemetryKit", dependencies: ["EndpointRouterKit"]),
        .testTarget(name: "TelemetryKitTests", dependencies: ["TelemetryKit"]),
        .target(
            name: "PhotoLedgerKit",
            dependencies: ["CommandKit", "OnboardingKit", "InteropKit"]
        ),
        .testTarget(name: "PhotoLedgerKitTests", dependencies: ["PhotoLedgerKit"]),
        .target(name: "MailSendKit"),
        .testTarget(name: "MailSendKitTests", dependencies: ["MailSendKit"]),
        .target(name: "SettingsKit"),
        .target(name: "SettingsUIKit", dependencies: ["LocalizationKit", "LaunchAtLoginKit", "PluginKit"], resources: [.process("Resources")]),
        .testTarget(name: "SettingsUIKitTests", dependencies: ["SettingsUIKit", "LocalizationKit"]),
        .target(name: "ClipboardActionUIKit"),
        .target(name: "NoticeBannerUIKit"),
        .target(name: "StatusIndicatorUIKit"),
        .target(name: "CIPipelineUIKit", dependencies: ["StatusIndicatorUIKit"]),
        .testTarget(name: "CIPipelineUIKitTests", dependencies: ["CIPipelineUIKit"]),
        .target(name: "MenuBarPopoverUIKit"),
        .target(name: "MoneyInflowUIKit", dependencies: ["MoneyInflowKit"]),
        .target(name: "OnboardingKit"),
        .target(
            name: "OnboardingUIKit",
            dependencies: ["OnboardingKit", "LocalizationKit"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "OnboardingKitTests", dependencies: ["OnboardingKit"]),
        .testTarget(
            name: "OnboardingUIKitTests",
            dependencies: ["OnboardingUIKit", "OnboardingKit", "LocalizationKit"]
        ),
        // 게임메이커 앱 군단 공통: codex(GPT image) 호출·프롬프트 템플릿·배치 큐·생성 이력 추상화.
        // 즉흥 CLI 호출을 재현 가능한 파이프라인으로 대체한다. 정본: apps/game-agent-of-gaya/docs/GAMEMAKER-SWIFT-APP-FLEET.md.
        .target(name: "GameAsset2DKit", dependencies: ["InteropKit"]),
        .target(name: "GameUIAssetKit"),
        .target(name: "GameUIRuntimeKit", dependencies: ["GameUIAssetKit"]),
        .target(name: "GameDepthEngineKit", dependencies: ["GameUIAssetKit"]),
        .target(name: "GameDepthEngineControlKit", dependencies: ["GameDepthEngineKit"]),
        .executableTarget(name: "GameUIManifestCheck", dependencies: ["GameUIAssetKit"]),
        .testTarget(name: "GameUIAssetKitTests", dependencies: ["GameUIAssetKit"], exclude: ["Fixtures"]),
        .testTarget(name: "GameUIRuntimeKitTests", dependencies: ["GameUIRuntimeKit"]),
        .testTarget(name: "GameDepthEngineKitTests", dependencies: ["GameDepthEngineKit"]),
        .testTarget(name: "GameDepthEngineControlKitTests", dependencies: ["GameDepthEngineControlKit"]),
        // 픽셀 처리 공통: 스프라이트 시트 슬라이스·실루엣 드리프트 검수·후처리(rembg/magick/pngquant) 래퍼.
        .target(name: "PixelKit", dependencies: ["CommandKit"]),
        // 앱 상태 미러: 앱 내부 데이터를 ~/.swift-app-state/<앱>.json 으로 게시 —
        // 스크린샷 없이 CLI(swift-app-router state)로 모든 앱 데이터를 즉시 조회하는 공통 채널.
        .target(name: "StateMirrorKit", dependencies: ["StateRootKit"]),
        .testTarget(name: "StateMirrorKitTests", dependencies: ["StateMirrorKit"]),
        .target(name: "OrchestratorClientKit", dependencies: ["CommandKit", "InteropKit"]),
        .testTarget(name: "OrchestratorClientKitTests", dependencies: ["OrchestratorClientKit", "CommandKit"]),
        .target(name: "SeatReaderKit", dependencies: ["CommandKit", "InteropKit"]),
        .target(name: "SeatKit", dependencies: ["StateRootKit", "LocalizationKit"]),
        .testTarget(name: "SeatReaderKitTests", dependencies: ["SeatReaderKit", "CommandKit"]),
        .target(
            name: "BacklogKit",
            dependencies: ["CommandKit", "InteropKit", "StateRootKit", "LocalizationKit"]
        ),
        .testTarget(
            name: "BacklogKitTests",
            dependencies: ["BacklogKit", "CommandKit"]
        ),
        .target(name: "BacklogClientKit", dependencies: ["BacklogKit"]),
        .testTarget(name: "BacklogClientKitTests", dependencies: ["BacklogClientKit", "CommandKit"]),
        // 상태 루트 — StateMirrorKit.isRunningUnderTest 가 이 kit 을 재사용한다.
        .target(name: "StateRootKit"),
        .target(name: "OrganKit", dependencies: [.target(name: "StateRootKit")]),
        .testTarget(name: "StateRootKitTests", dependencies: ["StateRootKit"]),
        // 키→URL 라우터. 원장은 app-build-manager(.app-build-manager/endpoints.json).
        .target(
            name: "EndpointRouterKit",
            dependencies: ["StateRootKit", "LocalizationKit"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "EndpointRouterKitTests", dependencies: ["EndpointRouterKit"]),
        .target(name: "LicenseStorageKit", dependencies: ["KeychainKit"]),
        .target(name: "LicenseKeyWalletKit", dependencies: ["LicenseStorageKit", "KeychainKit", "StateRootKit"]),
        .target(name: "LicenseCacheKit", dependencies: ["LicenseKeyWalletKit", "LicenseStorageKit", "StateRootKit", "EndpointRouterKit", "KeychainKit"]),
        .testTarget(name: "LicenseCacheKitTests", dependencies: ["LicenseCacheKit"]),
        .target(name: "LicenseKit", dependencies: ["LicenseCacheKit"]),
        .target(name: "EntitlementKit", dependencies: ["LicenseCacheKit"]),
        .target(name: "BusinessEntityKit", dependencies: ["StateRootKit"]),
        .testTarget(name: "BusinessEntityKitTests", dependencies: ["BusinessEntityKit"]),
        .target(name: "DalKit", dependencies: ["InteropKit", "StateRootKit"]),
        .testTarget(name: "DalKitTests", dependencies: ["DalKit"]),
        // 앱 self-test 표준 계약.
        .target(name: "SelfTestKit"),
        .testTarget(name: "SelfTestKitTests", dependencies: ["SelfTestKit"]),
        .target(name: "LaravelKnowledgePipelineKit", dependencies: ["StateMirrorKit"]),
        .testTarget(
            name: "LaravelKnowledgePipelineKitTests",
            dependencies: ["LaravelKnowledgePipelineKit", "StateMirrorKit"]
        ),
        .target(name: "RepositoryIdentityKit"),
        .testTarget(name: "RepositoryIdentityKitTests", dependencies: ["RepositoryIdentityKit"]),
        // 메뉴바 앱 공통 갱신 컨트롤러 — refreshTask + autoTimerTask 생명주기와
        // 각 갱신 뒤 StateMirror 게시 훅을 한곳에서 소유한다.
        .target(name: "MenuBarKit", dependencies: ["StateMirrorKit"]),
        .testTarget(name: "MenuBarKitTests", dependencies: ["MenuBarKit"]),
        // 드라이버 무관 DB 뷰어 코어. 명령 실행은 CommandKit 에 위임(ProcessShellRunner 접기).
        .target(
            name: "DBViewerKit",
            dependencies: ["CommandKit", "VPNKit"]
        ),
        .testTarget(
            name: "DBViewerKitTests",
            dependencies: ["DBViewerKit", "VPNKit"]
        ),
        // DB 뷰어 3앱에 복제돼 있던 SwiftUI 뷰 중 **차이가 없다고 실측된 것만** 모은다.
        .target(
            name: "DBViewerUIKit",
            dependencies: ["DBViewerKit"]
        ),
        // 미리보기 및 인스펙터 통합 엔진 코어 (L2/L3 프로토콜, 포맷 라우터, StateMirror).
        .target(
            name: "PreviewEngineKit",
            dependencies: ["StateMirrorKit", "StateRootKit"]
        ),
        .testTarget(
            name: "PreviewEngineKitTests",
            dependencies: ["PreviewEngineKit"]
        ),
        // 미리보기 뷰포트 UI (L0 호스트 셸, L1 무한 줌/패닝 캔버스, 가상화 그리드, 페이지 컨테이너).
        .target(
            name: "PreviewUIKit",
            dependencies: ["PreviewEngineKit"]
        ),
        // ~/.ssh/config 파싱 + system-ssh 러너. 실제 실행은 CommandKit 에 위임.
        .target(name: "RemoteExecKit", dependencies: ["CommandKit"]),
        .testTarget(name: "RemoteExecKitTests", dependencies: ["RemoteExecKit"]),
        .target(
            name: "SandboxKit",
            dependencies: [
                "StateRootKit",
                "CommandKit",
                .product(name: "Crypto", package: "swift-crypto"),
            ]
        ),
        .testTarget(
            name: "SandboxKitTests",
            dependencies: ["SandboxKit"]
        ),
        .target(
            name: "VPNKit",
            dependencies: ["CommandKit", "LocalizationKit", "InteropKit"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "VPNKitTests", dependencies: ["VPNKit"]),
        // MCP stdio 서버 전송/디스패치 루프. JSON/arg 안전 헬퍼는 MCPSupport 재사용.
        // 앱 홈 경로 + 제네릭 원자적 JSON store. 시스템 프레임워크만.
        .target(
            name: "AppPathsKit",
            dependencies: ["StateRootKit", "FastDiskIOKit"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(name: "AppPathsKitTests", dependencies: ["AppPathsKit"]),
        .target(name: "AgentPolicyKit", dependencies: ["StateRootKit"]),
        .target(name: "AgentTierKit", dependencies: ["AppPathsKit"]),
        .testTarget(name: "AgentPolicyKitTests", dependencies: ["AgentPolicyKit"]),
        .testTarget(name: "AgentTierKitTests", dependencies: ["AgentTierKit"]),
        // 파일 브라우저 코어 — 디렉터리 열거·Finder 태그·복사/이동/휴지통·압축,
        // FSEvents 감시, 한글 NFD→NFC 파일명 리네임. Foundation + CoreServices 만.
        // mq-dir(MIT) 이식 — Sources/FileBrowserKit/NOTICE.md 참조.
        // NOTICE.md 는 mq-dir(MIT) 출처 고지 문서다. 소스 옆에 둬야 이식본과 같이
        // 읽히므로 위치는 유지하고, SwiftPM 이 리소스로 오해해 매 빌드 경고를
        // 내지 않도록 명시적으로 제외한다.
        .target(name: "FileBrowserKit", exclude: ["NOTICE.md"]),
        .testTarget(name: "FileBrowserKitTests", dependencies: ["FileBrowserKit"]),
        // Codable JSON 파일 저장소. 시스템 프레임워크만.
        .target(name: "FileStorageKit"),
        // SCK 캡처 공용. 권한 게이트는 PermissionKit 재사용.
        .target(name: "ScreenGrabKit", dependencies: ["PermissionKit"]),
        .testTarget(name: "ScreenGrabKitTests", dependencies: ["ScreenGrabKit"]),
        // AX 트리 읽기 primitive.
        .target(name: "AXTreeKit"),
        .testTarget(name: "AXTreeKitTests", dependencies: ["AXTreeKit"]),
        .testTarget(name: "GameAsset2DKitTests", dependencies: ["GameAsset2DKit"]),
        .testTarget(name: "PixelKitTests", dependencies: ["PixelKit"]),
        // 앱 상호운용 계약(docs/app-interop-contract.md) 이행 공통: 봉투/능력/레지스트리.
        // 수제 페어와이즈 브릿지 N² 대신 각 CLI 가 몇 줄로 계약을 이행하게 한다.
        .target(name: "InteropKit", dependencies: ["PackageIdentityKit"]),
        .testTarget(name: "InteropKitTests", dependencies: ["InteropKit"]),
        .target(name: "MarketingVersionKit"),
        .testTarget(name: "MarketingVersionKitTests", dependencies: ["MarketingVersionKit"]),
        // PIM 스위트(pim-calendar·pim-todo·pim-mail·pim-contacts·pim-notes·pim-agenda) 공용:
        // 공유 vault(~/PimVault) 모델·원자적 JSON 저장소·agenda 집계·CLI 날짜/봉투 공통기.
        .target(name: "PimKit", dependencies: ["StateRootKit"]),
        .testTarget(name: "PimKitTests", dependencies: ["PimKit"]),
        // 재무 원장 공용 킷 — pim-calendar 방식 system SQLite3(외부 ORM 금지),
        // 민감정보(계좌·카드 전체번호)는 로컬에 저장하지 않고 Vaultwarden Secure Note 로.
        // 순수 모델 타입은 MoneyLedgerModels 로 빠졌고, 여기서는 @_exported 로 재노출한다.
        .target(
            name: "MoneyLedgerModels",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
            ]
        ),
        .target(
            name: "MoneyLedgerStoreKit",
            dependencies: ["MoneyLedgerModels"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(name: "MoneyLedgerImportKit", dependencies: ["MoneyLedgerStoreKit", "MoneyLedgerModels", "CommandKit", "InteropKit"]),
        .target(name: "MoneyLedgerReportKit", dependencies: ["MoneyLedgerModels"]),
        .target(
            name: "MoneyLedgerVaultKit",
            dependencies: ["MoneyLedgerStoreKit", "MoneyLedgerModels", "VaultwardenKit", "CommandKit", "InteropKit"]
        ),
        .target(
            name: "MoneyLedgerKit",
            dependencies: [
                "MoneyLedgerModels", "MoneyLedgerStoreKit", "MoneyLedgerImportKit",
                "MoneyLedgerReportKit", "MoneyLedgerVaultKit",
            ]
        ),
        .testTarget(
            name: "MoneyLedgerKitTests",
            // @testable 은 우산을 통과하지 못한다 — 내부를 여는 타깃을 직접 건다.
            dependencies: [
                "MoneyLedgerModels", "MoneyLedgerStoreKit", "MoneyLedgerImportKit",
                "MoneyLedgerReportKit", "MoneyLedgerVaultKit",
            ]
        ),
        .target(name: "MoneyLedgerCLIKit", dependencies: ["MoneyLedgerKit", "MoneyLedgerReportKit", "InteropKit", "CommandKit"]),
        .testTarget(name: "MoneyLedgerCLIKitTests", dependencies: ["MoneyLedgerCLIKit"]),
        .target(name: "MoneyLedgerUIKit", dependencies: ["MoneyLedgerKit"]),
        // 회계·세무 순수 Kit — 의존은 MoneyLedgerModels(값 타입·RuleConfidence) 와, JSON 리소스를
        // 설치본에서도 안전하게 찾기 위한 LocalizationKit.ResourceBundle 뿐(Bundle.module 금지 lint).
        .target(
            name: "MoneyAccountingKit",
            dependencies: ["MoneyLedgerModels", "LocalizationKit"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "MoneyAccountingKitTests", dependencies: ["MoneyAccountingKit", "MoneyLedgerModels"]),
        .target(
            name: "KoreanTaxRulesKit",
            dependencies: ["MoneyLedgerModels", "LocalizationKit"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "KoreanTaxRulesKitTests", dependencies: ["KoreanTaxRulesKit", "MoneyLedgerModels"]),
        .testTarget(name: "FleetDeskKitTests", dependencies: ["FleetDeskKit"]),
        .testTarget(
            name: "AppWindowKitTests",
            dependencies: [
                "AppWindowKit",
                "AppErrorKit",
                "NoticeBannerUIKit",
                "LocalizationKit",
            ]
        ),
        .testTarget(name: "WindowChromeKitTests", dependencies: ["WindowChromeKit"]),
        .testTarget(name: "FreshnessKitTests", dependencies: ["FreshnessKit"]),
        .testTarget(name: "SettingsKitTests", dependencies: ["SettingsKit"]),
        .testTarget(name: "LaunchAtLoginKitTests", dependencies: ["LaunchAtLoginKit"]),
        .testTarget(name: "PrivilegedHelperKitTests", dependencies: ["PrivilegedHelperKit"]),
        .testTarget(name: "MCPSupportTests", dependencies: ["MCPSupport"]),
        .testTarget(name: "InstallerKitTests", dependencies: ["InstallerKit"]),
        .testTarget(name: "CommandKitTests", dependencies: ["CommandKit", "CommandKitTesting"]),
        .testTarget(name: "PrivilegedKitTests", dependencies: ["PrivilegedKit"]),
        .testTarget(name: "PermissionKitTests", dependencies: ["PermissionKit", "PermissionDialogKit"]),
        .testTarget(name: "InspectorKitTests", dependencies: ["InspectorKit"]),
        .testTarget(name: "InspectorStateTests", dependencies: ["InspectorState"]),
        .testTarget(
            name: "LocalizationKitTests",
            dependencies: ["LocalizationKit"],
            resources: [.process("Resources")]
        ),

        // Realtime combat / simulation kits (products declared; targets were missing).
        .target(name: "GameRealtimeStateKit"),
        .testTarget(name: "GameRealtimeStateKitTests", dependencies: ["GameRealtimeStateKit"]),
        .target(
            name: "GameRealtimeProtocolKit",
            dependencies: ["GameRealtimeStateKit"]
        ),
        .testTarget(name: "GameRealtimeProtocolKitTests", dependencies: ["GameRealtimeProtocolKit"]),
        .target(
            name: "GameRealtimeSimulationKit",
            dependencies: ["GameRealtimeStateKit", "GameRealtimeProtocolKit"]
        ),
        .testTarget(name: "GameRealtimeSimulationKitTests", dependencies: ["GameRealtimeSimulationKit"]),
        .target(
            name: "GameRealtimeRuntimeKit",
            dependencies: [
                "GameRealtimeStateKit",
                "GameRealtimeProtocolKit",
                "GameRealtimeSimulationKit",
            ]
        ),
        .testTarget(name: "GameRealtimeRuntimeKitTests", dependencies: ["GameRealtimeRuntimeKit"]),
        .target(
            name: "GameRealtimeEngineKit",
            dependencies: ["GameRealtimeProtocolKit", "GameRealtimeRuntimeKit", "GameRealtimeStateKit"]
        ),
        .testTarget(name: "GameRealtimeEngineKitTests", dependencies: ["GameRealtimeEngineKit"]),
        .target(
            name: "GameRealtimeDebugKit",
            dependencies: [
                "GameRealtimeStateKit",
                "GameRealtimeProtocolKit",
                "GameRealtimeSimulationKit",
                "GameRealtimeRuntimeKit",
                "GameRealtimeEngineKit",
            ]
        ),
        .testTarget(
            name: "GameRealtimeDebugKitTests",
            dependencies: ["GameRealtimeDebugKit"],
            resources: [.copy("Fixtures/GameRealtimeDeterminismV1")]
        ),
        .executableTarget(
            name: "GameRealtimeBenchmark",
            dependencies: ["GameRealtimeDebugKit", "GameRealtimeEngineKit", "GameRealtimeProtocolKit", "LocalizationKit"],
            resources: [.copy("Resources/GameRealtimeBenchmarkV1")]
        ),
        .testTarget(name: "GameRealtimeBenchmarkTests", dependencies: ["GameRealtimeDebugKit"]),
        .testTarget(name: "GameRealtimePackageGraphTests"),
        .target(name: "GameSimulationStateKit"),
        .testTarget(name: "GameSimulationStateKitTests", dependencies: ["GameSimulationStateKit"]),
        .target(name: "GameSimulationProtocolKit"),
        .testTarget(name: "GameSimulationProtocolKitTests", dependencies: ["GameSimulationProtocolKit"]),
        .target(
            name: "GameSimulationReducerKit",
            dependencies: ["GameSimulationStateKit"]
        ),
        .testTarget(name: "GameSimulationReducerKitTests", dependencies: ["GameSimulationReducerKit"]),
        .target(
            name: "GameSimulationRuntimeKit",
            dependencies: [
                "GameSimulationStateKit",
                "GameSimulationProtocolKit",
                "GameSimulationReducerKit",
            ]
        ),
        .testTarget(name: "GameSimulationRuntimeKitTests", dependencies: ["GameSimulationRuntimeKit"]),
        // 방치형 정산 계층. 시계는 GameRealtimeRuntimeKit 의 GameRealtimeClock 을 재사용한다.
        .target(
            name: "GameIdleSettlementKit",
            dependencies: ["GameRealtimeRuntimeKit"]
        ),
        .testTarget(
            name: "GameIdleSettlementKitTests",
            dependencies: ["GameIdleSettlementKit"]
        ),
        .target(name: "GameUIRuntimeTreeKit"),
        .testTarget(name: "GameUIRuntimeTreeKitTests", dependencies: ["GameUIRuntimeTreeKit"]),
        .target(name: "PromptKit"),
        .target(name: "ZipArchiveKit"),
        .testTarget(name: "ZipArchiveKitTests", dependencies: ["ZipArchiveKit"]),
        .target(name: "HwpxComposeKit"),
        .testTarget(name: "HwpxComposeKitTests", dependencies: ["HwpxComposeKit"]),
        .target(name: "YamlKit"),
        .testTarget(name: "YamlKitTests", dependencies: ["YamlKit"]),
        .target(name: "PagePlanningKit", dependencies: ["YamlKit"]),
        .testTarget(name: "PagePlanningKitTests", dependencies: ["PagePlanningKit", "YamlKit"]),
        // Carbon(RegisterEventHotKey/InstallEventHandler) 기반 전역 단축키 + SwiftUI Recorder.
        // 시스템 프레임워크만 써서 외부 SPM(KeyboardShortcuts) 의존을 대체한다.
        .target(name: "HotKeyKit"),
        .testTarget(name: "HotKeyKitTests", dependencies: ["HotKeyKit"]),
        .target(
            name: "TenantGuardKit",
            dependencies: ["StateRootKit"]
        ),
        .testTarget(name: "TenantGuardKitTests", dependencies: ["TenantGuardKit"]),
        .target(
            name: "PluginKit",
            dependencies: ["InteropKit", "OrganKit", "StateMirrorKit", "StateRootKit"]
        ),
        .testTarget(
            name: "PluginKitTests",
            dependencies: ["PluginKit"]
        ),
        // 정부지원금 패밀리 공통 도메인/크롤러/상태/카탈로그 킷
        .target(
            name: "MoneySourceKit",
            dependencies: [
                "MoneyInflowKit",
                "WebCrawlKit",
                "HTTPClientKit",
                "StateMirrorKit",
                "StateRootKit",
                "LocalizationKit",
                "InteropKit",
            ]
        ),
        .testTarget(name: "MoneySourceKitTests", dependencies: ["MoneySourceKit"]),
        .target(name: "MoneyRevenueRecognitionKit"),
        .testTarget(name: "MoneyRevenueRecognitionKitTests", dependencies: ["MoneyRevenueRecognitionKit"]),
        .target(name: "MoneyFXKit"),
        .testTarget(name: "MoneyFXKitTests", dependencies: ["MoneyFXKit"]),
        .target(name: "LoanScheduleKit"),
        .testTarget(name: "LoanScheduleKitTests", dependencies: ["LoanScheduleKit"]),
        .target(
            name: "BankScraperKit",
            dependencies: ["MoneyAccountingKit", "MoneyLedgerModels"]
        ),
        .testTarget(name: "BankScraperKitTests", dependencies: ["BankScraperKit"]),
        .target(name: "ThrottledParallelKit"),
        .testTarget(name: "ThrottledParallelKitTests", dependencies: ["ThrottledParallelKit"]),
        .target(name: "IncrementalExecutionKit"),
        .testTarget(name: "IncrementalExecutionKitTests", dependencies: ["IncrementalExecutionKit"]),
        .target(name: "RoomPlacementKit", dependencies: ["StateRootKit", "SkillRegistryKit", "SessionKit"]),
        .target(name: "RoomSeatKit", dependencies: ["RoomPlacementKit", "StateRootKit", "SessionKit", "FastDiskIOKit"]),
        .target(
            name: "RoomKit",
            dependencies: [
                "RoomPlacementKit",
                "RoomSeatKit",
                "StateRootKit",
                "SkillRegistryKit",
                "SessionKit",
                "AppPathsKit",
                "CommandKit",
            ]
        ),
        .testTarget(name: "RoomKitTests", dependencies: ["RoomKit", "RoomPlacementKit"]),
        .target(name: "AgentTriageKit", dependencies: ["StateRootKit"]),
        .testTarget(name: "AgentTriageKitTests", dependencies: ["AgentTriageKit"]),
        .target(name: "SecretMaskKit"),
        .testTarget(name: "SecretMaskKitTests", dependencies: ["SecretMaskKit"]),
        .target(name: "FleetPerspectiveModelKit"),
        .target(
            name: "FleetCockpitPerspectiveKit",
            dependencies: [
                "FleetPerspectiveModelKit",
                "CommandKit",
                "InteropKit",
                "StateRootKit",
            ]
        ),
        .testTarget(
            name: "FleetCockpitPerspectiveKitTests",
            dependencies: ["FleetCockpitPerspectiveKit"]
        ),
        .target(
            name: "APFSSnapshotKit",
            dependencies: ["CommandKit"]
        ),
        .testTarget(
            name: "APFSSnapshotKitTests",
            dependencies: ["APFSSnapshotKit", "CommandKit"]
        ),
        .target(
            name: "ChunkDedupKit",
            dependencies: ["FastDiskIOKit"],
            swiftSettings: [
                .unsafeFlags(["-Onone"])
            ]
        ),
        .testTarget(
            name: "ChunkDedupKitTests",
            dependencies: ["ChunkDedupKit"]
        ),
        .target(
            name: "SparsebundleKit"
        ),
        .testTarget(
            name: "SparsebundleKitTests",
            dependencies: ["SparsebundleKit"]
        ),
        .target(
            name: "MachineIdentityKit",
            dependencies: ["CommandKit"]
        ),
        .testTarget(
            name: "MachineIdentityKitTests",
            dependencies: ["MachineIdentityKit"]
        ),
        .target(name: "LaunchAgentKit", dependencies: ["CommandKit"]),
        .testTarget(name: "LaunchAgentKitTests", dependencies: ["LaunchAgentKit"]),
        .target(
            name: "ContentAddressedAssetKit",
            dependencies: []
        ),
        .testTarget(
            name: "ContentAddressedAssetKitTests",
            dependencies: ["ContentAddressedAssetKit"]
        ),
        .target(
            name: "TenantDocumentVaultKit",
            dependencies: ["ContentAddressedAssetKit", "StateRootKit"]
        ),
        .testTarget(
            name: "TenantDocumentVaultKitTests",
            dependencies: ["TenantDocumentVaultKit"]
        ),
        .target(
            name: "WorkflowPipelineKit",
            dependencies: ["ContentAddressedAssetKit"]
        ),
        .testTarget(
            name: "WorkflowPipelineKitTests",
            dependencies: ["WorkflowPipelineKit"]
        ),
        .target(
            name: "ReleaseReceiptKit",
            dependencies: ["FastDiskIOKit"]
        ),
        .testTarget(
            name: "ReleaseReceiptKitTests",
            dependencies: ["ReleaseReceiptKit"]
        ),
        .target(name: "FlowChartUIKit"),
        .testTarget(name: "FlowChartUIKitTests", dependencies: ["FlowChartUIKit"]),
        .target(name: "GanttChartUIKit"),
        .testTarget(name: "GanttChartUIKitTests", dependencies: ["GanttChartUIKit"]),
        .target(name: "MetricGaugeUIKit"),
        .testTarget(name: "MetricGaugeUIKitTests", dependencies: ["MetricGaugeUIKit"]),
        .target(
            name: "SphereViewport3DUIRuntimeKit",
            linkerSettings: [.linkedFramework("SceneKit")]
        ),
        .testTarget(
            name: "SphereViewport3DUIRuntimeKitTests",
            dependencies: ["SphereViewport3DUIRuntimeKit"]
        ),
        .target(name: "InteractiveGestureHapticKit"),
        .testTarget(
            name: "InteractiveGestureHapticKitTests",
            dependencies: ["InteractiveGestureHapticKit"]
        ),
        // MARK: - Opportunity Fleet Kits (도메인 중립 기회/공고/딜 수집·분석·UI)
        .target(
            name: "OpportunityIntelKit",
            dependencies: []
        ),
        .testTarget(
            name: "OpportunityIntelKitTests",
            dependencies: ["OpportunityIntelKit"]
        ),
        .target(
            name: "OpportunityIngestKit",
            dependencies: ["WebCrawlKit", "HTTPClientKit", "OpportunityIntelKit"]
        ),
        .testTarget(
            name: "OpportunityIngestKitTests",
            dependencies: ["OpportunityIngestKit"]
        ),
        .target(
            name: "OpportunityTimelineUIKit",
            dependencies: ["OpportunityIntelKit"]
        ),
        .target(
            name: "ProcessAppIdentityKit",
            dependencies: []
        ),
        .testTarget(
            name: "ProcessAppIdentityKitTests",
            dependencies: ["ProcessAppIdentityKit"]
        ),
        .target(
            name: "ProcessTerminationKit",
            dependencies: ["PrivilegedKit"]
        ),
        .testTarget(
            name: "ProcessTerminationKitTests",
            dependencies: ["ProcessTerminationKit"]
        ),
        .target(
            name: "MarkdownSSOTKit",
            dependencies: []
        ),
        .testTarget(
            name: "MarkdownSSOTKitTests",
            dependencies: ["MarkdownSSOTKit"]
        ),
        .target(
            name: "AppContractTestKit",
            dependencies: ["StateMirrorKit"]
        ),
        .testTarget(
            name: "AppContractTestKitTests",
            dependencies: ["AppContractTestKit"]
        ),
        .target(
            name: "SurfaceParityKit",
            dependencies: ["StateMirrorKit", "AppContractTestKit"]
        ),
        .testTarget(
            name: "SurfaceParityKitTests",
            dependencies: ["SurfaceParityKit"]
        ),
        .target(
            name: "ISO8601DateCodecKit"
        ),
        .testTarget(
            name: "ISO8601DateCodecKitTests",
            dependencies: ["ISO8601DateCodecKit"]
        ),
        .target(
            name: "HomeostasisEngineKit",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
            ]
        ),
        .testTarget(
            name: "HomeostasisEngineKitTests",
            dependencies: ["HomeostasisEngineKit"]
        ),
        .target(
            name: "FastDiskIOKit",
            dependencies: ["HomeostasisEngineKit", "StateRootKit"],
            exclude: {
#if os(Linux)
                ["PersistentFSEventsWatcher.swift", "StreamCompressor.swift"]
#else
                [String]()
#endif
            }()
        ),
        .testTarget(
            name: "FastDiskIOKitTests",
            dependencies: ["FastDiskIOKit"]
        ),
        .target(
            name: "RuleMiningEngineKit",
            dependencies: ["HomeostasisEngineKit", "StateRootKit"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(
            name: "CognitiveHomeostasisKit",
            dependencies: [
                "HomeostasisEngineKit",
                "StateRootKit",
                "InteropKit",
                "FastDiskIOKit",
            ]
        ),
        .testTarget(
            name: "CognitiveHomeostasisKitTests",
            dependencies: ["CognitiveHomeostasisKit"]
        ),
        .target(
            name: "RuleMiningKit",
            dependencies: [
                "RuleMiningEngineKit",
                "CognitiveHomeostasisKit",
                "HomeostasisEngineKit",
                "StateRootKit",
                "InteropKit",
                "SessionKit",
                "GraphEngineKit",
                "CommandKit",
                "FastDiskIOKit",
            ]
        ),
        .testTarget(
            name: "RuleMiningKitTests",
            dependencies: ["RuleMiningKit"]
        ),
        .target(
            name: "AwakeRestReplayKit",
            dependencies: []
        ),
        .testTarget(
            name: "AwakeRestReplayKitTests",
            dependencies: ["AwakeRestReplayKit"]
        ),
        .target(
            name: "TranscriptLibraryKit",
            dependencies: ["FastDiskIOKit"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "TranscriptLibraryKitTests",
            dependencies: ["TranscriptLibraryKit"]
        ),
        .target(
            name: "AppPersistenceKit",
            dependencies: ["FastDiskIOKit"]
        ),
        .testTarget(
            name: "AppPersistenceKitTests",
            dependencies: ["AppPersistenceKit"]
        ),
        .target(
            name: "StealthKit",
            dependencies: ["StateRootKit", "LocalizationKit"],
            resources: [.process("Resources")]
        ),
        .target(name: "CDPCredentialFilterKit"),
        .target(name: "ChromiumCDPEndpointKit"),
        .target(name: "BehaviorSimulatorKit"),
        // Git Tree OID 추출 및 SQLite WAL 기반 5ms 영수증 원장
        .target(
            name: "GitMerkleReceiptKit",
            dependencies: [
                "FastDiskIOKit",
                "CommandKit",
                "InteropKit",
                "ISO8601DateCodecKit",
                "DoctorContract",
            ],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "GitMerkleReceiptKitTests",
            dependencies: ["GitMerkleReceiptKit"]
        ),
        // 2단계 SHA256 캐시, 단일 패스 AST 디스패처
        .target(
            name: "FastLintCoreKit",
            dependencies: [
                "SwiftSourceKit",
                "FastDiskIOKit",
                "ConcurrencyKit",
            ]
        ),
        .testTarget(
            name: "FastLintCoreKitTests",
            dependencies: ["FastLintCoreKit"]
        ),
        // 4레인 실시간 반응형 TUI 및 Chrome DevTools Trace Event 내보내기
        .target(
            name: "LintObservabilityKit",
            dependencies: [
                "FastDiskIOKit",
            ]
        ),
        .testTarget(
            name: "LintObservabilityKitTests",
            dependencies: ["LintObservabilityKit"]
        ),
        // 모노레포 전체 아키텍처 AST 메타모델, 거버넌스 사면체, 그래프 분석 및 검증 IR
        .target(
            name: "ArchitectureIRKit",
            dependencies: ["ISO8601DateCodecKit"]
        ),
        .testTarget(
            name: "ArchitectureIRKitTests",
            dependencies: ["ArchitectureIRKit"]
        ),
        .testTarget(
            name: "JSONLJournalKitTests",
            dependencies: ["JSONLJournalKit", "CommandKit"]
        ),
        .target(
            name: "TestingAdapterKit",
            dependencies: [
                "CommandKit",
                "StateMirrorKit",
                "StateRootKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "TestingAdapterKitTests",
            dependencies: [
                "TestingAdapterKit",
                "CommandKit",
                "StateMirrorKit",
                "StateRootKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
    ]
)
