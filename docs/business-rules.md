# 도메인 규칙

## 용어

| 용어 | 뜻 |
|---|---|
| world | 독립 원장 하나. 이름(`gujo-wiki`, `person-yun-jeonghan` 등)과 루트 디렉터리 경로로 등록된다 |
| 객체(object) | world에 발행된 불변 마크다운 기록 하나. 프런트매터 + 본문 |
| head | 아무도 supersede하지 않았고, 철회되지 않았으며, 스스로 철회 기록도 아닌 객체. 목록·검색의 기본 대상이다 |
| 개정 | 새 객체가 `supersedes: <옛 id>`를 달고 발행되는 것. 옛 객체는 그대로 남고 head에서만 빠진다. 갈라진 개정 여럿은 병합 개정 하나가 `supersedes-also: <id>` 줄로 함께 대체한다(결정 0005) |
| 철회 | 새 객체가 `retracts: <id>`를 달고 발행되는 것. 대상과 철회 기록 둘 다 head가 아니다 |
| 인용(cite) | `cite: <id> <rel>` 줄. rel을 생략하면 `cites`다 |
| 선별(screening) | 다른 객체를 `screens` 관계로 인용하고 본문에 `domain`·`kind`·`knowledge`를 적은 분류 기록 |
| 처리 기록 | type이 `screening`, `classification`, `run`, `checkpoint`, `duplicate`, `reverification`, `reproduction`, `refutation`, `objection`, `question`, `edit-request`, `role-definition`, `review`, `policy`, `scene-evidence` 중 하나인 객체. 지식이 아니므로 분류 요구 대상이 아니다 |
| 승격(promotion) | 하위 world의 객체를 상위 world로 복사 발행하고 양쪽에 영수증을 남기는 것 |

"kind"는 두 곳에서 다른 뜻으로 쓰인다. 분류 축의 kind는 `runbook`, `decision`, `incident`, `overview`, `reference`, `note`, `evaluation` 중 하나다. 객체의 `type` 필드는 별개의 개념 유형이며, `publish --kind scene-evidence`만 예외로 type을 정한다.

## 객체 정체성

- 새 객체의 `ledger`는 2이고, id는 `sha256(canonicalCore)`의 64자리 소문자 16진수다.
- canonicalCore는 다음 순서의 줄을 `\n`으로 이은 뒤 `\n---\n`과 본문을 붙인 문자열이다: `ledger`, `published`(ms 정밀 ISO8601 UTC), `author`, 있으면 `title`, `type`, `batch`, `origin`, `tags`, 각 `cite`, 각 `observes`, `supersedes`, `retracts`, `source`(JSON 한 줄), 각 `supersedes-also`, 그리고 모르는 필드 줄. `supersedes-also` 는 옛 파서가 모르는 필드로 보존하는 자리에 두어 옛 판도 같은 id 를 계산한다.
- `id`, `sha256`(본문 해시), `authoring`(저작 런타임·비용 정보)은 코어에 들어가지 않는다. 같은 내용을 다른 비용으로 썼다고 다른 객체가 되지 않는다.
- 제목과 태그는 발행 시 NFC로 정규화된다. 본문은 정규화하지 않는다.
- 같은 id의 파일이 이미 있을 때 바이트가 완전히 같으면 발행은 성공하고 기존 객체를 돌려준다(멱등). 바이트가 다르면 `duplicateID`로 실패한다.
- 구버전(ledger 1) 객체는 UUIDv7 형식 id(36자, 대시 포함)를 가진다. 이런 객체는 코어 재해시 검사를 받지 않고 본문 sha256 검사만 받는다.
- id 접두어 조회는 접두어에 맞는 객체가 정확히 하나일 때만 성공한다. 둘 이상이면 찾지 못한 것으로 처리한다.

## 발행 규칙

- 본문은 표준 입력으로 받는다. 본문이 비어 있으면 거부한다. 단 `--retracts`가 있는 발행은 본문이 비어도 된다.
- `--supersedes`(반복 포함), `--retracts`, `--cite`가 가리키는 id는 발행 시점에 존재해야 한다. 없으면 "없는 객체 참조"로 거부한다.
- 인용은 같은 world 또는 그 상위 world(parent → parent의 parent …)의 객체만 허용한다. 하위 world, 형제 테넌트 world, 관계없는 world의 객체를 인용하면 거부한다.
- 승격 대상 world(`--to`)는 현재 world의 parent 사슬에 있어야 한다. parent가 없는 world(예: parent 미설정 repo world)는 등록된 대상 world면 허용한다. `--to gujo`는 `gujo-wiki`로 읽는다.
- `--kind scene-evidence`(또는 `--type scene-evidence`) 발행은 `--of <결정 id>`가 반드시 있어야 하고, 결정 객체를 인용하는 줄이 자동으로 붙는다. `--of`는 scene-evidence 발행 전용이다.
- 환경 변수 `AGENT_WIKI_WORLD`가 설정되어 있고 명시한 `--world`가 그와 다르면 `publish`와 `promotion publish`는 거부한다. 조회는 막지 않는다. 발행 명령에는 `--world`를 항상 명시한다.

## 분류 기준선

- 원장 안의 head `policy` 객체 중 본문에 `classification-baseline`과 `since: <ISO8601>`을 가진 최신 것이 기준선이다. 기준선 객체가 없으면 분류를 요구하지 않는다.
- 기준선 시각보다 **뒤에** 발행된 지식 객체는 분류(선별 객체)가 있어야 한다. 기준선과 같은 시각이나 그 이전 객체는 요구하지 않는다. 비교는 ms 단위다.
- 처리 기록, 철회 기록, 철회당한 객체, supersede된 객체는 분류를 요구하지 않는다.
- 발행할 때 `--domain`, `--kind`, `--knowledge`, `--classification-reason` 넷을 모두 주면 본 객체와 선별 객체 두 개가 발행된다. 넷 중 일부만 주면 거부한다.
- domain은 `agent-memory-ssot`, `agent-orchestration`, `infra-hosting`, `secrets-identity`, `gujo-commerce`, `macos-apps`, `media-ai-pipeline`, `dev-workflow` 여덟 개 중 하나다. knowledge는 `tech`, `domain`, `preference` 중 하나다. 근거 문장은 비어 있으면 안 된다.
- 분류 없이 기준선 이후 지식을 발행하려면 `--allow-unclassified`를 줘야 한다. 이 객체는 미분류 백로그로 남고 `verify`에서 위반으로 보고된다.
- 분류는 개정 사슬의 head로 따라 올라간다. 옛 판을 선별한 기록은 새 판의 분류로 읽힌다.

## 개정·롤백·체크포인트

- `rollback <batch>`는 그 batch에 속한 객체마다 새 객체를 발행한다. 대상이 개정이었으면 이전 판의 제목·본문을 `supersedes: <대상>`으로 다시 발행하고, 신규였으면 `retracts: <대상>`으로 철회한다. 파일을 지우거나 되돌리지 않는다.
- `checkpoint`는 그 시점 전체 id 집합의 개수와 해시를 본문에 적은 객체를 발행하고, 이전 체크포인트를 `checkpoints` 관계로 인용한다.
- `verify`는 최신 체크포인트 이전에 발행된 객체 수가 기록보다 적으면 "삭제 감지", 수는 같거나 많은데 해시가 다르면 "집합 불일치"로 보고한다.

## world 계층

- world 층은 `localPerson`, `tenant`, `remoteShared`, `repository`, `other` 다섯 가지다. `gujo-wiki`는 git 저장소여도 `remoteShared`다.
- `tenant` world는 반드시 parent를 가지고, parent는 `remoteShared` 층이어야 한다. parent를 주면서 층을 `tenant`가 아닌 값으로 두는 등록은 거부한다.
- 검색·컨텍스트 범위는 현재 world와 그 조상 world다. 형제·하위 world는 포함하지 않는다.
- 전역 CLI는 `--world`가 없으면 `gujo-wiki`를 연다. repo CLI(`agent-wiki-local`)는 `--world`가 없으면 cwd에서 위로 올라가며 첫 `.wiki/` 디렉터리를 연다.

## 승격 영수증

- 승격은 상위 world에 객체를 발행하고, 원본 world에 `promotion-receipt` 객체(원본을 `receipts`, 대상을 `promoted-as`로 인용)를 발행한다. 두 관계는 다른 world를 가리키므로 일반 참조 무결성 검사에서 빠지고 승격 검증기가 따로 확인한다.
- 원본이 repo world면 영수증에 repoId와 commit이 들어가고, 그 commit에 같은 바이트의 객체가 있어야 한다. 원본이 비repo world면 world 이름만 들어가고 commit 필드는 비운다.
- 영수증 객체 자신은 다시 승격할 수 없다. 같은 (원본 객체, 원본 world) 쌍의 영수증이 이미 있으면 새로 만들지 않는다.

# agent-law(ledger 3)

근거: 결정 0007. 위의 절들은 ledger 1·2 원장(전신 원장과 `novel-world`·repo world)에 계속 적용된다. ledger 3 원장에는 이 절이 적용된다.

## 용어

| 한국어 | 저장·명령 이름 | 뜻 |
|---|---|---|
| 공포 | `enact` | 기록 하나를 원장에 올림 |
| 공포일 | `promulgated` | 원장에 들어온 시각(ms 정밀 UTC) |
| 개정 | `amends`, 병합은 `amends-also` | 새 기록이 옛 기록을 대체 |
| 폐지 | `repeals` | 기록을 무효로 함 |
| 현행 | `in-force` | 개정·폐지되지 않았고 스스로 폐지 기록도 아닌 기록 |
| 연혁 | `history` | 개정 사슬 |
| 증거물 | `exhibit` | 원자료 바이트(세션 조각·인용 구절·파일). sha256 이 이름 |
| 사실인정 | `finding` | 대상 기록에 대한 판단 축 기록 |
| 원상회복 | `restore` | 묶음 하나를 되돌리는 새 기록들 |
| 감사 | `audit` | 원장 무결성 검사 |
| 전신 | `predecessor` | 새 원장이 이어받은 옛 원장(읽기 전용) |
| 가림 | `redact` | 증거물을 실제로 지우는 유일한 예외 |

`world`, `batch`, `checkpoint` 는 이름을 바꾸지 않는다.

## 원장 구성

| 원장 이름 | 원장 키 | 층 | 상위 | 전신 |
|---|---|---|---|---|
| `agent-law` | `law` | remoteShared | 없음 | `gujo-wiki` |
| `agent-law-person-yun-jeonghan` | `person-yun-jeonghan` | tenant | `agent-law` | `person-yun-jeonghan` |
| `agent-law-tenant-gujo` | `tenant-gujo` | tenant | `agent-law` | `tenant-gujo` |

- 원장 키는 `^[a-z][a-z0-9-]{1,40}$` 이고 만든 뒤 바꿀 수 없다. 로컬 루트 `~/agent-law/<원장 키>/` 와 R2 키 앞부분에 쓰인다. 세 폴더가 git 저장소 하나(gitlab.com `gujoai/agents/agent-law`)를 이룬다.
- 운영 기록 원장 `agent-ops-log`(ledger 2 형식, 전신 아님, 상위 없음)을 하나 둔다. 지식이 아닌 운영 기록(작업 `task`·인계 `handoff`, 실행 기록 `event`)을 쓰는 앱은 이 원장에 계속 쓴다. 운영 기록은 승격하지 않는다. 지식으로 올릴 것은 처음부터 테넌트·공유 원장에 공포한다(지식 후보는 테넌트 원장에서 공포한 뒤 `promote`). (2026-10-04 사용자 결정 "운영 기록용 옛 형식 원장으로", 같은 날 "운영 기록은 승격하지 않음")
- 옛 분류 축을 붙여 기록하던 앱은 공포 뒤 분야(`domain`)만 사실인정으로 함께 내고 종류·지식은 버린다. ledger 3 관계·유형 집합 밖을 쓰던 앱은 관계를 `cites` 로, 원래 뜻을 태그(`rel:<이름>`, `kind:<이름>`)로 남긴다. (같은 날 사용자 결정)
- 테넌트 → 원장 대응표: `personal` → `person-yun-jeonghan`, `gujo` → `tenant-gujo`. 테넌트 표시가 없으면 `personal` 이다. 표에 없는 테넌트는 `unassigned` 다. 표의 정본은 호스트 설정 파일이고 CLI(`world tenant-map`)로만 고친다.
- 기기마다 기기 키(원장 키와 같은 형식, 불변)를 한 번 등록한다. 미등록 기기에서는 공포와 세션 적재를 거부한다. 드리밍 기기는 하나만 지정한다.

## 전신

- 새 원장은 옛 원장 하나를 전신으로 선언한다. 전신은 사슬이 아니다.
- 전신으로 지정된 원장은 보관됨이다. 공포·개정·폐지·원상회복·체크포인트·승격 등 모든 쓰기를 거부한다.
- 인용 허용 범위는 같은 원장, 상위 사슬, 그리고 그 각각의 전신이다. 형제·하위 원장과 그 전신은 거부한다. 검색·컨텍스트 범위도 같고, 전신 객체에는 표시가 붙는다.

## 기록 정체성과 표기

- `ledger: 3`, id = `sha256(canonicalCore)`. 코어 필드 순서는 `ledger`, `promulgated`, `author`, `author-kind`, `device`, `runtime`, `runtime-version`, `model`, `effort`, `app`, `app-version`, `speaker`, `title`, `type`, `origin`, `batch`, `tags`, 각 `cites`, 각 `exhibit`, `amends`, 각 `amends-also`, `repeals`, `source`, 모르는 필드다. canonicalCore 는 이 줄들 뒤에 `\n---\n` 과 본문을 붙인 문자열이다.
- 코어 밖: `id`, `sha256`(본문 해시), `cost`(토큰 수·읽은 객체 수·세션 id).
- 파일 표기: `---`, 머리 필드(`ledger`, `id`, `promulgated`, `author`, `sha256`, 나머지 코어 순서, `cost`), `---`, 본문. 한 줄에 `키: 값` 하나. 여러 값 필드는 값마다 한 줄(`cites: <id> <rel>`, `exhibit: <sha256>`, `amends-also: <id>`). `tags: [a, b]` 는 받은 순서. 값 없는 필드는 쓰지 않는다. 제목·태그는 NFC 정규화, 본문은 그대로. canonicalCore 의 줄은 머리 필드 줄과 바이트 단위로 같다.
- 파서 정본은 공용 원장 읽기 킷(`swiftkit` WikiLedgerKit) 하나다.
- 같은 id 파일이 있으면 바이트가 같을 때만 성공한다. 한 번 쓴 파일은 고치거나 지우지 않는다. 위치: `<원장 키>/objects/YYYY/MM/<id>.md`.

## 작성자와 모델 기록

| 필드 | 값 |
|---|---|
| `author` | `agent:<이름>@<기기>` · `user:<이름>` · `app:<앱 슬러그>` |
| `author-kind` | `agent` · `human` · `app` |
| `device` | 기기 키 |
| `runtime` | `claude-code` · `codex` · `grok` · `antigravity` · `human` · `app` |
| `runtime-version` | 실행 도구 버전 |
| `model` | 정확한 모델 id |
| `effort` | `low` · `medium` · `high` · `xhigh` · `max` · `unknown` |
| `app`, `app-version` | 앱 슬러그·버전 |

- `agent` 공포는 `runtime`·`model` 이 없으면 거부한다. 추론 강도를 모르면 `unknown`.
- `app` 공포는 `app`·`app-version` 필수. AI 판단을 거친 앱 기록(드리밍·중재)은 그 판단의 `runtime`·`model`·`effort` 도 적는다. 판단 없이 기계적으로 만든 기록은 모델 칸을 비운다.
- `human` 공포는 모델 칸을 비운다.
- 아는 값만 적는다. 값의 우선순위는 명시 인자 > `AGENT_WIKI_RUNTIME`·`AGENT_WIKI_MODEL`·`AGENT_WIKI_EFFORT`·`AGENT_WIKI_RUNTIME_VERSION` > 실행 도구 환경 변수 > 세션 등록 파일이다.
- 세션 등록 파일은 세션마다 하나(`~/.agent-wiki/sessions/<세션 id>.json`)이고, 공포하는 명령은 실행 도구의 세션 id 환경 변수로 자기 세션을 찾는다. 세션 id 도 명시 값도 없으면 다른 세션을 추정하지 않고 거부한다.

## 화자

- `speaker` 는 `user` · `agent` · `external` · `other-agent`. 기본값은 작성자가 에이전트면 `agent`, 사람이면 `user`, 증거 유형이면 `external`. 사람 공포의 화자는 `user` 로 고정이다(다른 값은 거부).
- 증거 기록의 화자는 인용한 발화의 화자다. 공포할 때 인용 구절(가린 것)을, 같은 가림 규칙을 적용한 실제 세션 발화 하나의 연속된 부분 문자열과 글자 단위로 대조한다. 일치하면 그 발화의 역할을 화자로 적고, 아니면 거부한다.
- 다른 기록의 `speaker: user` 는 `speaker: user` 인 증거 기록을 `testifies` 로 인용할 때만 인정한다.
- 공유 원장(`agent-law`)의 기록에 사용자 증언이 필요하면, 개인·테넌트 원장에서 증언을 확인한 증거 기록을 `promote` 로 공유 원장에 승격한다. 승격할 때 원본 원장의 범위에서 증언을 다시 확인하고, 통과해야 승격된다. 승격된 증거 기록은 승격 영수증이 증언 확인을 대신하며 화자를 그대로 가진다. 공유 원장의 기록은 그 승격된 증거를 `testifies` 로 인용한다. 옮기기로 고른 구절만 공유로 가고 테넌트 격리는 유지된다. (2026-10-04 사용자 결정 "개인에서 확인한 증거를 승격") 태그 `promoted` 는 승격 경로만 붙이는 예약 표지이고, 영수증과 원본 대조로 확인되지 않은 승격본 주장은 감사 위반이다.

## 유형

- 지식 기록: `record`(일반), `article`(저장소를 넘는 조문), `judgment`(저장소를 넘는 판결 본문).
- 처리 기록(사실인정을 요구하지 않음): `evidence`, `finding`, `appeal`, `proposal`, `ruling`, `redaction`, `contents`(목차), `report`, `checkpoint`, `registration`(판결 등록), `promotion-receipt`.
- 처리 기록 중 `ruling`·`appeal`·`proposal`(`court`), `redaction`(`redact`), `registration`(`judgment`), `contents`(`contents`·드리밍), `report`(드리밍), `promotion-receipt`(`promote`), `finding`(`finding`·드리밍)은 괄호 안 전용 명령만 공포한다. 일반 공포(`enact`·`amend`·화면 편집)는 거부한다. 승격은 원본 유형을 그대로 옮긴다. `redact` 는 가림 기록에 예약 태그 `path:redact` 를 붙이고, 일반 경로는 `path:` 로 시작하는 태그를 받지 않는다.
- 개정·폐지(`amends`·`amends-also`·`repeals`)는 초안이 적은 유형이 아니라 대상 기록의 실제 유형으로 판정하고, 어느 경로(`repeal`·`amend`·화면 편집·`restore`·전용 명령)든 같다. `ruling` 의 `level: supreme` 은 어느 경로로도 개정·폐지하지 못한다(대법원 결정은 최종). 항소심 `ruling`·`appeal`·`proposal` 은 `court`, `registration` 은 `judgment`(확정 판결은 아래 "판결 등록"대로 대법원 결정 인용이 있어야 하고 대법원 결정의 조치인 `court` 도 된다), `contents`·`report` 는 드리밍·`contents`, `finding` 은 `finding`·드리밍 경로만 개정·폐지한다. `redaction` 은 폐지·개정하지 못한다(지운 증거물은 돌아오지 않으므로 가림은 되돌릴 수 없다). `promotion-receipt` 도 폐지·개정하지 못한다(승격본의 무결성 기록이라 고치거나 지우면 승격 확인이 깨진다). 그 밖의 기록(지식 기록 등)은 일반 경로도 개정·폐지한다. 폐지만 하는 기록은 대상 유형을 그대로 적고, 본문은 폐지 이유라 그 유형의 필수 머리 칸을 요구하지 않는다.
- 승격(`promote`)은 지식 기록(`record`·`article`·`judgment`)과 `evidence` 만 한다. 그 밖의 유형은 거부한다(종료 코드 1).
- `finding` 은 `finds` 대상이 정확히 하나다. `ruling` 의 `level: supreme` 은 `speaker: user` 증거 기록을 `testifies` 로 인용해야 공포된다.
- 옛 분류(`domain`·`kind`·`knowledge`)와 분류 기준선은 ledger 3 에 없다. 분야는 사실인정의 `domain` 칸으로, 종류는 유형으로, 지식은 축 조합으로 대신한다.

## 본문 머리 칸

유형별 추가 칸은 본문 첫 줄부터 빈 줄 전까지 `키: 값` 으로 둔다. 정해진 키만 허용한다.

| 유형 | 칸 |
|---|---|
| `finding` | `subject`(`person`·`agent-self`·`project`·`external`), `certainty`(`confirmed`·`probable`·`possible`), `effective-from`, `effective-until`, `domain`(8개 중 하나), `reason`(비면 거부) |
| `ruling` | `level`(`appellate`·`supreme`), `outcome`(`uphold`·`overturn`·`refer`·`approve`·`reject`) |
| `registration` | `repo`, `status`(`provisional`·`confirmed`), `path` |
| `proposal` | `scope` |
| `redaction` | `target`, `reason` |
| `evidence` | `session`, `utterance-at`, `runtime`, `device` |

분야 8개: `agent-memory-ssot`, `agent-orchestration`, `infra-hosting`, `secrets-identity`, `gujo-commerce`, `macos-apps`, `media-ai-pipeline`, `dev-workflow`.

## 관계

| 관계 | 출발 | 도착 | 뜻 |
|---|---|---|---|
| `cites` | 모든 유형 | 모든 기록 | 일반 참조(기본값) |
| `finds` | `finding` | 지식 기록 | 사실인정 대상 |
| `testifies` | 모든 유형 | `evidence` | 근거 증언 |
| `migrated-from` | 이관 기록 | 전신 객체 | 옮겨 온 원본 |
| `appeals` | `appeal` | 모든 기록 | 이의 대상 |
| `proposes` | `proposal` | 모든 기록 | 개정 대상 |
| `hears` | `ruling` | `appeal`·`proposal` | 다룬 건(그 심급에서 닫힘) |
| `per-ruling` | 개정·원상회복·폐지 | `ruling` | 결정에 따른 조치 |
| `checkpoints` | `checkpoint` | `checkpoint` | 이전 체크포인트 |
| `receipts`, `promoted-as` | 승격 영수증 | 원본·결과 | 승격 |

표 밖의 관계는 거부한다.

## 사실인정과 4종류

- 한 기록의 현행 사실인정은 그 기록을 `finds` 하는 사실인정 현행판 중 가장 늦게 공포된 것이다. 사실인정이 없는 지식 기록은 감사에서 "판단 대기"로 보고하되 위반은 아니다.
- 4종류(계산, 저장하지 않음, `record` 에만): 사람 = `subject: person`, 지적 = `speaker: user` 이고 `subject: agent-self`, 진행 = `subject: project`, 위치 = `subject: external`. 그 밖은 미분류.

## 출처 표시

- `origin: dream` 정리본은 다음 드리밍의 재료에서 빠지고, `testifies`·`finds` 의 근거나 증거 인용 대상이 될 수 없다. `cites` 는 된다.
- `origin: migration` 이관 기록은 재료·증거 인용이 되고, 전신 객체를 `migrated-from` 으로 반드시 인용한다. 옮기는 곳은 그 전신을 가진 원장으로 고정한다.

## 공포·개정·폐지·원상회복

- 본문은 표준 입력. 빈 본문 거부(폐지 예외). 참조 id 는 공포 시점에 허용 범위에 있어야 한다.
- 공포 직후 그 원장 파일만 git 에 커밋한다. 커밋은 저장소 잠금(대기 상한 기본 30초) 안에서 하고, 못 얻으면 "커밋 대기"로 남겨 다음 `sync` 가 커밋한다.
- `restore <batch>`: 개정이었으면 이전 판을 다시 공포, 신규였으면 폐지. 파일을 지우지 않는다. 만들 기록 하나하나가 위 "유형"의 개정·폐지 판정을 받고(CLI·화면은 일반 경로, 결정의 조치는 `court` 경로), 되돌릴 수 없는 기록이 하나라도 있으면 아무것도 쓰지 않고 이유 목록과 함께 거부한다(종료 코드 1).
- 원상회복은 전부 아니면 전무다(만들 기록 전부를 쓰기 전에 경로 판정과 공포 검증 전체로 검사), 되살린 이전 판은 원래 화자를 그대로 가진다(사람이 되돌려도 — 사람 화자 고정의 유일한 예외).
- 드리밍 묶음(드리밍 보고가 적은 묶음 id)은 반드시 되돌릴 수 있다(2026-10-04 사용자 결정 "자동 적용 + 묶음 되돌리기"). 그 묶음 안에서 드리밍(`app:agent-wiki`)이 만든 사실인정·목차·보고는 드리밍 경로로, 드리밍이 낸 이의·개정안은 `court` 경로로 되돌린다. 이의·개정안은 아직 심리되지 않은 건(그 건을 `hears` 로 인용한 결정이 없는 건)만 되돌리고, 이미 결정이 난 건이 들어 있으면 묶음 전체를 거부한다(다툼은 상고로). 드리밍 묶음이라도 드리밍이 만들지 않은 기록과 일반 묶음은 위 규칙 그대로다.
- 갈라진 현행은 감사가 보고하고 `amends-also` 병합 개정으로 푼다.

## 드리밍

- 지정 드리밍 기기에서만, 마지막 실행 뒤 24시간이 지났고 새로 적재된 세션이 있을 때 하루 한 번(조정 가능), 또는 `dream run`.
- 단계: 둘러보기 → 재료 모으기(모든 기기의 새 세션 조각, 그 세션이 찾거나 인용한 전신 객체, 설정한 저장소의 판결·조문; 정리본 제외) → AI 실행 도구 무인 호출로 정리 제안 → 안전 검사 → 묶음 하나로 공포 → 목차 → 보고·동기화.
- 할 수 없는 것: 저장소의 판결·조문 수정(알리기만), `judgment` 공포·개정·폐지, `speaker: user` 기록의 폐지·개정(항소심에 개정안), `article` 의 직접 개정(개정안), 정리본을 증거로 인용, 전신 판결 이관(항소심에 신청).
- 안전장치(조정 가능, 원장마다가 아니라 실행 전체 기준): 한 번 최대 10건(넘는 것은 다음 실행), 폐지 3건 초과 묶음은 전체 미적용 + 경보, 드리밍 묶음이 원상회복되면(누가 했든) 자동 드리밍 정지. 드리밍 묶음은 사실인정·개정안·이의가 들어 있어도 `restore` 로 되돌릴 수 있다(아래 "공포·개정·폐지·원상회복"). `dream resume` 은 `author-kind: human` 만.
- 쓰일 때만 이관: 재료 세션에서 찾거나 인용한 전신 객체만 `origin: migration` 으로 옮기고 사실인정을 함께 공포한다.
- 목차(`contents`): 원장마다 하나, 현행 기록 가리킴(id 앞 8자리 + 한 줄, 줄당 150자 이내, 200줄 이내), 맨 위에 경보·대법원 공지·이의 기간 중인 개정안.
- 보고(`report`)와 `report models`: 모델·추론 강도·실행 도구별 공포 건수, 개정·폐지·뒤집힌 비율. 측정만 하고 자동 가중치로 쓰지 않는다.

## 심급제

| 심급 | 누가 | 다루는 것 |
|---|---|---|
| 1심 | 드리밍·공포한 에이전트 | 일반 기록·사실인정. 바로 적용 |
| 항소심 | 대상 기록을 쓴 모델과 다른 모델 | 이의, 전신 판결 이관 신청, `speaker: user` 기록 개정안, 조문 개정안 |
| 대법원 | 사용자 | 규칙 완화, 확정 판결 변경, 상고 |

- 이의가 들어온 기록은 현행으로 남고 항소심 대기에 오른다.
- 항소심 결정은 유지·뒤집기·회부. 조문 개정안이 완화이면 반드시 회부한다. 다른 모델이 없으면 회부한다.
- 대법원 대기 건은 목차 맨 위에 공지되고, 이의 제기 기간(기본 72시간) 뒤에만 결정할 수 있다. 대법원 결정은 승인·기각을 말한 사용자 발화 증언(`testifies`)이 있어야 공포된다. 최종이다.
- 사건을 닫는 결정은 규칙을 지킨 것만 센다. 항소심 결정은 `app:agent-wiki` 가 대상 기록을 쓴 모델과 다른 모델로 낸 것(다른 모델이 없어 AI 없이 낸 회부만 모델 칸이 빈다), 대법원 결정은 대법원 대기였던 건에 이의 기간 뒤 공포되고 사용자 발화 증언을 인용한 것이다. 그 밖의 결정은 사건을 닫지 않는다.
- 규칙끼리 부딪히면 더 구체적인 쪽이 이긴다. 개정은 소급하지 않는다.

## 판결 등록

- `judgment register` 는 공유 원장에 `registration` 기록을 공포한다. 판결 번호는 그 id 의 앞 8자리이고 바뀌지 않는다. 상태·경로·제목 변경은 개정(`judgment amend`), 폐지는 `judgment repeal <번호> [--reason <r>]` 이다. 일반 `amend`·`repeal` 은 판결 등록을 다루지 못한다.
- 확정(`status: confirmed`)은 사용자 발화 증언이 있어야 한다. 잠정 → 확정 개정과 확정으로 처음 등록하는 것 모두 `speaker: user` 증거 기록을 `testifies` 로 인용한다(`--testimony <증거 id>`). (2026-10-04 사용자 결정 "확정 변경은 대법원으로")
- 확정 판결 등록의 개정·폐지는 무엇이든(잠정으로 되돌림·경로·제목 수정 포함) 대법원 결정(`ruling` `level: supreme`)을 `per-ruling` 으로 인용해야 한다. 그래서 `judgment amend`·`judgment repeal` 은 확정 판결을 거부하고, 확정 판결의 변경은 `court` 개정안 → 대법원 결정의 조치로 한다. 원상회복도 같은 판정을 받는다. 잠정 판결의 경로·제목 수정·폐지는 바로 된다.
- 저장소를 넘는 결정은 `judgment` 유형으로 본문까지 원장에 둔다. 저장소 판결 본문은 원장에 사본으로 두지 않는다. 저장소 쪽 번호 체계 전환 전까지는 각 저장소의 지금 번호가 정본이다.
