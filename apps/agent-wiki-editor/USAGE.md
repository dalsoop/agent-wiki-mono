# AgentWikiStudio 사용법

메뉴바 아이콘 → 상태 확인 / 새로고침 / 설정.
설정창에서 언어(System/한국어/English)를 즉시 전환할 수 있다.

메인 창 사이드바: 내 기록 · 수집 · 최근 · world · 발행(간단 폼/CLI 안내).
monlith 폴백: 헤더 「GUI (studio)」「GUI (전체)」.

CLI 바이너리 이름: `agent-wiki-studio`.

**dual-entry:** PATH CLI `agent-wiki` 는 `agent-wiki-synchronizer` 가 `cli_aliases` 로 소유한다. 이 앱은 그 이름을 claim 하지 않고, 조회·발행은 PATH 의 `agent-wiki` 를 프록시한다.
설치: `app-build-manager ship apps/agent-wiki-studio-swift release`.

의존성: `agent-wiki-studio capabilities` → `.result.depends` (목록은 여기 두지 않는다.
정본: `docs/app-interop-contract.md`).
