# 아키텍처

## 패키지 구성과 의존 방향

모든 패키지는 독립 SwiftPM 패키지이고, 서로 `.package(path:)`로 연결된다. 루트 `Package.swift`는 없다. 플랫폼은 전부 macOS 15, swift-tools 6.1이다.

```
citationledgerkit ─┐
                   ├─> agent-wiki-kit ─┬─> apps/agent-wiki-synchronizer
swiftkit ──────────┘                   ├─> apps/agent-wiki-indexer
swiftkit-appscaffold ──────────────────┤─> apps/agent-wiki-editor  (+ agent-wiki-ui, 저장소 밖)
swiftkit-sparkle ──────────────────────┤─> apps/agent-wiki-reader  (+ agent-wiki-ui, 저장소 밖)
                                       └   apps/agent-wiki-grapher (agent-wiki-kit 미사용, swiftkit 의 WikiLedgerKit 사용)
```

| 패키지 | 역할 | 의존 대상 |
|---|---|---|
| `citationledgerkit` | 내용 주소 해시(`sha256Hex`), ms 정밀 ISO 시각, UUIDv7, 작성자 신원 해석(`CitationActor`) | `swift-crypto`(외부, GitHub) |
| `agent-wiki-kit` / `KnowledgeBaseWikiCore` | 원장 엔진: 객체 모델, 저장소, verify, world 설정, 인용·승격 게이트, 색인(SQLite FTS), 그래프, 사건 로그, git·S3 동기화, fleet 질의 | `citationledgerkit`, `swiftkit` |
| `agent-wiki-kit` / `WikiCLIShared` | CLI 명령 구현 공용 라이브러리(`runPublish`, `runVerify`, `runScopedSearchOrContext` 등) | `KnowledgeBaseWikiCore`, `swiftkit` |
| `agent-wiki-kit` / `BlobStoreKit` | `KnowledgeBaseWikiCore`가 재수출하는 blob 저장 모듈 | 없음 |
| `apps/agent-wiki-synchronizer` | 전역 CLI(제품명 `agent-wiki-synchronizer`, 런타임 슬러그 `agent-wiki-global`)와 메뉴바 앱 `AgentWikiGlobal`. 설치된 `agent-wiki`의 원천 | `agent-wiki-kit`, `citationledgerkit`, `swiftkit*` |
| `apps/agent-wiki-indexer` | repo `.wiki/` 전용 CLI(제품명 `agent-wiki-indexer`, 슬러그 `agent-wiki-local`)와 메뉴바 앱 | `agent-wiki-kit`, `citationledgerkit`, `swiftkit*` |
| `apps/agent-wiki-reader` | 설치된 `agent-wiki`를 하위 프로세스로 부르는 읽기 전용 프록시 CLI와 메뉴바 앱 | `agent-wiki-kit`, `agent-wiki-ui`, `swiftkit*` |
| `apps/agent-wiki-editor` | Studio GUI(`AgentWikiStudio`), 얇은 CLI(`agent-wiki-editor`, 슬러그 `agent-wiki-studio`), 그리고 분기된 full CLI 사본(제품명 `agent-wiki`) | `agent-wiki-kit`, `agent-wiki-ui`, `swiftkit*` |
| `apps/agent-wiki-grapher` | 원장을 읽기 전용으로 읽어 인용 그래프 질의(orphans·centrality·impact·path·context)를 내는 창 앱과 CLI(슬러그 `agent-wiki-graph`) | `swiftkit`(WikiLedgerKit·GraphEngineKit·GraphRAGKit) |
| `swiftkit` | 공용 킷 약 100개의 사본. 이 저장소의 패키지가 쓰는 것은 CommandKit, StateRootKit, InteropKit, AgentCLIKit, SigV4Kit, EndpointRouterKit, LocalizationKit, StateMirrorKit 등 일부다 | 외부 SwiftPM 패키지 |
| `swiftkit-appscaffold` | 앱 수명주기, `GujoManaged` 진입 가드(trait `GujoManaged`·`SelfUpdating`·`Telemetry`) | `swiftkit` |
| `swiftkit-sparkle` | Sparkle 자동 업데이트 래퍼(`SparkleUpdateKit`) | Sparkle |

`agent-wiki-ui`(SwiftUI 원장 화면, 제품 `KnowledgeBaseWikiUI`)는 editor와 reader가 `../../agent-wiki-ui` 경로로 의존하지만 저장소에 커밋되어 있지 않다.

## 원장(world) 디렉터리 구조

world 하나는 디렉터리 하나이고, 그 아래가 세 층으로 나뉜다.

| 층 | 경로 | 성격 |
|---|---|---|
| 원본층 | `blobs/<sha 앞 2자>/<sha256>` | 날것 바이트(로그·캡처·PDF). 이름이 곧 sha256이며 한 번 쓰면 그대로다 |
| 사건층 | `events/*.ndjson` | `{occurred, subject, rel, object, source}` 사실 로그. 해석 객체가 `observes`로 가리킨다 |
| 해석층 | `objects/YYYY/MM/<id>.md` | 프런트매터 + 본문 마크다운 객체. 원장의 정본 |
| 파생층 | `state/index.db`, `state/graph.db` 등 | 해석층에서 언제든 재생성하는 SQLite 색인·그래프. 백업 대상에서 빠진다 |

world 목록은 호스트 파일 `~/.memo-citation-ledger/config.json`(`LedgerConfig`, StateRootKit `hostPath`로 해석)에 있고, fleet 레지스트리는 `~/.memo-citation-ledger/fleet.json`이다. world 디렉터리 경로는 이 설정이 정한다.

## 대표 흐름: `agent-wiki --world gujo-wiki publish ...`

1. `AgentWikiGlobalCLI/main.swift`가 `SingleInstanceCLI.autoGuard()`와 `GujoManaged.exitIfNotEntitledSync()`를 먼저 부른다.
2. `CLIArgv.peelLeadingGlobals`가 명령 앞의 `--as`·`--world`만 떼어 낸다. 작성자 기본값은 `MEMO_LEDGER_AUTHOR` 환경 변수, 없으면 `CitationActor.resolve()`다.
3. 허용 옵션 집합 밖의 `-`로 시작하는 인자가 있으면 종료 코드 64로 끝낸다.
4. world 없이 동작하는 명령(`help`, `version`, `capabilities`, `install`, `skill*`, `hook`, `schedule`, `init`, `world`, `gujo`, `fleet`, `pull`, `weight`)은 여기서 처리하고 끝난다.
5. `LedgerConfig.load()` → `resolveWorld(explicitWorld: --world 값 또는 "gujo-wiki", tenantWikiWorld: 활성 테넌트 world)`로 world를 정한다. 전역 CLI는 cwd의 `.wiki`를 찾지 않는다. 등록되지 않은 이름이면 실패한다.
6. `publish`는 `WorldEnvLock`(환경 변수 `AGENT_WIKI_WORLD`)을 먼저 확인하고 `runWorldAwarePublish`로 간다.
7. `enforceCiteGate`가 모든 world를 스캔해 각 `--cite` id가 있는 world를 찾고, 같은 world나 상위 world가 아니면 거부한다.
8. 인용 대상이 모두 현재 world에 있으면 `runPublish`(분류 검사·선별 객체 발행 포함), 하나라도 상위 world에 있으면 `runScopedPublish`로 간다.
9. `LedgerStore.publish`가 NFC 정규화 → canonicalCore 계산 → id 결정 → `objects/YYYY/MM/<id>.md`에 `withoutOverwriting`으로 쓴다.
10. `syncIndexAfterWrite`가 파생 색인을 갱신하고, 표준 출력에 64자 id 한 줄을 낸다.

## 원격 연결

| 대상 | 쓰는 코드 | 전송 | 방향 |
|---|---|---|---|
| gujo-wiki git 원격(GitLab, seed) | `GujoSync` | `/usr/bin/env git` 하위 프로세스 | origin과 fetch·merge·push, 피어는 fetch·merge만 |
| blob 저장소(Cloudflare R2, S3 호환) | `GujoBlobSync` | URLSession + SigV4 서명 | 로컬에만 있는 blob push, 원격에만 있는 blob pull |
| wiki-hub | `GujoHubClient` | HTTPS GET, 응답은 `FleetPullResult` JSON | 읽기 전용 검색 |
| restic 백업 | `CommandBackup` | `restic` 하위 프로세스 | `objects`·`events`·`blobs`만 백업 |
| Gujo 스토어 메타데이터 | 각 앱 `gujo-product.json` | 파일(스토어 쪽이 읽음) | 이 저장소는 선언만 한다 |

wiki-hub 주소는 환경 변수 `GUJO_HUB_URL`이 먼저이고, 없으면 EndpointRouterKit의 `wiki-hub` 항목이다. git 원격 주소는 `~/.gitlab-status-ui/endpoints.json`(StateRootKit 경로)이 있으면 그 우선순위를 따르고, 없으면 코드의 기본 목록을 쓴다.

## 앱 4면 구성

각 앱은 GUI 타깃, `*Core` 라이브러리, `*CLI` 실행 타깃, StateMirror 게시(`~/.swift-app-state/<슬러그>.json`)를 갖는다. CLI의 `capabilities`가 InteropKit 계약 JSON을 내고, 각 앱의 `interop.json`은 런타임 슬러그(`cli`)만 선언한다. GUI를 쓰지 않는 PATH CLI 타깃은 AppKit·SwiftUI를 import하지 않는다.
