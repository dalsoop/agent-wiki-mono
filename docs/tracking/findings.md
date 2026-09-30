# 미해결 문제

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
- 병합 개정(`--supersedes` 반복, 결정 0005)은 synchronizer·`WikiCLIShared` 에만 들어갔다. editor 사본은 반복된 `--supersedes` 의 마지막 값만 쓴다.
- 지금 못 고치는 이유: editor `DualEntryAdoption.swift`의 2026-08 정책 주석과 README는 Studio `AgentWikiFullCLI`를 CLI 소스 정본으로 선언하지만, 실제 설치본과 앱 레지스트리는 synchronizer를 원천으로 쓴다. 어느 쪽을 정본으로 할지 소유자가 정해야 한다.

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
- 지금 못 고치는 이유: 사본을 유지할지, 원본을 원격 의존으로 받을지는 소유자가 정해야 한다.

## 추적되는 백업 파일이 있다

- 증상: `apps/agent-wiki-editor/Package.swift.bak-kit-20260806141945`가 커밋되어 있다.
- 영향: 옛 의존 구성을 현재 매니페스트로 오인할 수 있다.
- 지금 못 고치는 이유: 삭제는 저장소 정리 작업이라 소유자 확인이 필요하다.

