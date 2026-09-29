# agent-wiki-reader

## 범위

- 보고용 CLI `agent-wiki-reader`: 자체 명령 `help`, `version`, `status`, `capabilities`, `open`만 직접 처리하고, 나머지 인자는 허용 목록 판정 후 설치된 `agent-wiki`(`HostPlatform.cliBinPath("agent-wiki")`)에 하위 프로세스로 넘긴다.
- 메뉴바 앱 `AgentWikiReader`(world 목록, 원격 공유 상태, CLI 패널). 원장 화면은 `agent-wiki-ui`의 `KnowledgeBaseWikiUI`를 쓴다.
- StateMirror `~/.swift-app-state/agent-wiki-reader.json`, 설정·작업 sqlite(`DurableAppLayout` 슬러그 `agent-wiki-reader`).

범위 밖: 원장 쓰기, 승격, 작업 그래프, fleet 등록, 동기화 실행. 원장 로직을 이 앱 안에 구현하지 않는다(모든 조회는 설치된 `agent-wiki`를 통한다).

## 불변식

- `AgentWikiReaderService.isReadOnlyInvocation`이 거부한 인자는 하위 프로세스를 띄우지 않고 종료 코드 64와 안내 한 줄로 끝낸다.
- 거부 목록(`blockedCommands`)이 허용 목록보다 먼저 판정된다. 새 `agent-wiki` 명령이 생기면 기본은 거부이고, 읽기 전용임을 확인한 뒤에만 허용 목록에 넣는다.
- 중첩 명령은 하위 명령 단위로 판정한다: `graph`는 `status|timeline|neighbors|interpretations`, `blob`은 `get|info|refs|path|verify|list|open`, `event`는 `tree|tail|count`, `gujo`는 `status`와 `peer list`, `world`는 `list|use`. `fleet`에도 `list|doctor|scan` 판정 코드가 있지만 `fleet`이 거부 목록에 있어 먼저 거부되므로 도달하지 않는다.
- 앞쪽 전역 플래그는 `--world`·`--as`(값 필요), `--json`·`--all`·`--fleet`만 건너뛴다. `--world`나 `--as` 뒤에 값이 없으면 거부한다.
- `world use`는 현재 허용되지만 호스트 설정의 `currentWorld`를 바꾸는 쓰기다. 이 허용을 넓히지 않는다.

## 운영 표면

- 이 앱 CLI를 처음 다룰 때는 `agent-wiki-reader capabilities`로 계약(명령 목록·상태 파일·health·depends)을 먼저 확인하고, 그다음 `--help`를 본다.
- GUI가 시작될 때 `HealthPulse.publish(app: "agent-wiki-reader")`가 `~/.swift-app-state/pulse/agent-wiki-reader.pulse`(StateRootKit 상태 루트 기준)를 쓴다. 이 파일과 StateMirror `~/.swift-app-state/agent-wiki-reader.json`은 관측용 출력이므로 손으로 고치지 않는다.

## 테스트

- 2026-09-30 기준 `agent-wiki-ui`가 저장소에 없어서 새 클론·worktree에서는 빌드되지 않는다. 이 Mac의 메인 체크아웃에서만 빌드할 수 있다.
- Core 스모크 테스트가 있다. 허용 목록을 바꾸면 `publish`·`capture`·`promotion`·`graph rebuild`·`blob put`·`event append`·`fleet register` 거부와 `show`·`search`·`--world x list` 허용을 함께 검사한다.
