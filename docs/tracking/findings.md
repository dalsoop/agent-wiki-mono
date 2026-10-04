# 미해결 문제

## `publish --of`와 `world add --display`가 옵션 검사에서 거부된다

- 증상: `agent-wiki publish --of <id>`와 `agent-wiki world add … --display <이름>`이 "unknown option(s)"로 종료 코드 64를 낸다. 발행 파서와 world 파서는 두 옵션을 읽지만, 전역·repo CLI의 `allowedOptions`에 두 옵션이 없다. 설치본에서도 `--of` 거부를 확인했다(2026-09-30, 쓰기 없음).
- 영향: scene-evidence 발행(`--kind scene-evidence`는 `--of`가 필수)이 CLI로는 불가능하고, world 표시 이름을 CLI로 등록할 수 없다.
- 지금 못 고치는 이유: 두 CLI의 `main.swift` 수정과 재빌드가 필요하며, 전역 CLI는 먼저 빌드 오류부터 고쳐야 한다.

## 상위 world를 인용한 발행은 분류·batch를 처리하지 않는다

- 증상: `--cite`가 상위 world 객체를 가리키면 `runScopedPublish`로 가서, 기준선 이후 미분류 지식도 거부되지 않고, `--domain` 등 분류 인자와 `--batch`·`MEMO_LEDGER_BATCH`가 무시된다.
- 영향: 개인·테넌트 world에서 `gujo-wiki`를 인용하는 흔한 발행이 분류 없이 들어가 `verify` 위반으로 쌓이고, batch 단위 `rollback` 대상에서 빠진다.
- 지금 못 고치는 이유: 두 발행 경로의 인자 파서를 합치는 코드 수정이 필요하다.

## 원격 연결 기본값과 보안 관련 이슈

- 증상: 보안 이슈 있음, 비공개 추적. 일부 원격 연결·백업 기본값이 더 이상 쓰지 않는 호스트를 가리킨다.
- 백업 기본 자격 증명: 기본 자격 증명 제거됨(`4746239`). 기존 백업 저장소 비밀번호 교체 여부는 사용자 확인이 필요하다.
- 영향: 설정 파일이 없는 환경에서 동기화·백업 기본 경로가 동작하지 않을 수 있다.
- 지금 못 고치는 이유: 대체 호스트와 교체 방식은 사용자가 정해야 한다.

## 사람용 문서가 코드와 어긋난다

- 증상: 루트 `README.md`는 `agent-wiki-indexer`를 SQLite FTS·벡터 색인 엔진으로 소개하지만 실제로는 repo `.wiki/` 전용 CLI(`agent-wiki-local`)이고, 코드에 벡터 색인은 없다. README의 발행 예시 `--domain "devops" --kind "rule"`은 분류 허용 목록 밖이라 거부된다. README는 `agent-wiki fleet pull`을 안내하지만 fleet 하위 명령은 `list|doctor|scan|register|remove`이고 `pull`은 최상위 명령이다. 저장 경로를 `~/.gujo-wiki/…`로 적지만 world 루트는 설정 파일이 정한다. 앱별 README·USAGE는 옛 이름(`agent-wiki-studio-swift`, monlith, `agent-wiki-global` 제품명)을 쓰고, `gujo-product.json`의 요구 사항은 "macOS 14 이상"이지만 패키지 하한은 macOS 15다.
- 영향: README를 믿은 에이전트가 거부되는 명령을 실행하거나, 없는 기능을 전제로 설계한다.
- 지금 못 고치는 이유: README와 스토어 메타데이터는 사람이 쓰는 제품 설명이라 문구와 공개 범위를 소유자가 정해야 한다.

## 새 객체를 gujo-wiki git에 커밋하는 주체가 이 저장소에 없다

- 증상: `GujoSync.sync`는 fetch·merge·push만 하고, 저장소 어디에도 `git add`·`git commit` 호출이 없다.
- 영향: 발행한 객체가 원격으로 퍼지는 경로를 이 저장소 코드만으로는 설명할 수 없다. 커밋 주체가 멈추면 `gujo status`의 ahead·behind로만 드러난다.
- 지금 못 고치는 이유: 커밋 주체(다른 앱, LaunchAgent, 사람)가 이 저장소 밖에 있어 여기서 확인할 수 없다.

## `swiftkit` 사본과 원본의 관계가 정해져 있지 않다

- 증상: `swiftkit`, `swiftkit-appscaffold`, `swiftkit-sparkle`은 킷 약 100개를 담은 사본이고, 이 저장소 커밋(`dc4b31d`, `37135c6`)이 그 안의 EndpointRouterKit 기본값을 직접 고친다. 원본 저장소와의 동기화 절차는 저장소 안에 없다.
- 영향: 같은 킷의 수정이 저장소마다 갈라진다. 이 저장소에서 쓰지 않는 킷(가계부·세금·게임 등)도 함께 유지된다.
- 지금 못 고치는 이유: 사본을 유지할지, 원본을 원격 의존으로 받을지는 소유자가 정해야 한다. 2026-09-30 결정 0006 때 swift-app-mono 의 킷으로 다시 맞췄다(그 뒤로 이 저장소가 정본이라 swift-app-mono 쪽 변경은 들어오지 않는다).

## 추적되는 백업 파일이 있다

- 증상: `apps/agent-wiki-editor/Package.swift.bak-kit-20260806141945`가 커밋되어 있다.
- 영향: 옛 의존 구성을 현재 매니페스트로 오인할 수 있다.
- 지금 못 고치는 이유: 삭제는 저장소 정리 작업이라 소유자 확인이 필요하다.


## 화면의 수집·세대 진화 기능이 새 명령 표면에서 막힌다

- 증상: 편집·읽기 앱 화면의 수집(`capture --file`)과 세대 진화(`agent evolve`)는 CLI 를 하위 프로세스로 부르는데, 결정 0007 로 `capture` 는 폐지(64)되고 `agent` 는 ledger 3 원장에서 거부(64)된다.
- 영향: 기본 원장이 `agent-law` 가 된 뒤 이 두 화면 기능이 실패한다. 직접 편집(새 기록·개정·폐지)은 새 공포 경로로 옮겨져 동작한다.
- 지금 못 고치는 이유: ledger 3 에서 수집은 `exhibit put` + `enact`, 진화는 드리밍이 대신하는데, 화면 동작을 어떻게 바꿀지(대체·제거)는 이번 명세가 정하지 않았다.

## 사람 작성자 판정이 환경 변수에 기댄다

- 증상: CLI 에서 작성자를 사람(`user:`)으로 정한 공포·`dream resume` 은 실행 환경에 에이전트 표지(실행 도구 세션 id 환경 변수, `AI_AGENT`, `CLAUDECODE`, `human` 이 아닌 `AGENT_WIKI_RUNTIME`)가 없을 때만 받는다(`LawActorResolution`). 에이전트가 `env -u CLAUDE_CODE_SESSION_ID -u CLAUDECODE -u AI_AGENT … agent-wiki --as user:… enact …` 처럼 표지를 지우고 부르면 사람 공포로 통과한다.
- 영향: 사람 공포는 `speaker: user` 로 고정되므로, 표지를 지운 에이전트가 증언 확인 없이 `speaker: user` 기록을 만들고 `dream resume` 으로 드리밍 정지를 풀 수 있다. 대법원 결정은 증거 기록의 증언 확인(세션 발화 대조)을 따로 요구하므로 이 경로만으로는 열리지 않는다.
- 지금 못 고치는 이유: 같은 사용자 계정의 하위 프로세스에서 사람과 에이전트를 가를 신뢰할 수 있는 표지가 없다. 막으려면 사람만 가진 비밀(키체인 확인·생체 인증·서명 키)로 사람 공포를 서명하는 방식이 필요하고, 그 방식과 화면 편집·CLI 의 사용 흐름은 사용자가 정해야 한다.

## 대법원·판결 확정의 증언이 그 사건에 묶이지 않는다

- 증상: 판결 확정(`--testimony`)과 대법원 결정은 `speaker: user` 증거라면 그 사건과 관계없는 옛 발화도 받는다.
- 영향: 증거 자체는 세션 대조로 위조할 수 없지만, "사용자가 바로 이것을 승인했다"는 뜻까지 보장하지는 않는다.
- 지금 못 고치는 이유: 공지 뒤에 공포된 증거만 받을지, 대상 id 를 인용한 증거만 받을지는 사용자가 정할 정책이다. 또한 "사용자 증언 인용" 판정이 `LawEnactPath.citesUserTestimony` 와 `LawEnactValidator.hasUserTestimony` 두 곳에 기준이 조금 다르게 있다(지금은 결과가 같다). 정책을 정할 때 한 곳으로 합친다.

## 옛 blob 동기화가 R2 계정 엔드포인트를 소스에 적어 둔다

- 증상: `agent-wiki-kit/Sources/KnowledgeBaseWikiCore/GujoBlobSync.swift` 의 `GujoBlobConfig` 기본값(`init(endpoint:)`, 환경 변수 `GUJO_S3_ENDPOINT` 가 없을 때)이 Cloudflare 계정 id 가 든 R2 엔드포인트 주소를 리터럴로 적는다. agent-law 쪽(`LawStorageSettings`)은 2026-10-04 에 이 기본값을 지우고 `world storage --endpoint` 설정에서만 받도록 바꿨다.
- 영향: 공개 저장소에 계정 엔드포인트가 남는다(docs/standards.md "소스에 새 호스트 이름을 적지 않는다", docs/security.md). 전신 원장 blob 의 `gujo blob status|pull` 은 설정 없이도 이 계정으로 붙는다.
- 지금 못 고치는 이유: 결정 0003 시절 전신 원장 전송 코드라 agent-law 작업 범위 밖이고, 기본값을 지우면 설정 파일이 없는 기기의 전신 blob 받기가 멈춘다. 지울 때는 전신 blob 설정 자리(`gujo blob config --endpoint`)와 안내를 함께 정해야 한다.
