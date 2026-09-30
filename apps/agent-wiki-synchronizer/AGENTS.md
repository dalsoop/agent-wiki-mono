# agent-wiki-synchronizer

## 범위

- 전역 CLI 타깃 `AgentWikiSynchronizerCLI`(제품 `agent-wiki-synchronizer`, 런타임 슬러그 `agent-wiki-global`). 설치되면 `AgentWikiGlobal.app/Contents/Helpers/agent-wiki-synchronizer`가 되고 `/opt/homebrew/bin/agent-wiki`, `agent-wiki-global`, `agent-wiki-synchronizer`가 모두 이 파일을 가리킨다.
- 명령 분기(`main.swift`), 허용 옵션 목록, 전역 CLI 전용 명령: `fleet`, `gujo`(sync·peer·blob), `promotion`, `schedule`(LaunchAgent 등록), `task`/`orchestration`, `world`, 테넌트 world 바인딩(`TenantWikiBinding`).
- 메뉴바 앱 `AgentWikiSynchronizer`과 `AgentWikiSynchronizerCore`(상태 조회, StateMirror 게시, world 표시 이름).

범위 밖: 발행·조회·verify 등 공용 명령의 동작(`agent-wiki-kit`의 `WikiCLIShared`), 원장 모델과 게이트(`KnowledgeBaseWikiCore`). 그 로직을 이 패키지에 복사하지 않는다. repo `.wiki` 원장 처리는 `apps/agent-wiki-indexer` 담당이다.

## 불변식

- `--world`가 없으면 `gujo-wiki`를 연다. cwd `.wiki` 탐지를 넣지 않는다.
- `publish` 전에 `WorldEnvLock.denial`을 확인한다.
- `GujoManaged.exitIfNotEntitledSync()`와 `SingleInstanceCLI.autoGuard()`는 `main.swift`의 첫 호출로 유지한다.
- 이 CLI 타깃과 Core는 AppKit·SwiftUI를 import하지 않는다. PATH CLI가 AppKit을 링크하면 dual-entry 실행이 멈춘다(2026-07-25 실측).
- 허용 옵션 목록에 옵션을 추가하면 `apps/agent-wiki-indexer`의 목록에도 같은 옵션을 넣는다.
- 도메인 조작은 이 CLI로 한다. StateMirror(`~/.swift-app-state/agent-wiki-global.json`)나 `~/.memo-citation-ledger/*.json`을 손으로 고치거나 메뉴바 GUI로 우회하지 않는다. 상태 루트는 `AppPaths.stateDirectory()`(StateRootKit)다.

## 구현 패턴

- world가 필요 없는 명령은 `LedgerConfig.load()` 이전에 처리하고 `exit(0)`한다. world가 필요한 명령은 아래 `switch`에 넣는다.
- 하위 프로세스는 `SafeProcessRunner`로 부른다. `CommandSchedule.swift`의 `launchctl` 함수가 옛 `Process` 변수 `p`를 참조해 현재 패키지가 빌드되지 않는다. 이 함수를 고칠 때는 `safeResult`의 종료 코드를 돌려주도록 끝까지 다시 쓴다.

## 운영 표면

- 이 앱 CLI를 처음 다룰 때는 `agent-wiki capabilities`로 계약(명령 목록·상태 파일·health·depends)을 먼저 확인하고, 그다음 `--help`를 본다.
- GUI가 시작될 때 `HealthPulse.publish(app: "agent-wiki-global")`가 `~/.swift-app-state/pulse/agent-wiki-global.pulse`(StateRootKit 상태 루트 기준)를 쓴다. 이 파일과 StateMirror `~/.swift-app-state/agent-wiki-global.json`은 관측용 출력이므로 손으로 고치지 않는다.

## 테스트

- 2026-09-30 기준 `agent-wiki-synchronizer` 제품 빌드는 위 `launchctl` 오류로 실패한다. 테스트는 빌드가 되어야 돌릴 수 있다.
- Core 테스트: 스모크, 테넌트 world 층 판정, world 표시 이름. world 해석이나 옵션 목록을 바꾸면 "명령 뒤 `--world`는 무시되고 `gujo-wiki`가 열림", "등록되지 않은 world는 실패", "`AGENT_WIKI_WORLD`와 다른 world 발행 거부"를 확인한다.
- 설치는 `app-build-manager`로 하고, 설치 뒤 `agent-wiki version`, `agent-wiki capabilities`, `agent-wiki --world gujo-wiki status --json`으로 확인한다.
