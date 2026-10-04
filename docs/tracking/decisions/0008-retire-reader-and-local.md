# 0008. Reader 와 Local 앱을 퇴역한다(배포 컷오프)

## 맥락

2026-10-04 agent-law 전환(결정 0007) 뒤 위키 관련 앱을 점검했다. 다른 앱·스킬·훅에서 `agent-wiki-reader`, `agent-wiki-local` CLI 를 부르는 곳은 0곳이었다(스킬 카탈로그, swift-app-mono 앱 소스, Claude 훅 설정 조사). 에이전트가 실제로 쓰는 것은 `agent-wiki` 하나다.

- `agent-wiki-reader`(AgentWikiReader): 읽기 전용 화면과 읽기 전용 프록시 CLI. AgentWikiStudio 와 같은 화면 모듈(`agent-wiki-ui`)을 쓰는 중복이다.
- `agent-wiki-indexer`(AgentWikiLocal, CLI `agent-wiki-local`): 저장소 `.wiki/`(ledger 2) 전용 CLI. 남은 저장소 위키는 swift-app-mono 하나뿐이고, 전역 CLI 가 `--world` 로 같은 원장을 다룬다.

사용자 결정(2026-10-04): "6개 모두 퇴역". 나머지 넷(AgentWikiGraphStudio, AgentWikiGraphReaper, LLMWiki Editor, Package Wiki Bridge)은 swift-app-mono MR !478 에서 같은 방식으로 컷오프했다.

## 결정

- 두 앱을 배포 컷오프한다. 앱 폴더의 `CUTOFF`, `Packaging/package-identity.json` 의 `ship_cutoff: true`·`desired: absent` 로 설치 도구가 재설치를 거부한다. `DEPRECATION.md` 가 대체를 안내한다.
- 소스는 지우지 않는다. 설치본은 지우지 않고 `~/Library/Application Support/agent-wiki-cutoff/` 로 옮긴다.
- 사람용 화면은 AgentWikiStudio 하나, 그래프는 AgentWikiGraph 하나, 에이전트용 CLI 는 `agent-wiki` 하나로 둔다.

## 대안

- **Reader 를 유지하고 Studio 를 퇴역:** Studio 가 편집과 열람을 함께 하므로 열람 전용을 남길 이유가 없다.
- **소스까지 삭제:** 선례(2026-08-06 knowledge-base-viewer 컷오프)처럼 역사와 번들 id 를 남기고 배포만 멈춘다.

## 결과

- 이 저장소의 활성 앱은 synchronizer(전역 CLI), editor(Studio), grapher 셋이다. 문서의 Reader·Local 서술은 "퇴역" 으로 표시한다.
