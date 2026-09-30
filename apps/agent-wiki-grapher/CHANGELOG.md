# Changelog

All notable changes to `agent-wiki-graph-swift` will be documented in this file.

## [1.0.13] - 2026-09-26

### Changed
- Rename targets to the AgentWikiGrapher prefix (app-structural-parity); products unchanged

## [1.0.12] - 2026-09-25
### Fixed
- The CLI compiles in Swift 6 mode again. A static `ISO8601DateFormatter` is not Sendable; dates now use `Date.formatted(.iso8601)`, which gives the same output.

## [1.0.11] - 2026-09-24

### Fixed
- Complete SafeProcessRunner migration broken by 86c79a277e.

## [1.0.10] - 2026-09-17

### Fixed
- DateFormatter/ISO8601DateFormatter 정적 캐시 전환으로 핫패스 할당 최적화

## [1.0.9] - 2026-09-09
### Changed
- CLI `version` / `--version` / `capabilities --json` 마케팅 스탬프를 호스트 Info.plist `CFBundleShortVersionString`과 맞춘다.
