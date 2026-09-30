# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.29] - 2026-10-01

### Changed
- 정본 저장소를 agent-wiki-mono 로 옮겼다(agent-wiki-mono 결정 0006). 동작은 1.0.28 과 같고, 설치본의 원천이 이 저장소가 된다.

## [1.0.28] - 2026-09-30

### Added
- 병합 개정: `publish --supersedes <id>` 를 반복하면 개정 하나가 여러 head 를 함께 대체한다(첫째는 `supersedes:`,
  나머지는 `supersedes-also:`). 옛 판 CLI 도 같은 id 를 재계산해 `verify` 가 통과한다. head·분류 승격·참조 검사·그래프가
  모든 부모를 보고, `history` 는 병합된 갈래를 들여 써서 함께 보인다(agent-wiki-mono 결정 0005, PR #6 과 같은 변경).

## [1.0.27] - 2026-09-30

### Changed
- The `install` subcommand no longer copies or links into PATH (shared `agent-wiki-kit` change). It prints guidance and exits 0. PATH linking is done only by the deploy tool (`app-build-manager ship`).
- The CLI version check re-probes the PATH CLI `version` when the stamp differs from the app version.

## [1.0.26] - 2026-09-26

### Changed
- Rename targets to the AgentWikiSynchronizer prefix (app-structural-parity); products unchanged

## [1.0.25] - 2026-09-25
### Fixed
- Fixed repository world resolution to dynamically resolve to the current worktree's `.wiki` when executed inside the same bare+worktree repository.
- Refused writes to the shared main slot `.wiki` or from outside the repository, enforcing dedicated worktrees for repository wiki mutations.
- `promotion repair-receipts --apply` now outputs the list of written files to commit.

## [1.0.24] - 2026-09-25
### Changed
- `gujo status` prints how to configure an endpoint instead of a dead clone URL; there is no default remote for the shared wiki. The internal GitLab (10.0.50.63) was retired on 2026-09-24.

## [1.0.23] - 2026-09-25
### Added
- Added `agent-wiki promotion repair-receipts [--world <w>] [--apply] [--json]` command to detect and repair missing half receipts across promotion source and target worlds.
### Fixed
- Fixed promotion publish write order and error recovery so that writing failures roll back partial state and never leave half receipts on either world.

## [1.0.22] - 2026-09-24
### Fixed
- The CLI compiles again: 86c79a277e's SafeProcessRunner migration removed the `Process` in `launchctl` but kept its wait loop. The 10 s timeout (124 on timeout) now comes from SafeProcessRunner.
- `verify` no longer fails a promotion receipt only because its source worktree was deleted or the origin remote moved (gitlab.ranode.net → gitlab.com changed every repoId). A registered world holding the same content-addressed object id is accepted as the source.

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
