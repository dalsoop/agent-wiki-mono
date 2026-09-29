# 미해결 문제

## 저장소 HEAD에서 전역 CLI가 빌드되지 않는다

- 증상: synchronizer 패키지의 `agent-wiki-synchronizer` 제품 빌드가 `CommandSchedule.swift` 165-172행의 정의되지 않은 `p` 때문에 실패한다(2026-09-30 확인). 첫 커밋부터 같은 상태다.
- 영향: 사용자의 모든 에이전트가 쓰는 `agent-wiki`를 이 저장소에서 다시 만들 수 없다. 설치본(2026-09-24)은 이 저장소 커밋으로 만들 수 없는 코드에서 나왔으므로, 설치본과 저장소 코드가 얼마나 다른지 알 수 없다.
- 지금 못 고치는 이유: 소스 코드 수정이 필요하다. 또한 설치본의 원천을 이 저장소로 옮길지, 설치본을 만든 원천 저장소를 정본으로 둘지는 소유자가 정해야 한다.
- 접근: `launchctl` 함수를 `SafeProcessRunner.run` 결과의 종료 코드를 돌려주도록 다시 쓰고 빌드한 뒤, 설치본과 `capabilities` 출력을 비교한다.

## `agent-wiki-kit` 테스트가 컴파일되지 않는다

- 증상: `agent-wiki-kit` 테스트 실행이 `GujoBlobSyncTests.swift:109`에서 `GujoHubClient.defaultBaseURL`(현재 `URL?`)에 `.absoluteString`을 바로 붙인 줄 때문에 컴파일 단계에서 실패한다. 테스트 파일 29개가 하나도 실행되지 않는다.
- 영향: 원장 엔진(정체성 해시, verify, 인용 게이트, 분류 기준선)을 바꿔도 회귀를 잡을 테스트가 돌지 않는다.
- 지금 못 고치는 이유: 테스트 코드 수정이 필요하고, 그 테스트가 기대하는 고정 호스트(`wiki.50.internal.kr`)가 현재도 정답인지는 소유자가 정해야 한다. 코드는 이미 호스트를 소스에 두지 않고 환경 변수와 EndpointRouterKit에서 얻는다.
- 접근: 기본 주소 테스트를 "환경 변수가 있으면 그 값"으로 바꾸고 옵셔널을 풀어 쓴다.

## `agent-wiki-ui` 패키지가 커밋되어 있지 않다

- 증상: 새 클론에서 `apps/agent-wiki-editor`와 `apps/agent-wiki-reader`를 빌드하면 `agent-wiki-ui doesn't exist in file system`으로 의존성 해석이 실패한다. 이 Mac의 메인 체크아웃에는 추적되지 않는 `agent-wiki-ui/`가 있다.
- 영향: 두 앱은 이 Mac의 메인 체크아웃에서만 빌드되고, 다른 worktree·클론·다른 Mac에서는 빌드되지 않는다.
- 지금 못 고치는 이유: `agent-wiki-ui`를 이 저장소에 넣을지, 별도 저장소로 둘지 소유자 결정이 필요하다.

## grapher CLI가 빌드되지 않는다

- 증상: grapher 패키지 빌드가 `AgentWikiGraphCLI/main.swift` 293-298행(SafeProcessRunner 전환 뒤 남은 옛 `catch` 본문), 339행(`isoDateFormatter` 동시성), 351행(`CLI.usage` 없음)에서 실패한다.
- 영향: `agent-wiki-graph` CLI와 창 앱을 이 저장소에서 만들 수 없다.
- 지금 못 고치는 이유: 소스 코드 수정이 필요하다.

## `publish --of`와 `world add --display`가 옵션 검사에서 거부된다

- 증상: `agent-wiki publish --of <id>`와 `agent-wiki world add … --display <이름>`이 "unknown option(s)"로 종료 코드 64를 낸다. 발행 파서와 world 파서는 두 옵션을 읽지만, 전역·repo CLI의 `allowedOptions`에 두 옵션이 없다. 설치본에서도 `--of` 거부를 확인했다(2026-09-30, 쓰기 없음).
- 영향: scene-evidence 발행(`--kind scene-evidence`는 `--of`가 필수)이 CLI로는 불가능하고, world 표시 이름을 CLI로 등록할 수 없다.
- 지금 못 고치는 이유: 두 CLI의 `main.swift` 수정과 재빌드가 필요하며, 전역 CLI는 먼저 빌드 오류부터 고쳐야 한다.

## 상위 world를 인용한 발행은 분류·batch를 처리하지 않는다

- 증상: `--cite`가 상위 world 객체를 가리키면 `runScopedPublish`로 가서, 기준선 이후 미분류 지식도 거부되지 않고, `--domain` 등 분류 인자와 `--batch`·`MEMO_LEDGER_BATCH`가 무시된다.
- 영향: 개인·테넌트 world에서 `gujo-wiki`를 인용하는 흔한 발행이 분류 없이 들어가 `verify` 위반으로 쌓이고, batch 단위 `rollback` 대상에서 빠진다.
- 지금 못 고치는 이유: 두 발행 경로의 인자 파서를 합치는 코드 수정이 필요하다.

## Studio(editor)에 분기된 full CLI 사본이 있다

- 증상: `apps/agent-wiki-editor/Sources/AgentWikiFullCLI`가 `agent-wiki`라는 같은 제품명으로 전체 명령을 구현하지만, `WikiCLIShared`·synchronizer 파일과 파일마다 수 줄에서 수백 줄씩 다르다.
- 영향: editor를 설치하면 PATH의 `agent-wiki`가 다른 동작의 바이너리로 바뀔 수 있다. 한쪽에서 고친 결함이 다른 쪽에 남는다.
- 지금 못 고치는 이유: editor `DualEntryAdoption.swift`의 2026-08 정책 주석과 README는 Studio `AgentWikiFullCLI`를 CLI 소스 정본으로 선언하지만, 실제 설치본과 앱 레지스트리는 synchronizer를 원천으로 쓴다. 어느 쪽을 정본으로 할지 소유자가 정해야 한다.

## 퇴역·미확인 호스트가 기본값으로 남아 있다

- 증상: `GujoWikiRemote`의 기본 git 원격 1순위가 퇴역한 `gitlab-ssh.internal.kr`이다. `CommandBackup`의 기본 restic 저장소가 퇴역한 호스트 `pve`의 sftp 경로다. `CommandPublish`의 원격 전사 기본값(`whisper.50.internal.kr`)과 editor `CommandQuery`의 wiki-hub 주석(`wiki.50.internal.kr`)은 현재 유효한지 확인되지 않았다.
- 영향: `~/.gitlab-status-ui/endpoints.json`이 없는 환경에서 `gujo` 안내 clone 주소가 닿지 않는 호스트를 가리킨다. 백업 설정 파일이 없으면 `backup`이 닿지 않는 저장소로 간다.
- 지금 못 고치는 이유: 대체 호스트와 백업 저장소 위치는 소유자가 정해야 하고, 소스 수정이 필요하다.

## 공개 저장소에 기본 백업 비밀번호와 계정 전용 엔드포인트가 있다

- 증상: `CommandBackup`은 설정 파일이 없을 때 코드에 적힌 기본 restic 비밀번호를 쓴다. `GujoBlobSync`는 계정 전용 R2 엔드포인트 주소를 기본값으로 가진다. 저장소는 GitHub 공개 저장소다.
- 영향: 기본값으로 만든 restic 저장소는 누구나 비밀번호를 안다. 계정 식별자가 공개되어 있다.
- 지금 못 고치는 이유: 이미 공개된 값의 교체·폐기와 기본값 제거 여부는 소유자가 정해야 한다.

## 앱 진입 가드가 자격을 검사하지 않는다

- 증상: 모든 CLI가 첫 줄에서 `GujoManaged.exitIfNotEntitledSync()`를 부르지만, 구현은 낡은 설치본 경고만 내고 인자·번들 id·종료 코드 파라미터를 버린다. 각 앱 `gujo-product.json`은 구독(Gujo Pass) 상품으로 등록되어 있다.
- 영향: 스토어 등록과 달리 설치된 CLI는 구독 여부와 상관없이 모두 동작한다.
- 지금 못 고치는 이유: 자격 검사를 켤지는 제품 소유자의 결정이다.

## 읽기 전용 reader가 호스트 설정을 바꾸는 `world use`를 허용한다

- 증상: `agent-wiki-reader world use <이름>`이 허용 목록을 통과해 `~/.memo-citation-ledger/config.json`의 `currentWorld`를 바꾼다. 조회 명령도 파생 색인(`state/index.db`)을 갱신한다.
- 영향: "보고용 읽기 전용" 클라이언트를 쓴 뒤 repo CLI·GUI의 현재 world가 바뀐다.
- 지금 못 고치는 이유: `world use`를 막을지(현재 world 전환을 reader 기능으로 볼지) 소유자 결정이 필요하다.

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
- 지금 못 고치는 이유: 사본을 유지할지, 원본을 원격 의존으로 받을지는 소유자가 정해야 한다.

## 추적되는 백업 파일이 있다

- 증상: `apps/agent-wiki-editor/Package.swift.bak-kit-20260806141945`가 커밋되어 있다.
- 영향: 옛 의존 구성을 현재 매니페스트로 오인할 수 있다.
- 지금 못 고치는 이유: 삭제는 저장소 정리 작업이라 소유자 확인이 필요하다.

## world 잠금 환경 변수가 기본 world 발행을 막지 않는다

- 증상: `AGENT_WIKI_WORLD`가 설정된 프로세스에서 `--world` 없이 `agent-wiki publish`를 실행하면 거부되지 않고 `gujo-wiki`에 발행된다. 잠금은 명시한 `--world`가 다를 때만 동작한다.
- 영향: 테넌트·개인 world로 잠근 세션이 실수로 `--world`를 빠뜨리면 그 내용이 공유 world에 들어간다. 원장은 append-only라 철회 발행으로만 가릴 수 있고 파일은 남는다.
- 지금 못 고치는 이유: 잠금이 기본 world 쓰기도 막아야 하는지, 아니면 잠금 값을 기본 world로 써야 하는지 소유자가 정해야 하고, 그다음 CLI 코드 수정이 필요하다.
