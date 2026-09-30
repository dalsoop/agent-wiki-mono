# 엔지니어링 노트

## 명령 뒤에 붙인 `--world`는 조회 명령에서 조용히 무시된다

- 증상: `agent-wiki search 키워드 --world person-yun-jeonghan`이 개인 world가 아니라 `gujo-wiki` 결과를 낸다.
- 원인: `CLIArgv.peelLeadingGlobals`는 명령 **앞**의 `--as`·`--world`만 떼어 낸다. 명령 뒤의 `--world`는 허용 옵션 목록에 있어서 거부되지도 않고, `pull`·`weight` 외의 명령은 그 값을 읽지 않는다. world가 정해지지 않으면 전역 CLI는 `gujo-wiki`를 연다.
- 대응: 항상 `agent-wiki --world <이름> <명령> …` 순서로 쓴다. `publish`는 뒤쪽 `--world`를 "모르는 옵션"으로 거부하므로 잘못된 world에 쓰이지는 않는다.
- 확인: `agent-wiki --world <이름> root`가 기대한 루트 경로를 출력하는지 본다.

## 발행 명령에는 `--world`를 항상 명시한다

- 보안 이슈 있음, 비공개 추적. `AGENT_WIKI_WORLD`를 쓰는 세션에서도 발행 명령 앞에 `--world <이름>`을 적는다.

## `verify`는 id 인자를 받지 않는다

- 증상: `agent-wiki verify <id>`가 그 객체만이 아니라 world 전체 위반을 출력한다.
- 원인: `runVerify`는 인자를 읽지 않고 world 전체, 승격 영수증, 체크포인트, 작업 그래프, 작성자, 분류 기준선, 색인 신선도를 모두 검사한다.
- 대응: 특정 객체의 발행 확인은 `agent-wiki --world <이름> show <id>`로 하고, `verify` 결과에서 그 id가 위반 목록에 없는지 확인한다. 다른 객체의 오래된 위반 때문에 종료 코드가 2일 수 있다.

## `scan()`은 id와 내용의 일치를 검사하지 않는다

- 증상: 코어가 변조된 객체도 `list`·`search`·`show`에 그대로 나온다.
- 원인: `LedgerStore.scan()`은 프런트매터를 파싱만 하고 저장된 id를 믿는다. id 재해시 검사는 `verify()`에만 있다.
- 대응: 무결성이 필요한 경로(승격 원본 확인 등)는 `sourceStore.verify()` 결과를 함께 본다. `PromotionService.validateSource`가 그렇게 한다. 새 경로에서 "scan에 나왔으니 진짜"라고 가정하지 않는다.

## CLI 명령 두 자리

- 명령 파일은 두 곳에 있다. `agent-wiki-kit/Sources/WikiCLIShared`(공용), `apps/agent-wiki-synchronizer/Sources/AgentWikiSynchronizerCLI`(fleet·gujo·promotion·schedule·task·world 등 전역 CLI 전용 명령). editor 의 분기 사본(`AgentWikiFullCLI`)은 editor 1.0.28 에서 지웠다.
- 설치된 `agent-wiki`의 원천은 이 저장소의 synchronizer다(`agent-wiki-synchronizer` 제품이 `AgentWikiGlobal.app/Contents/Helpers/agent-wiki-synchronizer`로 설치되고 `/opt/homebrew/bin/agent-wiki` → `agent-wiki-global` → 그 파일로 링크된다). 공용 명령은 `WikiCLIShared`에서, 전역 전용 명령은 synchronizer에서 고친다.
- 2026-09-30 까지는 설치본이 swift-app-mono 의 사본에서 빌드됐다(결정 0006). 그 사본은 퇴역했으니 거기서 고치지 않는다.

## 인용이 상위 world를 가리키면 분류 검사가 빠진다

- 증상: 기준선 이후 지식을 분류 없이 발행했는데 거부되지 않고, `--domain` 등을 줬는데 선별 객체가 생기지 않으며, `--batch`도 기록되지 않는다.
- 원인: `runWorldAwarePublish`는 인용 id가 모두 현재 world에 있을 때만 `runPublish`(분류 검사·선별 발행·batch 처리)로 간다. 하나라도 상위 world에 있으면 `runScopedPublish`로 가는데, 이 경로는 분류 인자를 해석하지 않는다.
- 대응: 상위 world를 인용한 발행 뒤에는 `agent-wiki --world <이름> classify <id> --domain … --kind … --knowledge … --reason …`로 분류를 따로 붙인다. 이 경로를 고칠 때는 두 함수가 같은 인자 파서를 쓰게 합친다.

## `gujo sync`는 커밋을 만들지 않는다

- 증상: 발행했는데 다른 Mac에서 `gujo sync` 후에도 새 객체가 보이지 않는다.
- 원인: `GujoSync.sync`는 `git fetch origin` → `merge --no-edit origin/main` → `push origin HEAD:main`만 한다. `git add`·`commit`은 이 저장소 코드 어디에도 없다. push 실패는 오류가 아니라 결과의 `pushed=false`와 메시지로만 남는다.
- 대응: sync 결과 JSON의 `pushed`를 확인한다. 새 객체를 커밋하는 주체는 이 저장소 밖에 있다.

## 발행마다 그래프를 전부 다시 만든다

- 증상: world가 커질수록 `publish`가 느려진다.
- 원인: `syncIndexAfterWrite`는 `state/index.db`가 있으면 색인을 증분 동기화하고, `state/graph.db`까지 있으면 전체 객체와 사건으로 그래프를 처음부터 다시 만든다.
- 대응: 대량 발행 작업에서는 이 비용을 감안한다. 그래프를 빼면 "노드 수가 객체 수보다 적은" 불일치가 쌓이므로 호출을 지우지 않는다.

## 분류 기준선 비교는 ms 단위여야 한다

- 증상: 기준선과 같은 초에 발행된 객체가 분류 게이트에 걸린다.
- 원인: 객체 `published`는 ms를 담는데 기준선을 초 단위로 읽으면 객체가 기준선보다 뒤로 밀린다.
- 대응: `LedgerClassificationPolicy.parseSince`는 소수 초 형식을 먼저 시도한다. 기준선 파싱을 바꿀 때 이 순서를 지킨다.

## 철회된 객체를 분류 검사에서 빼야 한다

- 증상: 시험 객체를 철회했는데 `verify`가 계속 종료 코드 2를 낸다.
- 원인: 철회 기록 자신만 빼고 철회당한 객체를 빼지 않으면 폐기한 지식에 분류를 요구하게 된다.
- 대응: `requiresClassification`에 철회된 id 집합을 넘긴다. 새 게이트를 만들 때도 같은 집합을 넘긴다.

## 설치본과 저장소 HEAD가 다르다

- 증상: 설치된 `agent-wiki`는 동작하는데, 저장소에서 synchronizer를 빌드하면 `CommandSchedule.swift`의 `launchctl` 함수에서 "cannot find 'p' in scope"로 실패한다.
- 원인: 저장소의 첫 커밋(2026-09-23)에 들어온 `launchctl` 함수는 `SafeProcessRunner.run` 결과를 받은 뒤 옛 `Process` 변수 `p`를 계속 참조한다. 설치본(`/Applications/AgentWikiGlobal.app`, 2026-09-24 설치)은 이 코드로는 빌드될 수 없으므로 다른 원천에서 빌드된 것이며, 그 원천은 이 저장소에서 확인할 수 없다.
- 대응: 이 저장소에서 `agent-wiki`를 다시 설치하기 전에 synchronizer 빌드를 먼저 고친다. 설치본 동작을 근거로 저장소 코드가 맞다고 판단하지 않는다.

## `Process` → `SafeProcessRunner` 기계 치환이 반쯤 끝난 파일이 있다

- 증상: synchronizer `CommandSchedule.swift`의 `launchctl`과 grapher `AgentWikiGraphCLI/main.swift`의 GUI 열기 함수가 컴파일되지 않는다.
- 원인: `Process` 인스턴스 `p`를 직접 띄우던 블록을 `let safeResult = SafeProcessRunner.run(…)`으로 바꾸면서 뒤쪽의 `p.isRunning`·`p.terminationStatus` 참조나 `catch` 본문을 남겼다.
- 대응: 같은 패턴을 고칠 때는 `safeResult`의 종료 코드·출력을 쓰도록 함수 끝까지 다시 쓴다. 치환 뒤에는 그 패키지를 반드시 빌드한다. `WikiCLIShared`의 `CommandBackup`·`CommandInstall`·`CommandBlob`과 editor `AgentWikiFullCLI`의 `CommandAgent`·`CommandBlob`에는 아직 `Process()`가 남아 있다.

## 빌드 명령은 빌드 대기열로 보낸다

- 증상: 이 Mac의 에이전트 세션에서 `swift build`·`swift test`를 직접 실행하면 훅이 막는다. 셸 `for` 반복문 안의 `swift build`도 막힌다.
- 대응: `build-queue-manager submit '<swift 명령>' --workdir <저장소 루트> --wait`로 하나씩 보낸다. 출력은 파일로 받아 종료 코드를 확인한다. 대기열이 "job vanished"를 내면 같은 명령을 다시 제출한다.

## 변경 점검 절차

1. 바꾼 패키지를 빌드하고, 그 패키지에 의존하는 패키지를 `citationledgerkit` → `agent-wiki-kit` → `apps/*` 순서로 빌드한다. 변경 전에 통과하던 명령이 실패하면 멈춘다.
2. 원장 동작을 바꿨다면 임시 디렉터리를 루트로 `LedgerStore`를 만드는 테스트를 추가하고, 발행 → `verify()`가 빈 배열인지 확인한다.
3. CLI 옵션을 바꿨다면 두 CLI의 `allowedOptions`와 `capabilities` 출력을 모두 확인한다.
4. 설치까지 한다면 설치 뒤 `agent-wiki version`과 `agent-wiki --world gujo-wiki status --json`으로 동작을 확인한다.
