# agent-wiki-indexer

## 범위

- repo 원장 CLI 타깃 `AgentWikiLocalCLI`(제품 `agent-wiki-indexer`, 런타임 슬러그 `agent-wiki-local`). `--world`가 없으면 cwd에서 위로 올라가며 첫 `.wiki/` 디렉터리를 원장으로 연다. `.wiki`가 없으면 안내 메시지와 함께 실패한다.
- repo 전용 명령: `task`(작업 그래프), `repository`/`repository-summary`, `promotion`/`promote`, `world`(list·add·set-layer). 나머지 명령은 `WikiCLIShared` 함수를 부른다.
- 메뉴바 앱 `AgentWikiLocal`과 `AgentWikiLocalCore`(StateMirror `~/.swift-app-state/agent-wiki-local.json`, 상태 루트 `AppPaths.stateDirectory()`).

범위 밖: 이름과 달리 색인 엔진이 아니다. SQLite FTS 색인(`LedgerIndex`)은 `agent-wiki-kit`에 있고, 이 앱은 그것을 부를 뿐이다. `gujo-wiki` 같은 전역 world 운영(`gujo`, `fleet`, `schedule`)은 `apps/agent-wiki-synchronizer` 담당이다.

## 불변식

- `--world`를 주면 등록된 world만 연다. 없는 이름이면 "없는 세계관"으로 실패한다.
- `--world`가 없을 때 테넌트 world나 `currentWorld`로 폴백하지 않는다. cwd `.wiki`만 본다.
- 허용 옵션 목록은 전역 CLI(`apps/agent-wiki-synchronizer`)와 같게 유지한다.
- `promotion`의 `--path`는 `repository`, `repository-summary`, `promotion`, `promote` 명령에서만 cwd를 대신한다.
- 도메인 조작은 이 CLI로 한다. 상태 파일을 손으로 고치지 않는다.

## 테스트

- 2026-09-30 기준 패키지 빌드와 테스트(XCTest 3개)가 통과한다. 이 저장소에서 빌드되는 유일한 앱이라, CLI 동작을 격리 world에서 시험할 때 이 제품을 쓴다(`SWIFT_APP_STATE_ROOT`를 임시 디렉터리로 두고 `init`).
- 테넌트 world 층 판정 테스트가 있다. world 해석을 바꾸면 "하위 디렉터리에서 실행해도 상위 `.wiki`를 찾음", "`.wiki`와 등록된 world 경로가 같으면 등록 이름을 씀", "`.wiki`가 없으면 실패"를 검사한다.
