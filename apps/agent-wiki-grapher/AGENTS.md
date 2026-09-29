# agent-wiki-grapher

## 범위

- 창 앱 `AgentWikiGraph`(메뉴바 없음)과 CLI `agent-wiki-grapher`(런타임 슬러그 `agent-wiki-graph`).
- `AgentWikiGraphCore`: 원장 디렉터리를 읽어 인용·개정 그래프를 만들고, `orphans`, `centrality`, `impact`, `path`, `context`(질의 토큰 시드 → 이웃 확장 → in-degree 순위) 질의를 낸다. 그래프 수학은 swiftkit `GraphEngineKit`, 원장 파싱은 `WikiLedgerKit`, 관계 인식 검색은 `GraphRAGKit`이 한다.
- 파생 캐시 `~/.swift-app-state/agent-wiki-graph/index.json`(스키마 버전과 원장 mtime 지문이 바뀌면 재빌드), StateMirror `~/.swift-app-state/agent-wiki-graph.json`.

범위 밖: 원장 쓰기. 이 앱은 `agent-wiki-kit`을 의존하지 않고 swiftkit의 `WikiLedgerKit`으로 원장을 따로 파싱한다. 원장 형식이 바뀌면 이 앱도 따로 맞춰야 한다.

## 불변식

- 원장 파일을 절대 쓰지 않는다. 캐시와 StateMirror만 쓴다.
- 캐시는 스키마 버전이 다르거나 원장 지문이 바뀌면 stale로 판정하고 현재 값으로 쓰지 않는다. 캐시 교체는 원자적으로 한다.
- CLI는 명령별 허용 옵션(`--json`, `--limit N`, `--kinds cite,supersedes`) 밖의 옵션을 작업 전에 종료 코드 64로 거부한다.
- CLI 타깃은 Foundation만 쓴다. CLI에 추가한 연산은 GUI에도 노출한다.

## 테스트

- 2026-09-30 기준 CLI `main.swift` 293-298행(SafeProcessRunner 전환 뒤 남은 `catch` 조각), 339행, 351행 오류로 패키지가 빌드되지 않는다.
- Core 스모크 테스트가 있다. 그래프 로직을 바꾸면 임시 원장으로 "인용 없는 객체가 orphans에 나옴", "supersedes 간선이 `--kinds supersedes`에서만 잡힘", "원장 파일 추가 뒤 캐시가 stale로 바뀜"을 검사한다.
