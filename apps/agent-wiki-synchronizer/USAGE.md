# AgentWikiGlobal 사용법

메뉴바 아이콘 → 상태 확인 / 새로고침 / 설정.
설정창에서 언어(System/한국어/English)를 즉시 전환할 수 있다.

CLI 바이너리 이름: `agent-wiki-global` (executable product `AgentWikiGlobal`).

의존성: `agent-wiki-global capabilities` → `.result.depends` (목록은 여기 두지 않는다.
정본: `docs/app-interop-contract.md`).

## agent-law R2 키 출처

- 키체인 서비스 `agent-law-r2` 에 키가 있으면 그것을 쓴다(기본).
- Bitwarden 항목을 출처로: `agent-wiki world storage --credential-source bitwarden:<item id>` (지우기 `--credential-source none`).
  키체인이 비어 있으면 `archive`·`redact`·`sync`·`dream run` 이 `vaultwarden-client item field exec` 로 자신을 다시 실행해
  값을 하위 프로세스 환경으로만 받는다. 셸 환경 변수로 직접 넣은 키는 받지 않는다. 자세한 절차: `docs/operations.md` agent-law 절.
