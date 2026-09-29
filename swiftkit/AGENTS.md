# swiftkit

## 범위

공용 Swift 킷 약 100개를 담은 SwiftPM 패키지의 사본이다. 이 저장소의 패키지가 실제로 쓰는 킷은 다음과 같다.

| 킷 | 쓰는 곳 |
|---|---|
| `CommandKit`(SafeProcessRunner·CommandRunning) | 원장 엔진, 모든 앱 |
| `StateRootKit`(상태 루트·호스트 경로, `SWIFT_APP_STATE_ROOT`) | 원장 설정 경로, 모든 앱 |
| `InteropKit`(capabilities 계약), `AgentCLIKit`, `AgentSurfaceKit`, `SelfTestKit`, `PluginKit` | CLI 타깃 |
| `EndpointRouterKit`(호스트 해석, `endpoints-defaults.json`), `SigV4Kit`(S3 서명) | 원장 엔진의 원격 연결 |
| `DualEntryKit`, `RepositoryIdentityKit`, `FileBrowserKit` | 원장 엔진 |
| `LocalizationKit`, `StateMirrorKit`, `AppPathsKit`, `SingleInstanceKit`, `PrivilegedKit` | 앱 공통 |
| `MenuBarPopoverUIKit`, `SettingsUIKit`, `WindowChromeKit`, `NoticeBannerUIKit`, `OnboardingUIKit`, `LaunchAtLoginKit`, `PermissionKit` | GUI 타깃 |
| `WikiLedgerKit`, `GraphEngineKit`, `GraphRAGKit` | grapher |
| `SessionKit`(`SupportedAIAgentCLI`) | 에이전트 런타임 CLI 이름 |

그 밖의 킷(가계부·세금·게임·VPN·스토어 운영 등)은 이 저장소의 어떤 패키지도 쓰지 않는다. 이 저장소에서 그 킷을 고치거나 새 킷을 추가하지 않는다.

## 경계

- 원장 도메인 로직(객체·world·게이트)을 이 패키지에 넣지 않는다. 그것은 `agent-wiki-kit` 담당이다.
- 이 사본의 수정은 다른 저장소의 swiftkit에 전달되지 않는다. 킷 동작을 바꿀 때는 이 저장소 안의 사용처만 기준으로 판단하고, 원본과 갈라진다는 사실을 커밋 메시지에 적는다.
- `Derived/`는 Tuist 생성물(`TuistBundle+*`, `InfoPlists`)이다. 손으로 고치지 않는다.

## 불변식

- `StateRootKit.resolveHost`: `SWIFT_APP_STATE_ROOT`가 있으면 그 경로, 테스트 실행 중이면 임시 디렉터리, 아니면 홈. 원장 설정 파일 위치가 이 함수에 달려 있으므로 우선순위를 바꾸지 않는다.
- `EndpointRouterKit` 기본값 파일의 호스트는 커밋 메시지에 이전 이유를 적고 바꾼다(최근 예: 2026-09-27 스토어 호스트 단수형 이전).

## 테스트

- 테스트 디렉터리가 191개라 2026-09-30 확인에서는 실행하지 않았다. 앱 빌드 과정에서 위 표의 킷이 컴파일되는 것만 확인했다.
- 킷을 바꾸면 그 킷의 테스트 타깃만 `--filter`로 돌리고, 이 저장소의 앱 다섯 개와 `agent-wiki-kit`을 다시 빌드한다.
