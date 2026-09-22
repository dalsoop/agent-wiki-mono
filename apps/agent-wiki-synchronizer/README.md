# AgentWikiGlobal-swift

로컬 명령 메뉴바 앱. 공유 `swiftkit`(CommandKit / PrivilegedKit / LocalizationKit) 위에 빌드된다.

이 앱은 태어날 때부터 4면 계약(GUI + Core + CLI + StateMirror)을 갖춘다 —
`interop.json`, `StateMirrorKit` 게시 지점, CLI `capabilities`. 남은 절차(도메인 로직,
아이콘, ship, MR)는 `agent-cli-scaffold checklist --app agent-wiki-global` 이 순서대로 알려준다.

## 빌드 / 테스트

    swift build
    swift test

## 구조

- `Sources/AgentWikiGlobal/` — SwiftUI 메뉴바 셸(MenuBarExtra) + 설정창 + i18n.
- `Sources/AgentWikiGlobalCore/` — 도메인 로직(시스템 명령 호출/파싱). `CommandRunning` 주입으로 테스트 가능.

도메인 구현은 `AgentWikiGlobalService` 의 `status()` 를 실제 명령으로 교체하는 것에서 시작한다.
