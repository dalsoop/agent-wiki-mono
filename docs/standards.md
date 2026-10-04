# 규칙

## 원장 쓰기

- 원장 파일에 쓰는 코드는 `LedgerStore.publish`(및 그것을 부르는 `publishScreening`, `publishCheckpoint`, `rollback`, 승격 서비스)만 사용한다. `objects/` 아래 파일을 직접 `write`·`removeItem`·`moveItem`하는 코드를 추가하면 위반이다.
- `LedgerStore.publish`의 `.withoutOverwriting` 쓰기 옵션과 "같은 id, 다른 바이트면 실패" 검사를 제거하지 않는다.
- `LedgerObject.coreLines()`와 `serialize()`의 필드 순서·표기를 바꾸지 않는다. 새 프런트매터 필드가 필요하면 정체성에 넣을지 먼저 결정하고, 넣지 않을 필드는 `authoring`처럼 `serialize()`에서 코어 뒤에 따로 붙인다.
- 처리 기록 type 집합은 `LedgerObject.processTypes` 하나가 정본이다. SQL 필터는 `processTypesSQL`에서 파생한다. 다른 곳에 같은 목록을 다시 적으면 위반이다.
- 분류 스탬프 본문 파싱은 `LedgerObject.parseClassification` 하나를 쓴다. 메모리 경로(`LedgerClassification`)와 SQL 경로(`LedgerIndex`)가 따로 파서를 두면 위반이다.

## 모듈 경계

- 의존 방향은 `citationledgerkit` → `agent-wiki-kit` → `apps/*`다. 킷이 앱을 import하거나, 앱이 다른 앱 패키지를 `.package(path:)`로 의존하면 위반이다.
- `KnowledgeBaseWikiCore`, `WikiCLIShared`, `citationledgerkit`, 각 앱의 `*Core`와 `*CLI` 타깃은 SwiftUI·AppKit을 import하지 않는다. PATH CLI가 AppKit을 링크하면 dual-entry 실행이 멈춘다.
- `KnowledgeBaseWikiCore`와 각 앱 `*Core`는 `Process()`, `system()`, `posix_spawn()`을 직접 쓰지 않는다. 하위 프로세스는 CommandKit의 `SafeProcessRunner`나 `CommandRunning` 주입으로 부른다.
- 에이전트 런타임 CLI 이름(claude, codex 등)을 문자열 리터럴로 새로 쓰지 않는다. swiftkit `SessionKit`의 `SupportedAIAgentCLI`를 쓴다.
- 인용·승격 허용 판정은 `WorldCiteGate`, `WorldPromotionGate`, `WorldEnvLock` 세 곳에만 둔다. CLI 명령마다 따로 판정 로직을 복사하지 않는다.
- `agent-wiki-reader`는 `AgentWikiReaderService.isReadOnlyInvocation`을 통과한 인자만 설치된 `agent-wiki`에 넘긴다. 쓰기 명령을 허용 목록에 넣으면 위반이다.

## CLI 표면

- 전역 CLI와 repo CLI는 허용 옵션 집합 밖의 옵션이 오면 작업 전에 종료 코드 64로 끝난다. 새 옵션을 추가하면 `apps/agent-wiki-synchronizer/Sources/AgentWikiSynchronizerCLI/main.swift`와 `apps/agent-wiki-indexer/Sources/AgentWikiLocalCLI/main.swift`의 `allowedOptions` 양쪽에 넣는다. 한쪽만 넣으면 다른 CLI가 그 옵션을 거부한다.
- 발행 명령은 표준 출력에 id 한 줄만 낸다. 부가 정보(선별 id 등)는 표준 에러로 낸다. 다른 도구가 표준 출력을 id로 읽는다.
- 앱의 도메인 조작은 그 앱 CLI로 한다. 상태 파일(`~/.swift-app-state/*.json`, `~/.memo-citation-ledger/*.json`)을 손으로 고치거나 GUI 조작으로 우회하지 않는다.
- CLI에 연산을 추가하면 `capabilities` 출력의 `commands`에도 넣는다.

## 검증 게이트

CI가 없다. 머지 전에 바꾼 패키지와 그 패키지에 의존하는 패키지를 로컬에서 확인한다. 명령은 저장소 루트에서 실행한다.

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

- 통과 기준은 "변경 전보다 나빠지지 않음"이다. 변경 전에 통과하던 명령이 변경 후 실패하면 머지하지 않는다. 변경 전부터 실패하던 명령은 같은 원인으로만 실패해야 하고, 새 오류가 추가되면 안 된다.
- `agent-wiki-kit`의 `KnowledgeBaseWikiCore`를 바꾸면 그것에 의존하는 앱 네 개(synchronizer, indexer, editor, reader)를 모두 다시 확인한다.
- `swiftkit*`를 바꾸면 이 저장소의 앱 다섯 개와 `agent-wiki-kit` 빌드를 모두 확인한다.
- 원장 쓰기 로직을 바꾸면 임시 디렉터리에 world를 만들어 `publish` → `verify` 왕복을 확인한다. 실제 world에서 확인하지 않는다.

## 커밋·브랜치

- 기본 브랜치는 `main`이고 원격은 GitHub `dalsoop/agent-wiki-mono`다. 작업은 브랜치에서 하고 PR로 머지한다.
- 커밋 메시지는 영어 Conventional Commits 형식(`type(scope): subject`)이다.
- 같은 체크아웃을 다른 세션이 쓸 수 있으므로 `git add -A`와 `git commit -a`를 쓰지 않고 경로를 지정해 스테이징한다.
- 새 `.sh`, `.py` 스크립트를 추가하지 않는다. 필요한 절차는 앱 CLI 명령으로 구현한다.

## 명명

- 앱 디렉터리 이름, SwiftPM 실행 제품 이름, 런타임 슬러그(StateMirror 파일명·`interop.json`의 `cli`·`capabilities`의 name)가 앱마다 다르다. 슬러그를 바꾸면 설치 경로·StateMirror 경로·다른 도구의 조회가 모두 끊기므로, 슬러그는 이름 정리와 별도로 결정한다.

| 디렉터리 | 실행 제품 | 런타임 슬러그 |
|---|---|---|
| `apps/agent-wiki-synchronizer` | `agent-wiki-synchronizer`, `AgentWikiGlobal` | `agent-wiki-global` |
| `apps/agent-wiki-indexer` | `agent-wiki-indexer`, `AgentWikiLocal` | `agent-wiki-local` |
| `apps/agent-wiki-reader` | `agent-wiki-reader`, `AgentWikiReader` | `agent-wiki-reader` |
| `apps/agent-wiki-editor` | `agent-wiki-editor`, `agent-wiki`, `AgentWikiStudio` | `agent-wiki-studio` |
| `apps/agent-wiki-grapher` | `agent-wiki-grapher`, `AgentWikiGraph` | `agent-wiki-graph` |

## 설정

- world 목록은 `~/.memo-citation-ledger/config.json` 하나가 정본이다. 경로는 StateRootKit `hostPath`로 해석하므로 테넌트 컨텍스트에서도 호스트 파일을 읽는다. 앱이 자기 설정에 world 경로를 따로 저장하지 않는다.
- 원격 호스트 주소는 EndpointRouterKit이나 `~/.gitlab-status-ui/endpoints.json`에서 얻는다. 소스에 새 호스트 이름을 적지 않는다.

## agent-law (ledger 3)

근거: 결정 0007.

- ledger 3 기록 형식의 파서·직렬화는 공용 원장 읽기 킷(`swiftkit` WikiLedgerKit) 하나에만 둔다. 엔진과 다른 앱은 그것을 쓴다. swift-app-mono 사본은 이 코드를 그대로 옮긴다.
- 처리 기록 유형 집합, 관계 집합, 본문 머리 칸 키 목록은 각각 한 곳의 상수다. 다른 곳에 다시 적으면 위반이다.
- 전신 쓰기 거부는 쓰기 게이트 한 곳에서 판정한다. 명령마다 판정을 복사하지 않는다. 옛 승격(`promotion publish`)도 대상 원장에 같은 게이트를 적용한다(`PromotionTargetGate`).
- 처리 유형별 허용 공포 경로(일반 공포의 처리 유형 거부, 가림 기록의 예약 태그)는 `LawEnactPath` 한 곳에서 판정한다. 전용 명령의 서비스는 `LawEnactService.enact(…, path:)` 로 자기 경로를 넘긴다.
- 사람 작성자의 에이전트 세션 거부는 `LawActorResolution` 한 곳에서 판정한다.
- 옛 `LedgerObject` 코어는 바꾸지 않는다. ledger 3 는 별도 타입이다.
- ledger 3 원장 파일에 쓰는 코드는 `LawStore.enact`(와 그것을 부르는 원상회복 등)만 사용한다. 위 "원장 쓰기" 절의 `LedgerStore.publish` 규칙과 같은 뜻이다.
- `LawRuntime` 의 값(`claude-code`·`codex` 등)은 실행 파일 이름이 아니라 기록 어휘이므로 그 상수에만 둔다. 실행 도구를 부를 때는 지원 CLI 목록을 쓴다.
- 분야 8개는 ledger 2 분류(`LedgerClassificationInput.domains`)와 ledger 3 사실인정(`LawDomain`)에 따로 있다. ledger 2 는 전신으로만 남으므로 새 값은 `LawDomain` 에만 더한다.
- 실행 도구별 세션 id 환경 변수 이름은 지원 CLI 목록 한 곳에 둔다.
- R2 키는 키체인에서만 읽는다.
