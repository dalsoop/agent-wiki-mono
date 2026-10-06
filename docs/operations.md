# 운영

## 준비물

- macOS 15 이상, Swift 6.1 이상 툴체인(Xcode 16.3 이상). 모든 패키지의 플랫폼 하한이 macOS 15다.
- 첫 빌드 때 SwiftPM이 `swift-crypto`, Sparkle 등 외부 패키지를 받으므로 네트워크가 필요하다.
- `apps/agent-wiki-editor`와 `apps/agent-wiki-reader`를 빌드하려면 저장소 루트 옆이 아니라 **저장소 루트 안**에 `agent-wiki-ui/` 패키지(제품 `KnowledgeBaseWikiUI`)가 있어야 한다. 이 디렉터리는 커밋되어 있지 않으므로, 새 클론에서는 두 앱을 빌드할 수 없다.
- 이 Mac의 에이전트 세션은 `swift build`·`swift test`를 직접 실행하지 못하고 빌드 대기열을 거친다.

```bash
build-queue-manager submit 'swift build --package-path agent-wiki-kit' \
  --workdir "$(git rev-parse --show-toplevel)" --wait
```

## 빌드와 테스트

저장소 루트에서 패키지별로 실행한다. 순서는 의존 순서(`citationledgerkit` → `agent-wiki-kit` → 앱)를 따른다. 첫 빌드는 `swiftkit` 전체를 컴파일하므로 수 분이 걸리고, 이후는 패키지마다 `.build/`가 따로 생긴다.

```bash
swift test  --package-path citationledgerkit
swift build --package-path agent-wiki-kit
swift test  --package-path agent-wiki-kit
swift build --package-path apps/agent-wiki-synchronizer --product agent-wiki-synchronizer
swift build --package-path apps/agent-wiki-indexer
swift test  --package-path apps/agent-wiki-indexer
swift build --package-path apps/agent-wiki-grapher
swift build --package-path apps/agent-wiki-editor
swift build --package-path apps/agent-wiki-reader
```

## 원장 설정과 경로

| 경로 | 내용 | 쓰는 주체 |
|---|---|---|
| `~/.memo-citation-ledger/config.json` | `worlds`(name·rootPath·display·layer·parent), `currentWorld` | `agent-wiki world add/use/remove/set-layer`, `agent-wiki init` |
| `~/.memo-citation-ledger/fleet.json` | fleet 레지스트리(world 가중치·건강·repo 매핑) | `agent-wiki fleet …` |
| `~/.config/citation-ledger/actor` | 기본 작성자 한 줄(예: `agent:claude@macbook`) | 사람이 직접 |
| `<world 루트>/state/` | 파생 색인·그래프 | `index`, `graph rebuild`, 발행 후 자동 갱신 |
| `~/.swift-app-state/<슬러그>.json` | 앱별 StateMirror 관측 상태 | 각 앱 |
| `~/Library/LaunchAgents/net.ranode.memo-citation-ledger.<역할>.plist` | 정기 작업 다섯 개(아래 "정기 작업과 동기화" 표) | `agent-wiki schedule` |

환경 변수:

| 변수 | 역할 | 범위 |
|---|---|---|
| `SWIFT_APP_STATE_ROOT` | 호스트 상태 루트(`~` 대신). `config.json`·`fleet.json` 위치가 이 아래로 옮겨진다 | 모든 CLI·앱 |
| `AGENT_WIKI_WORLD` | 설정되면 다른 world로의 공포 계열(`enact`·`amend`·`repeal`·`restore`·`finding`·`checkpoint`·`promote` 등)과 `promotion publish`를 거부 | 전역 CLI |
| `MEMO_LEDGER_AUTHOR` | 기본 작성자 | 전역·repo CLI |
| `CITATION_ACTOR` | `MEMO_LEDGER_AUTHOR`가 없을 때 작성자 | 모든 원장 쓰기 |
| `MEMO_LEDGER_BATCH` | `enact`·`amend`·`repeal`·`finding`·`judgment register` 의 기본 batch id | 공포 계열 |
| `GUJO_S3_ACCESS_KEY`, `GUJO_S3_SECRET_KEY`, `GUJO_S3_ENDPOINT`, `GUJO_S3_BUCKET`, `GUJO_S3_REGION` | blob 원격 저장소 접속 설정 | `gujo blob` |
| `GUJO_HUB_URL` | wiki-hub 기본 주소 덮어쓰기 | `--fleet`/`--remote` 검색 |
| `RESTIC_PASSWORD` | 백업 설정 파일에 password가 없을 때 쓰는 백업 비밀번호. 둘 다 없으면 `backup`이 실패한다 | `backup` |

## 개발용 격리 world 만들기

실제 world를 건드리지 않고 CLI를 시험하려면 호스트 상태 루트를 임시 디렉터리로 옮긴다. `init`은 설정 파일에 world를 등록하고 `currentWorld`를 바꾸므로, 이 변수 없이 실행하면 실제 설정이 바뀐다.

```bash
export SWIFT_APP_STATE_ROOT="$(mktemp -d)"
BIN=apps/agent-wiki-indexer/.build/debug/agent-wiki-indexer   # 빌드되는 CLI
$BIN init "$SWIFT_APP_STATE_ROOT/scratch-wiki"
echo "시험 본문" | $BIN --world scratch-wiki enact --title "시험" --allow-unclassified   # ledger 2 world: 옛 발행 경로
$BIN --world scratch-wiki audit
```

테스트 코드 안에서는 StateRootKit이 테스트 실행을 감지해 임시 디렉터리를 호스트 루트로 쓴다. 테스트는 `LedgerStore(root: <임시 디렉터리>)`로 직접 원장을 만든다.

## 설치

앱 설치·배포는 `app-build-manager`로 한다. 설치된 전역 CLI는 `AgentWikiGlobal.app/Contents/Helpers/agent-wiki-synchronizer`이고, `/opt/homebrew/bin/agent-wiki-synchronizer`, `/opt/homebrew/bin/agent-wiki-global`, `/opt/homebrew/bin/agent-wiki`가 모두 이 파일로 이어진다. 설치 전에 synchronizer 빌드가 통과해야 한다. 설치 뒤 확인은 다음과 같다.

```bash
agent-wiki version                                  # LedgerVersion.current 와 같아야 한다
agent-wiki --world gujo-wiki status --json          # world 이름·객체 수
agent-wiki capabilities                             # InteropKit 계약 JSON
```

## 정기 작업과 동기화

- `agent-wiki schedule`은 아래 LaunchAgent 다섯 개를 등록하고, `agent-wiki schedule list`는 등록 상태를 보여 준다. 이미 있는 plist 의 인자가 다르면(옛 `tick checkpoint`·`tick verifier`) 거두고 새 인자로 다시 등록하며, ledger 3 대응이 없어 뺀 옛 틱(`librarian`·`run-reaper`·`retrospective`)의 plist 는 거둔다.

| 역할 | 실행 | 시각 |
|---|---|---|
| `checkpoint` | `agent-wiki --as app:agent-wiki checkpoint`(기본 원장 `agent-law`) | 매일 21:30 |
| `verifier` | `agent-wiki audit`(기본 원장) | 일요일 04:30 |
| `law-sync` | `agent-wiki sync` | 10분마다 |
| `law-archive` | `agent-wiki archive` | 매일 02:00 |
| `law-dream` | `agent-wiki dream run --scheduled`(드리밍 기기가 아니면 아무것도 하지 않고 종료 코드 0) | 매일 02:30 |

- `agent-wiki gujo …`는 `--root <경로>`가 없으면 등록된 `gujo-wiki` world 루트에서 동작한다. `agent-wiki gujo status`는 `--probe` 없이는 네트워크 없이 로컬 판정(마지막 sync 시각, 피어 ahead 수, 원격에만 있는 blob 수)을 낸다. `gujo sync`는 origin에서, `gujo sync --peer <이름>`은 피어에서 fetch·merge만 한다(전신은 읽기 pull 만, 결정 0007). push 하지 않는다.
- `agent-wiki sync`는 agent-law 저장소(`~/agent-law`)에서 커밋 대기 기록을 기록마다 커밋하고, `origin`에서 받아 파일 합집합으로 합친 뒤 push 한다. 같은 경로에 다른 바이트가 오면 합치지 않고 실패(종료 코드 1)로 멈춘다. push 실패도 종료 코드 1이다. 공포 직후 커밋과 `sync`는 저장소 잠금(`.git/agent-law.lock`)을 쓰고, 대기 상한은 `AGENT_LAW_COMMIT_LOCK_SECONDS`(기본 30초)다. 마지막 결과는 `.git/agent-law-sync.json`, 커밋 대기 표시는 `.git/agent-law-pending`이다. 저장소 준비 때 `.gitignore`에 `exhibits/`·`state/`·`sessions/`를 넣는다. git 동기화 뒤에는 원장마다 `redact` 가 공포한 가림 기록에 따라 증거물·세션 조각의 로컬 사본을 지우고, 증거물을 R2 `<원장 키>/exhibits/` 와 차집합으로 올리고 받는다(받은 것은 sha256 재계산, 가린 것은 옮기지 않음). 드리밍 끝 동기화도 같은 순서다.
- `agent-wiki gujo blob status|pull`은 R2와 blob 차집합을 계산하고 받는다. 받은 blob은 sha256을 다시 계산해 맞지 않으면 버린다. 전신은 받기만 하므로 `gujo blob push` 와 `gujo blob config --access-key/--secret-key` 는 종료 코드 64로 거부한다.
- `agent-wiki backup`은 restic으로 `objects`·`events`·`blobs`를 백업한다. `state/`는 재생성할 수 있으므로 백업하지 않는다.

## agent-law (ledger 3)

근거: 결정 0007.

- 기기 등록: `agent-wiki world device register <기기 키>`. 드리밍 기기 지정: `agent-wiki world dream-device <기기 키>`.
- 원장 만들기: `agent-wiki world add agent-law --key law --root ~/agent-law/law --layer remoteShared --predecessor gujo-wiki` 등(원장 구성표대로). 층은 이름으로 정해지지 않으므로 공유 원장은 `--layer remoteShared` 를 준다. 이미 등록한 원장은 `agent-wiki world set-layer agent-law remoteShared` 로 한 번 기록한다. 테넌트 대응: `agent-wiki world tenant-map personal agent-law-person-yun-jeonghan`.
- R2 키: 둘 중 하나다(결정 0009). (1) Bitwarden 출처 — 키는 `dns-zone-manager token create --r2-bucket` 이 Bitwarden 항목(`Cloudflare R2 · agent-law`, 필드 `access-key-id`·`secret-access-key`)에 저장한다. 한 번 `agent-wiki world storage --credential-source bitwarden:<item id>` 로 출처를 지정하면, 키체인에 값이 없을 때 `archive`(`--dry-run` 제외)·`redact`·`sync`·드리밍 기기의 `dream run` 이 시작할 때 `vaultwarden-client item field exec` 로 자신을 다시 실행해 값을 하위 프로세스 환경으로만 받는다(`vaultwarden-client` 는 PATH 에서 찾는다. 금고가 잠겨 있으면 그 실행은 실패한다). 키를 바꿔도 다른 단계가 없다. 지우기는 `--credential-source none`. (2) 키체인 — 금고에서 꺼내 키체인 서비스 `agent-law-r2` 에 넣는다(화면에 출력하지 않는다). 키체인에 값이 있으면 출처와 상관없이 키체인이 먼저다. 사람이 셸 환경 변수로 넣은 키는 받지 않는다. 엔드포인트·버킷 이름은 `agent-wiki world storage --endpoint <url> [--bucket <b>]` 로 호스트 설정에 둔다. 엔드포인트는 기본값이 없다 — 설정하지 않으면 `archive`(`--dry-run` 제외)·`redact` 는 "R2 엔드포인트 미설정" 안내와 함께 종료 코드 1, `summon` 의 R2 읽기·`sync` 의 증거물 동기화는 그 단계를 건너뛰고(키가 없을 때와 같다. 이 둘은 R2 가 선택 단계라 Bitwarden 재실행도 하지 않는다), `dream run` 은 거부 1. 버킷을 생략하면 `agent-law`.
- 드리밍 AI·중재자: `agent-wiki world ai dream --runtime <지원 CLI> --model <모델 id> [--effort <강도>]`, `agent-wiki world ai arbiters --add <runtime>:<model>[:<effort>]…` (비우기 `--clear`), 확인 `agent-wiki world ai show [--json]`. 소스에 기본 모델이 없다 — 드리밍 AI 가 없으면 `dream run` 은 1, 중재자가 없으면 `court hear` 는 항소심 사건을 대법원으로 회부한다.
- 예약 실행: `agent-wiki schedule` 이 체크포인트·감사·동기화(10분)·적재(하루)·드리밍(하루, 드리밍 기기만) 틱을 등록한다(위 "정기 작업과 동기화" 표).
- 확인: `agent-wiki audit`, `agent-wiki dream status`, `agent-wiki contents`.
