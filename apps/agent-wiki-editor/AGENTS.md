# agent-wiki-editor

## 범위

- Studio GUI `AgentWikiStudio`(내 기록·수집·최근·world·간단 발행 창, 메뉴바). 원장 화면은 `agent-wiki-ui`의 `KnowledgeBaseWikiUI`를 쓴다.
- 얇은 CLI `agent-wiki-editor`(런타임 슬러그 `agent-wiki-studio`): `capabilities`, `dual-entry status|adopt`(설치된 CLI 인계) 등.
- `AgentWikiStudioCore`(StateMirror `~/.swift-app-state/agent-wiki-studio.json`, `DualEntryAdoption`).

범위 밖: 설치된 `agent-wiki`의 원천이 아니다(설치본은 `apps/agent-wiki-synchronizer` 제품). 분기 사본 `AgentWikiFullCLI` 는 1.0.28 에서 지웠다. 원장 모델과 게이트는 `agent-wiki-kit` 담당이다.

## 불변식

- 공용 명령은 이 패키지에 복사하지 않는다(`WikiCLIShared`·synchronizer 가 자리다).
- `Package.swift.bak-kit-20260806141945`는 옛 매니페스트 백업이다. 빌드 구성으로 읽지 않는다.
- 도메인 조작은 CLI로 한다. 상태 파일을 손으로 고치거나 GUI로 우회하지 않는다.

## 운영 표면

- 이 앱 CLI를 처음 다룰 때는 `agent-wiki-editor capabilities`로 계약(명령 목록·상태 파일·health·depends)을 먼저 확인하고, 그다음 `--help`를 본다.
- GUI가 시작될 때 `HealthPulse.publish(app: "agent-wiki-studio")`가 `~/.swift-app-state/pulse/agent-wiki-studio.pulse`(StateRootKit 상태 루트 기준)를 쓴다. 이 파일과 StateMirror `~/.swift-app-state/agent-wiki-studio.json`은 관측용 출력이므로 손으로 고치지 않는다.

## 테스트

- 2026-09-30 기준 `agent-wiki-ui`가 저장소에 없어서 새 클론·worktree에서는 의존성 해석부터 실패한다.
- Core 테스트: 스모크, `DualEntryAdoption`(설치된 CLI 인계 판정). 기존 테스트는 GUI 실행 파일 경로(`Contents/MacOS`)와 없는 경로를 안전한 CLI 원본으로 인정하지 않는지, dry-run이 합성 경로에서 동작하는지 검사한다. 인계 로직을 바꾸면 이 세 가지를 유지한다.
