# agent-wiki-mono

AI 에이전트 함대가 공유하는 append-only 지식 원장(Agent Wiki)의 엔진과 macOS 앱·CLI를 담은 Swift 모노레포다.
이 Mac에 설치된 `agent-wiki` CLI(`/opt/homebrew/bin/agent-wiki` → `AgentWikiGlobal.app`)가 `apps/agent-wiki-synchronizer`의 산출물이고, 사용자의 모든 에이전트 세션이 이 CLI로 `gujo-wiki`·`person-*` 원장을 읽고 쓴다.
사용자는 한 사람(운영자)과 그 에이전트들이며, 서버는 없고 로컬 파일 원장 + git/S3 전송이 전부다.

## 프로젝트 구조

```
agent-wiki-mono/
├── CLAUDE.md                          ← 진입점 (AGENTS.md 와 같은 내용)
├── AGENTS.md                          ← 진입점 (CLAUDE.md 와 같은 내용)
├── docs/
│   ├── architecture.md                ← 패키지 의존 방향, CLI 요청 흐름, 원장 디렉터리 3층
│   ├── business-rules.md              ← 객체 정체성, head·개정·철회, world 계층, 분류 기준선
│   ├── security.md                    ← 작성자 신원, world 격리, 자격 증명, 공개 저장소 주의
│   ├── standards.md                   ← 모듈 경계, 검증 게이트, 커밋·명명 규칙
│   ├── engineering-notes.md           ← 함정(뒤쪽 --world 무시, 빌드 깨짐 등)과 점검 절차
│   ├── operations.md                  ← 빌드·테스트·설치·원장 설정 파일
│   ├── contracts.md                   ← agent-wiki CLI 명령·출력·종료 코드 계약
│   └── tracking/
│       ├── status.md                  ← 패키지별 빌드·테스트 실측 상태
│       ├── findings.md                ← 지금 못 고친 문제
│       └── decisions/
│           ├── index.md               ← 결정 목록
│           └── NNNN-*.md              ← 개별 결정
├── citationledgerkit/
│   └── AGENTS.md                      ← 해시·시각·UUIDv7·작성자 신원 해석
├── agent-wiki-kit/
│   └── AGENTS.md                      ← 원장 엔진(KnowledgeBaseWikiCore)·공용 CLI 명령(WikiCLIShared)·BlobStoreKit
├── apps/
│   ├── agent-wiki-synchronizer/
│   │   └── AGENTS.md                  ← 설치된 agent-wiki(전역 CLI) + 메뉴바 앱
│   ├── agent-wiki-indexer/
│   │   └── AGENTS.md                  ← repo .wiki 전용 CLI(agent-wiki-local)
│   ├── agent-wiki-reader/
│   │   └── AGENTS.md                  ← 읽기 전용 프록시 CLI + 메뉴바 앱
│   ├── agent-wiki-editor/
│   │   └── AGENTS.md                  ← Studio GUI + 분기된 full CLI 사본
│   └── agent-wiki-grapher/
│       └── AGENTS.md                  ← 인용 그래프 질의(읽기 전용)
├── swiftkit/
│   └── AGENTS.md                      ← 공용 Swift 킷 사본(CommandKit·StateRootKit 등)
├── swiftkit-appscaffold/
│   └── AGENTS.md                      ← 앱 수명주기·GujoManaged 진입 가드
└── swiftkit-sparkle/
    └── AGENTS.md                      ← Sparkle 자동 업데이트 래퍼
```

## 절대 규칙

- 원장 객체 파일(`<world>/objects/YYYY/MM/<id>.md`)은 한 번 쓰면 바꾸거나 지우지 않는다. 변경은 `supersedes`, 폐기는 `retracts`를 단 새 발행으로만 한다. `LedgerStore`에 수정·삭제 API를 추가하지 않는다.
- 객체 id는 `sha256(canonicalCore())`다. `LedgerObject.coreLines()`의 필드 구성·순서·표기를 바꾸면 기존 객체 전부가 `verify`에서 "코어 변조"가 된다. 코어를 바꾸지 않고, `authoring` 같은 부수 정보는 코어 밖에 둔다.
- 개발·테스트 중에는 실제 원장(`~/gujo-wiki`, `person-*` world)에 쓰지 않는다. 설치된 `agent-wiki`는 `--world`가 없으면 `gujo-wiki`에 발행하므로, 쓰기 시험은 임시 디렉터리 루트의 `LedgerStore`나 임시 world로 한다.
- 인용은 같은 world와 그 상위(parent 사슬)만, 승격(`promotion`)은 parent 사슬 위로만 허용한다. 이 두 게이트를 우회하는 경로를 만들지 않는다.
- 이 저장소는 GitHub 공개 저장소다. S3 키·restic 비밀번호·토큰 값을 코드·문서·원장에 새로 적지 않는다.

## 작업 전에 읽을 것

- 항상: `docs/standards.md`, `docs/engineering-notes.md`, 고칠 패키지의 `AGENTS.md`.
- `LedgerObject`·`LedgerStore`·직렬화를 건드리기 전: `docs/business-rules.md`의 객체 정체성 절과 `agent-wiki-kit/AGENTS.md`의 불변식.
- CLI 명령·옵션을 바꾸기 전: `docs/contracts.md` 전체와 `docs/engineering-notes.md`의 "CLI 사본 세 벌" 항목. 같은 명령이 `WikiCLIShared`, `apps/agent-wiki-synchronizer/Sources/AgentWikiGlobalCLI`, `apps/agent-wiki-editor/Sources/AgentWikiFullCLI`에 따로 있다.
- world·인용·승격 규칙을 바꾸기 전: `docs/security.md`의 world 격리 절.
- 동기화(`gujo`)·blob·백업을 건드리기 전: `docs/tracking/findings.md`의 퇴역 호스트 항목.

## 문제 처리

다음은 발견 즉시 사용자에게 알린다.
- 실제 world의 `objects/`를 덮어쓰거나 지우거나, 기존 객체의 id를 바꾸게 되는 변경이나 사고.
- `agent-wiki verify`가 실제 원장에서 "본문 변조", "코어 변조", "삭제 감지"를 보고하는 경우.
- 하위·형제 world 인용이나 parent 사슬 밖 승격이 통과하는 경로.
- 자격 증명 값이 커밋·원장·로그에 들어간 경우.
- 설치된 `agent-wiki`를 이 저장소에서 빌드되지 않는 코드로 덮어쓰게 되는 배포.

그 밖의 문제는 `docs/tracking/findings.md`에 기록한다.
