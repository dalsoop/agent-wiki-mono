# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.21] - 2026-09-19
### Changed
- Align state directory and storage paths to use `StateRootKit.ensureCustomerRoomStorage(slug:)` in `AppPaths` for customer room environments.

## [1.0.20] - 2026-09-18
### Added
- CLI task, orchestration, repository, repository-summary, run, sync, evolve, role 라우팅 복구 및 CommandTask 구현 추가.
- --path 인자 지원 추가.

## [1.0.19] - 2026-09-17
### Fixed
- Localizable.strings 문자열 인자 포맷 지정자 불일치 수정 (`%d` 계열 -> `%@` 계열).

## [1.0.18] - 2026-09-17
### Changed
- CLI 진입점의 `nonisolated(unsafe) var asyncExitCode` 및 수동 CFRunLoop 제거, `AgentCLICommand.runSync` 기반 원자적/동기 안전 진입으로 정규화.

## [1.0.17] - 2026-09-09

### Added
- **agent-wiki**: expose human-friendly display names for worlds and support scene evidence backlinks (2409fa9)
- **agent-wiki**: support alias:* tags in show lookup (6dec888)
- **agent-wiki-global**: swiftkit-appscaffold 채택 — Cloud Apps 관리 게이트 정식 통과 (1.0.14) (bb68f79)
- **agent-wiki-global**: 테넌트 world·인용 게이트 채택 (eef3f8a)
- MenuBarPopoverUIKit·MoneyInflowUIKit 기계 치환 (bb0db93)
- **l10n**: wrap numeric format args with String in agent-* apps (0b4a792)
- **ai-agent-config,ai-cli-account**: Antigravity 에이전트 통합 및 Package.resolved v2 정규화 (e08571f)
- **i18n**: 함대 L10n 전환과 영문 카탈로그 번역 (2b9276f)
- **app-icon-forge**: pin-all-fleet 기능 + 함대 아이콘 일괄 갱신 (d85e651)
- **entitlement**: EntitlementKit SSOT 단일화 (54083c2)
- **CommandKit**: inline waitWithTimeout watchdogs call ProcessWait.untilExit (4088f0e)
- **agent-wiki**: 글로벌·로컬 앱 분리 — WikiCLIShared + agent-wiki-global + agent-wiki-local (ab57099)

### Changed
- **fleet**: backfill package-identity UUIDs across 480 apps (afc33b8)
- **agent-wiki**: promote CommandPull to WikiCLIShared and remove duplicate CLI files (-237 lines) (56ae0e7)
- **agent-wiki**: promote CommandWeight to WikiCLIShared and remove duplicate CLI files (-182 lines) (a290a6d)
- **agent-wiki**: promote GujoWikiRemote to WikiCLIShared and remove duplicate CLI files (-84 lines) (f215533)
- **agent-wiki-global**: 마케팅 버전 1.0.15 — push 훅 marketing-version-bump 재범프 (a231275)
- **agent-wiki-global-swift**: package-identity purpose·state_root_env (c63d111)
- **fleet**: 10개 도메인 전수 레거시 Package.swift 타 앱 직접 참조 소각 및 PluginKit 단일 SSOT 리팩토링 (3baf2c9)
- 예측 스윕 기준 bump 누락 166앱 전량 patch bump (54c404a)
- **i18n**: 소스 변경 앱 396종 marketing version patch bump (73681b8)
- **agent-wiki-global**: 마케팅 버전 1.0.4 — 안내문 정정·수리 반영 (c94489d)

### Fixed
- **lint**: 70개 앱 마케팅 버전 범프 및 네이티브 린트 하드 게이트 전수 올그린 교정 (7cd36fe)
- **lint**: 전수 재현 잔여 수리 — 워커 2차분(39건)+마지막 4건 (0a72b17)
- **lint**: secrets 오탐(포맷 지정자) 면제 + 워커 2차 수리분 적재 (6b48590)
- **sparkle**: unique 슬롯을 점검에 올리고 Extra 19앱을 wrap 한다 (dc3cd02)
- **sparkle**: 설정에 함대 업데이트 섹션이 두 번 붙지 않게 한다 (36b2980)
- **agent-wiki-global**: leftover HealthPulse 복제 제거와 화면·삼킴 분할 (b6f7f55)
- **agent-wiki-global**: garage→R2 안내문 정정 + 앱 분리 랜딩의 잠복 빌드 결함 2건 수리 (b1fe587)
- import-dependency-match 잔여 37건 — 전이 import 모듈을 타깃 의존성에 명시 (0746150)
