# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.23] - 2026-09-21
### Changed
- Hosts come from EndpointRouterKit, not baked cluster DNS.

## [1.0.22] - 2026-09-17
### Fixed
- Localizable.strings 문자열 인자 포맷 지정자 불일치 수정 및 `CLILocalization.text` 안전 보간 전환.

## [1.0.20] - 2026-09-17
### Changed
- CLI 진입점의 `nonisolated(unsafe) var asyncExitCode` 및 수동 CFRunLoop 제거, `AgentCLICommand.runSync` 기반 원자적/동기 안전 진입으로 정규화.

## [1.0.19] - 2026-09-09

### Added
- **wiki**: world display names and scene-evidence objects (a0d0ccc)
- MenuBarPopoverUIKit·MoneyInflowUIKit 기계 치환 (bb0db93)
- **swiftkit**: extract CopyButton, ErrorBanner, StatusBadge into shared UI kits (21b72c8)
- **l10n**: fleet-wide String wrapping for numeric format args across 100 apps (baa121b)
- **l10n**: wrap numeric format args with String in agent-* apps (0b4a792)
- **fleet**: capabilities StateMirror 미선언 일괄 채움 (25be5dd)
- **ai-agent-config,ai-cli-account**: Antigravity 에이전트 통합 및 Package.resolved v2 정규화 (e08571f)
- **i18n**: 삼항·보간 한글 UI를 L10n으로 이동 (2d9cb92)
- **i18n**: 함대 L10n 전환과 영문 카탈로그 번역 (2b9276f)
- **entitlement**: EntitlementKit SSOT 단일화 (54083c2)
- **fleet**: 188개 GUI 앱 FleetDesk 정책 채택 — App.init에 applyFleetDeskPolicy (c053c40)
- **CommandKit**: inline waitWithTimeout watchdogs call ProcessWait.untilExit (4088f0e)
- **windowchrome**: 함대 카탈로그 창을 WindowChromeKit으로 옮기고 lint 필수 규칙 추가 (7181be4)
- **i18n**: B등급 앱에 언어 피커와 하드코딩 한글 제거를 넣어 A로 올린다 (a44600b)
- **wiki**: 테넌트 1인칭과 공유 원장을 갈라 두고 GitLab 웹 주소를 맞춘다 (dbb6355)
- **identity**: backfill agent_surface on 165 apps (c152bda)
- adopt app.sqlite layout on scaffold-shaped fleet apps (df0d265)
- **fleet**: surface translation-coverage under Settings language picker (f97ee0c)
- **apps**: remaining apps에 Telemetry trait 추가 (4b93c08)
- **store**: fill remaining gujo-product manifests (b911038)
- HealthPulse 배치 연결 169개 앱 (9a7dcb7)
- **agent-wiki**: world self-test — SelfTestKit 첫 채택 (96bf44c)
- **agent-wiki**: world rm — add 의 짝, world 정의만 제거(디렉터리 보존) (b63e672)
- **agent-wiki**: 개인 world도 gujo로 승격 가능하게 — repo 전용 게이트 제거 (e4c681f)
- **app-fleet-quality-auditor**: quality-contract 채택 aspect — 367앱 미채택을 3건으로 (30e6034)
- **agent-wiki**: extract KnowledgeBaseWikiUI to agent-wiki-ui package (0d8941d)
- **agent-wiki**: monlith compat shell banner; Reader/Studio open ledger on launch (71a3d2d)
- **agent-wiki**: extract KnowledgeBaseWikiUI; Reader/Studio host Ledger in-process (78c5868)
- **agent-wiki**: Reader/Studio hand off to monlith surface (98ab000)
- **adm**: embed extra_clis/full_cli_product into Helpers (6ca326c)
- **agent-wiki**: split monlith into kit, Studio CLI, Reader (5094bdf)

### Changed
- **fleet**: backfill package-identity UUIDs across 480 apps (afc33b8)
- **store**: drop per-app pricing.json for Gujo Pass (f953a00)
- bump marketing versions for apps this MR changes (5fe919f)
- **agent-wiki**: promote CommandRepository to WikiCLIShared and remove duplicate CLI files (-90 lines) (63927f8)
- **agent-wiki**: promote CommandPull to WikiCLIShared and remove duplicate CLI files (-237 lines) (56ae0e7)
- **agent-wiki**: promote CommandWeight to WikiCLIShared and remove duplicate CLI files (-182 lines) (a290a6d)
- **agent-wiki**: promote GujoWikiRemote to WikiCLIShared and remove duplicate CLI files (-84 lines) (f215533)
- **agent-wiki-studio-swift**: package-identity purpose·state_root_env (9828015)
- **fleet**: 10개 도메인 전수 레거시 Package.swift 타 앱 직접 참조 소각 및 PluginKit 단일 SSOT 리팩토링 (3baf2c9)
- **fleet**: CI 지적 122앱 마케팅 버전 bump — marketing-version-bump 차단 해소 (115f759)
- **fleet**: bump marketing versions for capabilities statemirror update (0635f62)
- 예측 스윕 기준 bump 누락 166앱 전량 patch bump (54c404a)
- **i18n**: 소스 변경 앱 396종 marketing version patch bump (73681b8)
- **fleet**: 차단 위반 전수 해소 — lineLimit frame 318건 + gujo-managed-gate + package-manifest-static (dc73663)
- 설정 씬 전환 앱 마케팅 버전 patch (58f03cf)
- **agent-wiki-studio**: 마케팅 버전 1.0.6 — 안내문 정정 반영 (12f40d9)
- app-distribution-manager → app-build-manager (f9cc928)
- messy_bool_mixed v6-v7 succeeded 산출물 — lint 0건 검증 통과분 (af56c56)
- **apps**: /opt/homebrew 잔여 123파일 치환 — score 99/100 (d1f907b)
- **apps**: /opt/homebrew hardcode 292파일 추가 HostPlatform SSOT 이관 (db5d0bd)
- **apps**: /opt/homebrew hardcode 일괄 HostPlatform SSOT 이관 (df75835)
- Sparkle SSOT — SelfUpdating trait로 통일 (324cd99)
- **fleet**: 출시 버전 1.0.0 — 0.x 앱 154개 + set-version 도달 불가 수정 (cc46035)
- **fleet**: 계약 채택 36앱 — pulse/state-mirror/interop 골격 (43af60d)

### Fixed
- **hosts**: rewrite retired Gujo domains in product json and docs (fe1234e)
- **lint**: 70개 앱 마케팅 버전 범프 및 네이티브 린트 하드 게이트 전수 올그린 교정 (7cd36fe)
- drop lint-lane swiftkit products from UI kit Package.swift (feb7112)
- **lint**: 전수 재현 잔여 수리 — 워커 2차분(39건)+마지막 4건 (0a72b17)
- **lint**: 워커 3차 수리분 적재 — agent-cli-manager·control-plane·deck 계열 (909d78a)
- **lint**: secrets 오탐(포맷 지정자) 면제 + 워커 2차 수리분 적재 (6b48590)
- **sparkle**: 다창 앱 설정 Window를 Settings 씬으로 옮긴다 (a6406b6)
- **agent-wiki-studio**: leftover HealthPulse 복제 제거와 화면·삼킴 분할 (dad80da)
- **agent-wiki-studio**: gujo blob 안내문의 옛 garage 시드 표기 정정 (a88cb67)
- **agent-wiki-studio**: 런치 시 상태 미러를 1회 게시한다 (e3a7a4d)
- **wiki**: Bundle.module → LocalizationKit 리졸버 + WindowChromeKit 채택 (8a84fb8)
- **landing**: 검증 꼬리를 전부 초록으로 — CommandKitSync 교착 근본 수리 (9c09c2e)
- **swiftkit**: hoist CommandKitSync into CommandKit (f948850)
- **apps**: raw Process()를 CommandKit으로 (3e4877b)
- **agent-wiki-studio**: clear i18n hard/errors (hard=0) (ddaaf41)
- **fleet**: version/capabilities 리터럴을 CLIMarketingVersion 으로 교체 (e5fa001)
- **lint**: import-dependency-match a~m 앱 해소 (bde759b)
- **fleet**: package-level .product() 오삽입 62앱 제거 + Package.resolved 79앱 생성 (7065066)
- **fleet**: InteropKit 의존 누락 227앱 일괄 수정 (v2) (934b144)
- **lint**: Grok 적대적 리뷰 CRITICAL/HIGH 수정 (0318577)
- **fleet**: version policy + audit appsDir + distribution marking (62435b5)
- **gitlab**: 접속 주소를 앱마다 박지 말고 정본 카탈로그에 묻는다 (b3ce45d)
- **cli**: --json 이 {ok,result} 계약 봉투를 쓰게 (env-c) (b938d43)
- **agent-wiki**: ignore ephemeral SASource path; open Reader/Studio windows (cbc4405)
- **agent-wiki**: product display names; drop monlith agent-wiki interop (382cc34)
