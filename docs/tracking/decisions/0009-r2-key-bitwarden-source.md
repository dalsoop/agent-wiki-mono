# 0009. agent-law R2 키를 Bitwarden 항목에서 하위 프로세스 환경으로 받는다

상태: 확정(사용자 결정, 2026-10-06)

## 맥락

결정 0007 은 R2 키를 이 기기 키체인(서비스 `agent-law-r2`)에서만 읽게 했다. 2026-10 부터 키는 `dns-zone-manager token create --r2-bucket` 이 만들어 Bitwarden 항목(`Cloudflare R2 · agent-law`, Machine 폴더, 필드 `access-key-id`·`secret-access-key`)에 저장한다. 키를 바꿀 때마다 그 값을 사람이 키체인에 다시 넣는 단계가 남았다.

사용자 원문: "fix auto complete" → "1 2 both"(1 = 키 단계 자동화).

같은 문제를 푸는 함대 관례: swift-app-mono `dns-zone-manager` 의 `credential source set bitwarden:<item id>#<selector>` 는 값이 필요할 때 `vaultwarden-client item field exec … --env <변수> -- <자기 자신>` 으로 자신을 다시 실행해, 값이 파일·화면에 남지 않고 하위 프로세스 환경에만 들어가게 한다. 1Password `op run`, Doppler `doppler run` 도 비밀을 하위 프로세스 환경으로만 넘기는 같은 모양이다.

## 결정

- 호스트 설정 `lawStorage.credentialSource` 에 키 출처를 둔다: `agent-wiki world storage --credential-source bitwarden:<item id>`, 지우기 `--credential-source none`. 기본은 키체인이다. 항목 id 는 비밀이 아니다.
- 키체인 `agent-law-r2` 에 두 값이 있으면 그것을 쓴다. 없고 출처가 Bitwarden 이면, R2 키가 꼭 필요한 명령(`archive`(`--dry-run` 제외)·`redact`·`sync`·드리밍 기기의 `dream run`)이 시작할 때 `vaultwarden-client`(PATH 해석) 의 `item field exec` 를 두 겹으로 감싸 자신을 다시 실행한다. 자식은 재실행 표지(`AGENT_WIKI_R2_FROM_BITWARDEN=1`)가 있을 때만 `AGENT_LAW_R2_ACCESS_KEY_ID`·`AGENT_LAW_R2_SECRET_ACCESS_KEY` 를 받고, 받은 즉시 세 변수를 자기 환경에서 지운다.
- 표지 없이 사람이 넣은 환경 변수는 받지 않는다(0007 의 "사람이 env 로 키를 넣는 경로는 열지 않는다" 유지). 표지가 있는 자식은 다시 실행하지 않는다(무한 재실행 방지).
- `summon`·`enact` 의 R2 읽기·올리기처럼 R2 가 선택 단계인 경로는 다시 실행하지 않는다. 키체인에 없으면 지금처럼 그 단계를 건너뛴다.

## 대안

- **키체인에 자동으로 다시 써 넣기:** 값이 디스크(키체인)에 사본으로 남고, 쓰는 주체가 둘(토큰 발급 도구·위키)이 된다.
- **위키가 Bitwarden 을 직접 읽기:** 금고 잠금 해제·세션 관리가 위키로 들어온다. 소유 앱(`vaultwarden-client`)의 표준 이전 경로를 쓴다.
- **환경 변수를 그대로 받기:** 사람이 셸에 키를 두는 경로가 열린다.

## 결과

- `docs/security.md` "R2 와 세션" 의 키 보관 조문, `AGENTS.md`·`docs/standards.md` 의 "R2 키는 키체인에서만 읽는다" 를 이 결정으로 개정한다.
- 출처가 Bitwarden 이고 키체인이 비어 있으면, 예약 실행(`sync` 10분·적재 하루·드리밍 하루)도 매번 금고를 연다. 금고가 잠겨 있으면 `vaultwarden-client` 가 실패하고 그 틱은 실패로 끝난다.
