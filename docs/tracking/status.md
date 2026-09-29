# 현황

기준 커밋 `f8089cc`(origin/main), 확인일 2026-09-30. 모든 명령은 이 Mac(Darwin 25.5, Apple Silicon)에서 빌드 대기열을 거쳐 실행했다.

## 패키지별 상태

| 패키지 | 구현 | 빌드 | 테스트 | 근거 |
|---|---|---|---|---|
| `citationledgerkit` | 해시·시각·UUIDv7·작성자 해석 | 통과 | 통과(5개 스위트, 10개 테스트) | `swift test --package-path citationledgerkit` 종료 코드 0 |
| `agent-wiki-kit` | 원장 엔진, 공용 CLI 명령, BlobStore | 통과 | 실패: 테스트 타깃 컴파일 오류 | `swift build` 종료 코드 0. `swift test`는 `GujoBlobSyncTests.swift:109`에서 `GujoHubClient.defaultBaseURL`(옵셔널)의 `.absoluteString` 접근이 컴파일되지 않아 종료 코드 1. 테스트는 한 개도 실행되지 않았다 |
| `apps/agent-wiki-synchronizer` | 전역 CLI, 메뉴바 앱 | 실패 | 실행 안 함 | `swift build --product agent-wiki-synchronizer` 종료 코드 1. `CommandSchedule.swift:165-172`에서 정의되지 않은 `p` 참조 |
| `apps/agent-wiki-indexer` | repo `.wiki` CLI, 메뉴바 앱 | 통과 | 통과(XCTest 3개, swift-testing 0개) | `swift build`, `swift test` 모두 종료 코드 0 |
| `apps/agent-wiki-grapher` | 그래프 질의 CLI, 창 앱 | 실패 | 실행 안 함 | `AgentWikiGraphCLI/main.swift` 293-298행에서 `SafeProcessRunner.run` 호출 뒤에 옛 `do`/`catch`의 본문 조각이 남아 구문이 깨진다. 같은 빌드에서 339행 동시성 오류와 351행 없는 멤버 `usage` 오류도 난다 |
| `apps/agent-wiki-editor` | Studio GUI, 분기된 full CLI | 실패 | 실행 안 함 | 의존 패키지 `agent-wiki-ui`가 저장소에 없어 의존성 해석 단계에서 종료 코드 1 |
| `apps/agent-wiki-reader` | 읽기 전용 프록시 CLI, 메뉴바 앱 | 실패 | 실행 안 함 | 위와 같은 원인 |
| `swiftkit` | 공용 킷 사본 | 앱 빌드 과정에서 쓰는 킷은 컴파일됨 | 실행 안 함 | 테스트 디렉터리가 191개라 이번 확인에서 제외 |
| `swiftkit-appscaffold`, `swiftkit-sparkle` | 앱 수명주기, 자동 업데이트 | indexer 빌드 과정에서 컴파일됨 | 실행 안 함 | 별도 명령 없음 |

## 설치본

- 이 Mac에 설치된 `agent-wiki`는 `AgentWikiGlobal.app`(2026-09-24 설치)의 `agent-wiki-synchronizer`이고, `agent-wiki version`은 `2026.07-repository-agent-adapter-v1`을 출력한다(저장소의 `LedgerVersion.current`와 같다).
- 저장소 HEAD의 synchronizer는 빌드되지 않으므로 설치본은 이 저장소 커밋에서 만든 것이 아니다.
- 설치본에서 `agent-wiki publish --of <id>`를 실행하면 "unknown option(s): --of"로 종료 코드 64다(2026-09-30 확인, 쓰기 없음).

## 남은 일 (우선순위 순)

1. synchronizer의 `CommandSchedule.swift` `launchctl` 함수를 `SafeProcessRunner` 결과를 쓰도록 고쳐 전역 CLI를 다시 빌드 가능하게 만든다. 설치본을 이 저장소에서 다시 만들 수 있어야 한다.
2. `agent-wiki-kit` 테스트 타깃의 컴파일 오류를 고치고, 고정 호스트 이름을 기대하는 wiki-hub 테스트를 현재 엔드포인트 해석 방식(환경 변수 → EndpointRouterKit)에 맞춘다.
3. `agent-wiki-ui`를 저장소에 넣거나 editor·reader의 의존을 정리해 새 클론에서 빌드되게 한다.
4. grapher CLI `main.swift`의 깨진 구간을 복구한다.
5. `--of`·`--display`를 전역·repo CLI 허용 옵션에 넣어 scene-evidence 발행과 world 표시 이름 등록을 가능하게 한다.
6. 상위 world 인용 발행 경로(`runScopedPublish`)가 분류·batch 인자를 처리하게 한다.
7. editor의 분기된 `AgentWikiFullCLI` 사본을 `WikiCLIShared`로 합치거나 제거한다.
8. 퇴역 호스트를 가리키는 기본값(git 원격 1순위 `gitlab-ssh.internal.kr`, restic 기본 저장소 `pve`)을 정리하고, 소스에 남은 `*.50.internal.kr` 기본 주소의 현재 유효 여부를 확인한다.
