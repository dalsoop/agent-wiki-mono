# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.13] - 2026-09-17
### Fixed
- Localizable.strings 문자열 인자 포맷 지정자 불일치 수정 (`%d` 계열 -> `%@` 계열).

## [1.0.12] - 2026-09-13

### Changed
- `StateMirrorAdoption.publish(_ state: State)` 추가로 상태 미러링 생명주기 동기화 및 필드 유실 방지.

## [1.0.11] - 2026-09-09

### Added
- MenuBarPopoverUIKit·MoneyInflowUIKit 기계 치환 (bb0db93)
- **swiftkit**: extract CopyButton, ErrorBanner, StatusBadge into shared UI kits (21b72c8)
- **ai-agent-config,ai-cli-account**: Antigravity 에이전트 통합 및 Package.resolved v2 정규화 (e08571f)
- **i18n**: 삼항·보간 한글 UI를 L10n으로 이동 (2d9cb92)
- **i18n**: 함대 L10n 전환과 영문 카탈로그 번역 (2b9276f)
- **entitlement**: EntitlementKit SSOT 단일화 (54083c2)
- **fleet**: 188개 GUI 앱 FleetDesk 정책 채택 — App.init에 applyFleetDeskPolicy (c053c40)
- **windowchrome**: 함대 카탈로그 창을 WindowChromeKit으로 옮기고 lint 필수 규칙 추가 (7181be4)
- **i18n**: B등급 앱에 언어 피커와 하드코딩 한글 제거를 넣어 A로 올린다 (a44600b)
- **wiki**: 테넌트 1인칭과 공유 원장을 갈라 두고 GitLab 웹 주소를 맞춘다 (dbb6355)
- **fleet**: adopt remaining pulse/quality/interop and identity for 5 apps (475493e)
- **identity**: backfill agent_surface on 165 apps (c152bda)
- adopt app.sqlite layout on scaffold-shaped fleet apps (df0d265)
- **fleet**: surface translation-coverage under Settings language picker (f97ee0c)
- **apps**: remaining apps에 Telemetry trait 추가 (4b93c08)
- **store**: fill remaining gujo-product manifests (b911038)
- **app-fleet-quality-auditor**: quality-contract 채택 aspect — 367앱 미채택을 3건으로 (30e6034)
- **adoption**: plan/apply CLI gates for @main and non-main entries (23b819a)
- **agent-wiki**: extract KnowledgeBaseWikiUI to agent-wiki-ui package (0d8941d)
- **agent-wiki**: monlith compat shell banner; Reader/Studio open ledger on launch (71a3d2d)
- **agent-wiki**: extract KnowledgeBaseWikiUI; Reader/Studio host Ledger in-process (78c5868)
- **agent-wiki**: Reader/Studio hand off to monlith surface (98ab000)
- **agent-wiki**: split monlith into kit, Studio CLI, Reader (5094bdf)

### Changed
- **fleet**: backfill package-identity UUIDs across 480 apps (afc33b8)
- **store**: drop per-app pricing.json for Gujo Pass (f953a00)
- **agent-wiki-reader-swift**: package-identity purpose·state_root_env (1ec8ee5)
- **fleet**: CI 지적 122앱 마케팅 버전 bump — marketing-version-bump 차단 해소 (115f759)
- 예측 스윕 기준 bump 누락 166앱 전량 patch bump (54c404a)
- **i18n**: 소스 변경 앱 396종 marketing version patch bump (73681b8)
- **fleet**: 차단 위반 전수 해소 — lineLimit frame 318건 + gujo-managed-gate + package-manifest-static (dc73663)
- 설정 씬 전환 앱 마케팅 버전 patch (58f03cf)
- app-distribution-manager → app-build-manager (f9cc928)
- **apps**: /opt/homebrew hardcode 292파일 추가 HostPlatform SSOT 이관 (db5d0bd)
- **apps**: /opt/homebrew hardcode 일괄 HostPlatform SSOT 이관 (df75835)
- Sparkle SSOT — SelfUpdating trait로 통일 (324cd99)
- **fleet**: 출시 버전 1.0.0 — 0.x 앱 154개 + set-version 도달 불가 수정 (cc46035)

### Fixed
- **hosts**: rewrite retired Gujo domains in product json and docs (fe1234e)
- drop lint-lane swiftkit products from UI kit Package.swift (feb7112)
- **lint**: 워커 1차 위반 수리분 적재 — import deps·하드코딩 카탈로그 추출 (2e2519e)
- **sparkle**: 다창 앱 설정 Window를 Settings 씬으로 옮긴다 (a6406b6)
- **agent-wiki-reader**: leftover HealthPulse 복제 제거와 화면·삼킴 분할 (0fafd3f)
- **agent-wiki-reader**: clear i18n hard/errors (hard=0) (3aa1fa2)
- **fleet**: version/capabilities 리터럴을 CLIMarketingVersion 으로 교체 (e5fa001)
- **fleet**: package-level .product() 오삽입 62앱 제거 + Package.resolved 79앱 생성 (7065066)
- **fleet**: InteropKit 의존 누락 227앱 일괄 수정 (v2) (934b144)
- **fleet**: version policy + audit appsDir + distribution marking (62435b5)
- **agent-wiki**: ignore ephemeral SASource path; open Reader/Studio windows (cbc4405)
- **agent-wiki**: product display names; drop monlith agent-wiki interop (382cc34)
