# 현황

기준 커밋 `f8089cc`(origin/main), 확인일 2026-09-30. 모든 명령은 이 Mac(Darwin 25.5, Apple Silicon)에서 빌드 대기열을 거쳐 실행했다.

## 패키지별 상태

| 패키지 | 구현 | 빌드 | 테스트 | 근거 |
|---|---|---|---|---|
| `citationledgerkit` | 해시·시각·UUIDv7·작성자 해석 | 통과 | 통과(5개 스위트, 10개 테스트) | `swift test --package-path citationledgerkit` 종료 코드 0 |
| `agent-wiki-kit` | 원장 엔진, 공용 CLI 명령, BlobStore | 통과 | 통과(70개 스위트, 248개 테스트) | 2026-10-01 전체 테스트 종료 코드 0 |
| `apps/agent-wiki-synchronizer` | 전역 CLI, 메뉴바 앱 | 통과 | 실행 안 함 | 2026-10-01 `swift build --product agent-wiki-synchronizer` 종료 코드 0. 설치본(1.0.29)의 원천(결정 0006) |
| `apps/agent-wiki-indexer` | repo `.wiki` CLI, 메뉴바 앱 | 통과 | 통과(XCTest 3개, swift-testing 0개) | `swift build`, `swift test` 모두 종료 코드 0 |
| `apps/agent-wiki-grapher` | 그래프 질의 CLI, 창 앱 | 통과 | 실행 안 함 | 2026-10-01 `swift build` 종료 코드 0(결정 0006 으로 설치본 원천 사본을 가져온 뒤) |
| `apps/agent-wiki-editor` | Studio GUI | 통과 | 실행 안 함 | 2026-10-01 `swift build` 종료 코드 0. `agent-wiki-ui` 가 커밋되어 새 클론에서도 해석된다 |
| `apps/agent-wiki-reader` | 읽기 전용 프록시 CLI, 메뉴바 앱 | 통과 | 실행 안 함 | 2026-10-01 `swift build` 종료 코드 0 |
| `swiftkit` | 공용 킷 사본 | 앱 빌드 과정에서 쓰는 킷은 컴파일됨 | 실행 안 함 | 테스트 디렉터리가 191개라 이번 확인에서 제외 |
| `swiftkit-appscaffold`, `swiftkit-sparkle` | 앱 수명주기, 자동 업데이트 | indexer 빌드 과정에서 컴파일됨 | 실행 안 함 | 별도 명령 없음 |

## 설치본

- 이 Mac에 설치된 `agent-wiki`는 `AgentWikiGlobal.app`(2026-09-24 설치)의 `agent-wiki-synchronizer`이고, `agent-wiki version`은 `2026.07-repository-agent-adapter-v1`을 출력한다(저장소의 `LedgerVersion.current`와 같다).
- 저장소 HEAD의 synchronizer는 빌드되지 않으므로 설치본은 이 저장소 커밋에서 만든 것이 아니다.
- 설치본에서 `agent-wiki publish --of <id>`를 실행하면 "unknown option(s): --of"로 종료 코드 64다(2026-09-30 확인, 쓰기 없음).

## 남은 일 (우선순위 순)

1. 고정 호스트 이름을 기대하는 wiki-hub 테스트(지금 `withKnownIssue`)를 현재 엔드포인트 해석 방식(환경 변수 → EndpointRouterKit)에 맞춘다.
2. `--of`·`--display`를 전역·repo CLI 허용 옵션에 넣어 scene-evidence 발행과 world 표시 이름 등록을 가능하게 한다.
3. 상위 world 인용 발행 경로(`runScopedPublish`)가 분류·batch 인자를 처리하게 한다.
4. 원격 연결·백업 기본값을 정리한다(보안 이슈 있음, 비공개 추적).
