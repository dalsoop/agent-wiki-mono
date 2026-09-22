# AgentWikiGraph-swift

일반 창 앱(독 앱 — 메뉴바 없음). 공유 `swiftkit`(CommandKit / LocalizationKit) 위에 빌드된다.

이 앱은 태어날 때부터 4면 계약(GUI + Core + CLI + StateMirror)을 갖춘다 —
`interop.json`, `StateMirrorKit` 게시 지점(앱 시작 시 1회 게시 포함), CLI `capabilities`,
사용법 온보딩(한 번만 표시 — 질문형 입력 위저드 금지). 남은 절차(도메인 로직,
아이콘, ship, MR)는 `agent-cli-scaffold checklist --app agent-wiki-graph` 이 순서대로 알려준다.

## 빌드 / 테스트

    swift build
    swift test

## 구조

- `Sources/AgentWikiGraph/` — SwiftUI 주 창(`MainView`) + 사용법 온보딩 + 설정(⌘,) + i18n.
- `Sources/AgentWikiGraphCore/` — 도메인 로직(시스템 명령 호출/파싱). `CommandRunning` 주입으로 테스트 가능.

도메인 구현은 `AgentWikiGraphService` 의 `status()` 를 실제 명령으로 교체하고 `MainView` 의
TODO 를 채우는 것에서 시작한다. **CLI 에 추가하는 모든 연산은 GUI 표면도 함께**(4면 계약).
