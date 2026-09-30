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
