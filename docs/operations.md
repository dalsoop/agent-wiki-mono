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
| `<world 루트>/.git/gujo-s3.json` | R2 blob 자격 증명(권한 0600) | `agent-wiki gujo blob config` |
| `<world 루트>/state/` | 파생 색인·그래프 | `index`, `graph rebuild`, 발행 후 자동 갱신 |
| `~/.swift-app-state/<슬러그>.json` | 앱별 StateMirror 관측 상태 | 각 앱 |
| `~/Library/LaunchAgents/net.ranode.memo-citation-ledger.<역할>.plist` | 정기 작업(checkpoint 매일 21:30, librarian 매일 03:30, run-reaper 매시 45분, verifier 일요일 04:30, retrospective 일요일 05:00) | `agent-wiki schedule` |

환경 변수:

| 변수 | 역할 | 범위 |
|---|---|---|
| `SWIFT_APP_STATE_ROOT` | 호스트 상태 루트(`~` 대신). `config.json`·`fleet.json` 위치가 이 아래로 옮겨진다 | 모든 CLI·앱 |
| `AGENT_WIKI_WORLD` | 설정되면 다른 world로의 `publish`·`promotion publish`를 거부 | 전역 CLI |
| `MEMO_LEDGER_AUTHOR` | 기본 작성자 | 전역·repo CLI |
| `CITATION_ACTOR` | `MEMO_LEDGER_AUTHOR`가 없을 때 작성자 | 모든 원장 쓰기 |
| `MEMO_LEDGER_BATCH` | `publish`의 기본 batch id | `runPublish` 경로 |
| `GUJO_S3_ACCESS_KEY`, `GUJO_S3_SECRET_KEY`, `GUJO_S3_ENDPOINT`, `GUJO_S3_BUCKET`, `GUJO_S3_REGION` | blob 원격 저장소 접속. 키 둘이 모두 있을 때만 파일 설정보다 우선한다 | `gujo blob` |
| `GUJO_HUB_URL` | wiki-hub 기본 주소 덮어쓰기 | `--fleet`/`--remote` 검색 |

## 개발용 격리 world 만들기

실제 world를 건드리지 않고 CLI를 시험하려면 호스트 상태 루트를 임시 디렉터리로 옮긴다. `init`은 설정 파일에 world를 등록하고 `currentWorld`를 바꾸므로, 이 변수 없이 실행하면 실제 설정이 바뀐다.

```bash
export SWIFT_APP_STATE_ROOT="$(mktemp -d)"
BIN=apps/agent-wiki-indexer/.build/debug/agent-wiki-indexer   # 빌드되는 CLI
$BIN init "$SWIFT_APP_STATE_ROOT/scratch-wiki"
echo "시험 본문" | $BIN --world scratch-wiki publish --title "시험" --allow-unclassified
$BIN --world scratch-wiki verify
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

- `agent-wiki schedule`은 위 표의 LaunchAgent 다섯 개를 등록하고, `agent-wiki schedule list`는 등록 상태를 보여 준다.
- `agent-wiki gujo …`는 `--root <경로>`가 없으면 등록된 `gujo-wiki` world 루트에서 동작한다. `agent-wiki gujo status`는 `--probe` 없이는 네트워크 없이 로컬 판정(마지막 sync 시각, 피어 ahead 수, 원격에만 있는 blob 수)을 낸다. `gujo sync`는 origin과 fetch·merge·push를, `gujo sync --peer <이름>`은 피어에서 fetch·merge만 한다.
- `agent-wiki gujo blob status|pull|push`는 R2와 blob 차집합을 계산하고 옮긴다. 받은 blob은 sha256을 다시 계산해 맞지 않으면 버린다.
- `agent-wiki backup`은 restic으로 `objects`·`events`·`blobs`를 백업한다. `state/`는 재생성할 수 있으므로 백업하지 않는다.
