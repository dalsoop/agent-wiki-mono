# 외부 계약

소비자는 에이전트 세션, 훅, 다른 macOS 앱(agent-app-registry, agent-wiki-reader 등)이다. 모두 PATH의 CLI를 하위 프로세스로 부르고, 표준 출력·표준 에러·종료 코드를 읽는다. 네트워크 API는 제공하지 않는다.

## 공통 규칙

- 호출 형식: `agent-wiki [--as <actor>] [--world <이름>] <명령> [인자…]`. `--as`와 `--world`는 **명령 앞**에 있어야 효력이 있다. 명령 뒤의 `--world`는 `pull`·`weight` 외에는 무시된다.
- world 기본값: 전역 CLI(`agent-wiki`, `agent-wiki-global`, `agent-wiki-synchronizer`)는 `gujo-wiki`, repo CLI(`agent-wiki-local`)는 cwd 위쪽의 첫 `.wiki/`다. 등록되지 않은 world 이름은 오류다.
- id 인자: 64자 전체 id, 유일한 id 접두어(보통 8자), 또는 `show` 계열에서는 제목·`alias:` 태그. 해석 순서는 id 접두·일치 → 제목 정확 일치 → alias 태그 → 제목 접두 → 제목 부분 일치다. 여러 개가 걸리면 실패한다.
- JSON: `--json`(일부 명령은 `-j`)을 주면 `{"ok": true, "result": …}` 봉투로 표준 출력에 낸다.
- 오류 메시지는 표준 에러로 한 줄 이상 나온다.

| 종료 코드 | 뜻 |
|---|---|
| 0 | 성공 |
| 1 | 명령 실패(없는 world, 없는 객체 참조, 본문 없음, 게이트 거부, 입출력 실패 등) |
| 2 | `verify`가 위반을 하나 이상 찾음 |
| 64 | 허용 옵션 목록에 없는 옵션, 또는 reader가 거부한 쓰기 명령 |

## 발행

`echo "<본문>" | agent-wiki --world <w> publish [옵션…]`

| 옵션 | 뜻 |
|---|---|
| `--title <t>` | 제목. `근거:`, `결정:`, `개념:` 같은 접두어가 있고 `--type`이 없으면 type이 접두어에서 정해진다 |
| `--type <t>` | 객체 type |
| `--cite <id> [rel]` | 인용. rel을 생략하면 `cites`. 여러 번 줄 수 있다 |
| `--supersedes <id>` / `--retracts <id>` | 개정 / 철회. 철회는 본문을 생략할 수 있다. `--supersedes` 를 반복하면 병합 개정이다(첫째가 주 부모, 나머지는 `supersedes-also:`, 결정 0005) |
| `--observes <event id>` | 사건 로그 참조. 여러 번 줄 수 있다 |
| `--tag <t>`, `--alias <a>` | 태그, `alias:<a>` 태그 |
| `--origin <url|path>` | 출처 |
| `--batch <id>` | 묶음 id(기본값은 `MEMO_LEDGER_BATCH`) |
| `--domain`, `--kind`, `--knowledge`, `--classification-reason` | 3축 분류. 넷을 함께 주면 선별 객체가 같이 발행된다 |
| `--allow-unclassified` | 분류 기준선 이후에도 분류 없이 발행 |
| `--kind scene-evidence --of <결정 id>` | 결정의 현장 근거 발행. 단 `--of`가 전역·repo CLI의 허용 옵션 목록에 없어서 현재는 종료 코드 64로 거부된다 |

- 성공: 표준 출력에 새 객체의 64자 id 한 줄. 선별 객체가 함께 발행되면 표준 에러에 `선별: <id>` 한 줄.
- 같은 내용·같은 시각으로 이미 발행된 객체가 있으면 그 id를 다시 출력한다.
- 오류: 본문 없음, 없는 객체 참조, 인용 게이트 거부(하위·형제·관계없는 world), 분류 인자 일부만 줌, 분류값이 허용 목록 밖, 기준선 이후 미분류, `AGENT_WIKI_WORLD` 잠금, 모르는 옵션. 모두 종료 코드 1이다(모르는 전역 옵션은 64).

## 조회

| 명령 | 입력 | 출력 |
|---|---|---|
| `show <id>` | id·제목·alias | 객체 파일 원문(프런트매터 + 본문) |
| `list [--all] [--json]` | 없음 | head 목록(`--all`이면 전체 역사). 텍스트는 `<id 8자>  <제목>  — <author>` |
| `status [--json]` | 없음 | world 이름, 객체 수, 최근 발행 |
| `search <질의> [--json] [--fleet]` | 검색어 | 현재 world와 조상 world의 검색 결과. `--fleet`/`--remote`면 여러 world 또는 wiki-hub |
| `context <질의>` | 질문 | 에이전트에 넣을 계층 컨텍스트 블록(텍스트) |
| `history <id>` | id | supersedes 사슬(최신 → 과거). 병합 개정을 만나면 `↳ 병합: <id> 갈래` 아래에 그 부모의 계보를 들여 쓴다 |
| `cited-by <id>` | id | 이 객체를 인용한 객체들 |
| `path <id1> <id2>` | 두 id | 인용 경로(BFS) |
| `root` | 없음 | world 루트 절대 경로 |
| `version` | 없음 | `LedgerVersion.current` 문자열 |
| `capabilities` | 없음 | InteropKit 계약 JSON(명령 목록·상태 파일·health·depends) |

조회 명령도 파생 색인(`state/index.db`)이 뒤처져 있으면 갱신한다. 원장 객체는 바꾸지 않는다.

## 검증

`agent-wiki --world <w> verify`

- 인자를 받지 않는다. 뒤에 id를 붙여도 world 전체를 검사한다.
- 위반이 없으면 표준 출력에 `이상 없음 (객체 N개, 체크포인트 검사 포함)`을 내고 종료 코드 0으로 끝난다.
- 위반이 있으면 한 줄에 하나씩 `<id 또는 파일명>: <문제>`를 내고 종료 코드 2로 끝난다.
- 체크포인트가 없으면 표준 에러에 안내 한 줄을 내고 나머지 검사는 계속한다.

## world 관리

| 명령 | 효과 |
|---|---|
| `world list [--json]` | 등록된 world와 층·parent·표시 이름 |
| `world add <name> <path> [--layer <층>] [--parent <world>]` | 설정에 world 추가. `--layer tenant`는 `--parent <remoteShared world>` 필수. 파서는 `--display <이름>`도 읽지만 허용 옵션 목록에 없어서 종료 코드 64로 거부된다 |
| `world use <name>` | `currentWorld` 변경(전역 CLI는 이 값을 쓰지 않고 `--world` 없으면 `gujo-wiki`) |
| `world set-layer <name> <층>` | 층 변경 |
| `init <path>` | `objects/`와 규약 파일·역할 정의를 만들고, 설정에 world를 등록하고 `currentWorld`로 지정 |

## 승격

- `promotion preview <id> --to <world> [--json]`: 쓰기 없이 결과를 미리 보여 준다.
- `promotion publish <id> --to <world> --confirm [토큰] [--json]`: 대상 world에 객체를, 원본 world에 영수증을 발행한다. `--confirm`이 없으면 발행하지 않는다. 토큰을 생략하면 preview가 계산한 확인 토큰을 쓴다.
- repo world에서는 `--path <repo 경로>`로 저장소 위치를 지정할 수 있다.
- 오류: parent 사슬 밖 대상, 알 수 없는 대상 world, 원본이 영수증, 원본이 저장된 바이트와 다름, repo 출처의 commit에 객체가 없음, 대상 world 쓰기 거부(보관된 전신·미등록 기기, 쓰기 게이트), 대상이 ledger 3 원장(ledger 3 승격은 `promote`). 대상 판정은 아무것도 쓰기 전에 한다.

## 읽기 전용 프록시 `agent-wiki-reader` (퇴역, 결정 0008 — 배포하지 않음. 아래는 소스의 동작 기록)

- 자체 명령: `help`, `version`, `status`(설치된 `agent-wiki world list` 결과), `capabilities`, `open`(GUI 실행).
- 그 밖의 인자는 앞쪽 `--world`·`--as`·`--json`·`--all`·`--fleet`를 건너뛴 첫 단어로 판정한다. 허용: `help`, `version`, `list`, `show`, `search`, `context`, `path`, `structure`, `history`, `cited-by`, `verify`, `world list|use`, `graph status|timeline|neighbors|interpretations`, `recent`, `root`, `discuss`, `diff`, `learn`, `rules`, `blob get|info|refs|path|verify|list|open`, `event tree|tail|count`, `gujo status`, `gujo peer list`. `fleet`은 거부 목록이 먼저 판정되어 `fleet list`도 거부된다(capabilities에는 "읽기 전용 fleet 프록시"로 적혀 있다). 허용되면 설치된 `agent-wiki`에 그대로 넘기고 그 출력과 종료 코드를 돌려준다.
- 거부되면 표준 에러에 `agent-wiki-reader: blocked write/ops command — use agent-wiki-studio or agent-wiki`를 내고 종료 코드 64로 끝난다.

## 그래프 질의 `agent-wiki-graph`

`status`, `rebuild`, `orphans`, `centrality`, `impact <id>`, `path <a> <b>`, `context <질의>`, `capabilities`, `open`. 모든 명령이 `--json`을 받고, `orphans`·`centrality`는 `--limit N`, `--kinds cite,supersedes`, `context`는 `--limit N`을 받는다. 그 밖의 옵션은 작업 전에 종료 코드 64로 거부한다. 원장에 쓰지 않고, 파생 캐시만 `~/.swift-app-state/agent-wiki-graph/index.json`에 쓴다.

## agent-law 명령 (ledger 3)

근거: 결정 0007. 모든 명령은 앞에 `--world`·`--as` 를 받고 `--json` 을 지원한다. 공포류는 표준 출력에 id 한 줄만 낸다. 전역 CLI 의 기본 원장은 `agent-law` 다.

| 명령 | 문법 |
|---|---|
| 공포 | `enact --title <t> [--type <유형>] [--tag <t>]… [--cite <id>[:<rel>]]… [--exhibit <sha>]… [--speaker <s>] [--batch <id>] [--runtime <r>] [--runtime-version <v>] [--model <m>] [--effort <e>] [--app <a>] [--app-version <v>]` (본문 표준 입력. 모델 기록 인자는 환경 변수·세션 등록보다 우선) |
| 개정 | `amend <id> [--also <id>]… --title <t> …` |
| 폐지 | `repeal <id> [--reason <r>]` |
| 연혁 | `history <id>` |
| 감사 | `audit` |
| 원상회복 | `restore <batch>` |
| 사실인정 | `finding <id> --subject <s> --certainty <c> --domain <d> --reason <r> [--from <t>] [--until <t>]` |
| 증거물 | `exhibit put <파일>` · `exhibit get <sha>` |
| 가림 | `redact <R2 키 또는 sha> --reason <r>` |
| 소환 | `summon [--session <id>] [--since <t>] [--until <t>] [--device <k>] [--runtime <r>] [--role user\|assistant\|tool] [--query <q>] [--record <발화 번호>]` |
| 적재 | `archive [--dry-run]` |
| 동기화 | `sync` (git 동기화 뒤 원장마다 가림 기록에 따른 로컬 삭제와 증거물 R2 동기화) |
| 드리밍 | `dream run [--scheduled]` · `dream status` · `dream resume` |
| 심급 | `court appeal <id> --reason <r>` · `court propose <id> --scope <s>` · `court hear` · `court decide <건 id> --approve\|--reject --testimony <증거 id>` · `court list [--level appellate\|supreme]` |
| 판결 | `judgment register --repo <r> --title <t> [--status provisional\|confirmed] [--testimony <증거 id>] [--path <p>]` · `judgment amend <번호> [--status provisional\|confirmed] [--testimony <증거 id>] [--path <p>] [--title <t>]` · `judgment repeal <번호> [--reason <r>]` · `judgment list [--repo <r>]` · `judgment show <번호>` |
| 목차 | `contents` |
| 보고 | `report models [--since <t>]` |
| 승격 | `promote <id> --to <원장>` |
| 원장 설정 | `world add <이름> --key <k> --root <경로> [--parent <이름>] [--predecessor <이름>]` · `world tenant-map <테넌트> <원장>` · `world device register <키>` · `world dream-device <키>` · `world storage [--endpoint <url>] [--bucket <b>] [--region <r>]` |
| 훅 | `hook session [--session <id>] [--runtime <r>] [--runtime-version <v>] [--model <m>] [--effort <e>]` (표준 입력에 실행 도구의 세션 시작 훅 JSON. 표준 출력 없음, 항상 종료 코드 0) |

- `show`·`list`·`search`·`context`·`path`·`cited-by`, 파생 색인 `index rebuild|sync|status` 는 이름과 뜻을 유지한다. ledger 3 의 `show` 는 현행 여부·4종류 보기·현행 사실인정을 텍스트 모드에서는 표준 에러에, `--json` 에서는 필드로 낸다. 검색 결과의 전신 객체는 `[전신 <원장>]`(JSON `predecessor: true`)로 표시한다.
- ledger 2 원장(`novel-world`, repo world)에 쓰는 일도 `enact`·`amend`·`repeal`·`restore`·`audit`·`checkpoint` 로 하며, ledger 2 의 `enact` 는 옛 분류 옵션(`--domain`·`--kind`·`--knowledge`·`--classification-reason`·`--allow-unclassified`·`--origin`·`--alias`·`--observes`)을 계속 받는다.
- ledger 3 승격의 대상 기록은 원본을 인용하지 않는다(상위 원장은 하위를 인용할 수 없다). 원본 id 는 영수증 본문에 적힌다.
- 증거(`evidence`) 기록의 ledger 3 승격은 원본 원장 범위에서 증언을 다시 확인하고, 실패하면 아무것도 쓰지 않고 종료 코드 1 로 거부한다. 증거물은 대상 원장 `exhibits/` 에 복사한다(대상 원장 키의 R2 사본은 다음 `sync`). 승격본은 화자를 그대로 가지며, 그 표지는 대상 원장의 승격 영수증(승격본을 `receipts` 로 인용)과 `promoted` 태그다. `testifies` 인용과 `audit` 은 표지만 믿지 않고 영수증 본문의 원본 원장(대상의 하위 원장)을 읽어 같은 영수증과 원본 증거 기록(화자·증거물·본문)을 찾을 때만 승격본으로 인정한다. 확인되지 않은 승격본 주장은 `speaker: user` 증언이 되지 못하고 감사 위반이다.
- 폐지된 이름(`publish`, `verify`, `rollback`, `classify`, `capture`, `blob` 의 쓰기 하위 명령, `hook authoring`)은 종료 코드 64 와 새 이름 안내만 내고 아무것도 하지 않는다. 전신 blob 은 받기만 하므로 `gujo blob push` 와 `gujo blob config --access-key/--secret-key` 도 64 다.
- `enact`·`amend`(와 화면 편집)는 처리 유형 `ruling`·`appeal`·`proposal`·`redaction`·`registration`·`contents`·`report`·`promotion-receipt`·`finding` 을 공포하지 않고 종료 코드 1 과 전용 명령 안내를 낸다. `repeal`·`amend`·화면 편집·`restore` 의 개정·폐지는 대상 기록의 실제 유형으로 판정한다: 대법원 결정(`ruling` 의 `level: supreme`)·가림 기록·승격 영수증(`promotion-receipt`)은 어느 명령으로도 개정·폐지하지 못하고, 항소심 결정·이의·개정안·판결 등록·목차·보고·사실인정은 전용 명령(`court`·`judgment`·`dream`/`contents`·`finding`)의 경로만 개정·폐지한다(그 밖은 종료 코드 1). `restore <batch>` 는 묶음 안에 되돌릴 수 없는 기록이 하나라도 있으면 아무것도 쓰지 않고 종료 코드 1 과 이유 목록을 낸다. 드리밍 묶음(드리밍 보고가 적은 묶음)은 예외로, 드리밍이 만든 사실인정·목차·보고와 아직 심리되지 않은 이의·개정안까지 CLI `restore` 가 되돌린다(이미 결정이 난 이의·개정안이 있으면 종료 코드 1). 판결 등록의 확정(`status: confirmed` 로 등록·개정)은 `--testimony <speaker: user 증거 id>` 가 없으면, 확정 판결 등록의 개정·폐지(`judgment amend`·`judgment repeal`·`restore`)는 대법원 결정의 `per-ruling` 인용이 없으면 종료 코드 1 이다(확정 판결의 변경은 `court` 개정안 → 대법원 결정의 조치). `promote` 는 지식 기록(`record`·`article`·`judgment`)과 `evidence` 만 승격하고 그 밖의 유형은 종료 코드 1 이다. 에이전트 세션(실행 도구 세션 id 환경 변수·`AI_AGENT`·`CLAUDECODE`·`human` 이 아닌 `AGENT_WIKI_RUNTIME`)에서 작성자가 사람(`user:`)이면 공포·`dream resume` 은 종료 코드 1 이다. 사람 공포의 `--speaker` 는 `user` 만 받는다.
- ledger 2 원장의 `enact`·`amend`·`repeal` 은 모델 기록 옵션(`--runtime`·`--model` 등)을 쓰지 않고, 받으면 무시함을 표준 에러에 알린다.
- `dream run --scheduled` 는 드리밍 기기가 아닌 곳에서 아무것도 하지 않고 종료 코드 0 이다(`dream run` 은 거부 1).
- 그 밖의 옛 쓰기 명령(`discuss`, `learn`, `review`, `event`, `task`, `agent` 등)은 ledger 2 원장에서만 동작하고, ledger 3 원장에서는 64 와 새 명령 안내를 낸다. `checkpoint` 는 두 형식 모두에서 동작한다.
- 종료 코드: 0 성공, 1 거부(모델 미상, 증언 불일치, 전신 쓰기, 소환 범위 밖, 기기 키 미등록, 드리밍 기기 아님, 허용되지 않은 관계, 안전장치 위반, 처리 유형의 일반 공포, 되돌릴 수 없거나 전용 경로가 필요한 대상의 개정·폐지·원상회복, 승격할 수 없는 유형, 에이전트 세션의 사람 작성자), 2 감사 위반, 64 사용법 오류·폐지된 명령.
- 읽기 전용 프록시는 공포·개정·폐지·원상회복·사실인정·`exhibit put`·가림·적재·동기화·`dream run|resume`·심급의 쓰기·판결 등록·승격·원장 설정·훅을 거부한다.
