# agent-wiki-kit

## 범위

| 타깃 | 담당 |
|---|---|
| `KnowledgeBaseWikiCore` | `LedgerObject`(모델·직렬화·canonicalCore), `LedgerStore`(발행·스캔·verify·체크포인트·롤백), `LedgerConfig`·`WorldBinding`(world 설정·층·parent), `WorldCiteGate`·`WorldPromotionGate`·`WorldEnvLock`, `LedgerClassificationPolicy`, `LedgerIndex`(SQLite FTS 파생 색인), `LedgerGraph`, `EventLog`, `PromotionService`·`PromotionVerifier`, `GujoSync`(git), `GujoBlobSync`(R2), `GujoHubClient`, `FleetRegistry`·`FleetPull`, 저장소 작업 그래프(`RepositoryAgent*`, `TaskGraph`) |
| `WikiCLIShared` | 두 CLI(전역·repo)가 공유하는 명령 구현 `run*` 함수와 `fail`·`printJSON`·`resolve` 같은 CLI 보조 함수 |
| `BlobStoreKit` | `blobs/<앞 2자>/<sha256>` 저장·조회·gc·무결성. `KnowledgeBaseWikiCore`가 재수출한다 |

범위 밖: 명령 분기(`main.swift`), 허용 옵션 목록, fleet·gujo·promotion·schedule·task·world 명령의 CLI 표면은 각 앱 CLI 타깃이 가진다. GUI 코드는 두지 않는다. 앱 패키지를 import하지 않는다.

## 불변식

- `LedgerStore`의 쓰기 연산은 발행뿐이다. 수정·삭제 API를 추가하지 않는다. 롤백과 체크포인트도 발행으로 구현한다.
- `publish`는 `objects/YYYY/MM/<id>.md`(UTC 연·월)에 `.withoutOverwriting`으로 쓴다. 같은 id 파일이 있으면 바이트가 같을 때만 성공한다.
- `coreLines()` 순서: ledger, published, author, title, type, batch, origin, tags, cite…, observes…, supersedes, retracts, source, unknownFields. `serialize()`는 그 사이에 id·sha256을 끼우고 코어 뒤에 authoring을 붙인다. 순서를 바꾸면 기존 id가 모두 깨진다.
- `scan()`은 id 재해시를 검사하지 않는다. 무결성 판단은 `verify()` 결과로만 한다.
- `processTypes`가 처리 기록 type의 유일한 목록이고, `processTypesSQL`은 그것에서 파생한다.
- `LedgerConfig.resolveWorld`는 명시 world, cwd `.wiki`, 테넌트 world가 모두 없으면 `nil`이다. `currentWorld`로 폴백하지 않는다.
- `LedgerConfig.configURL`은 StateRootKit `hostPath`를 쓴다. 테넌트 상태 루트가 아니라 호스트 파일을 읽어야 `--world person-*`가 테넌트 컨텍스트에서도 풀린다.
- 인용은 같은 world와 조상 world만, 승격은 parent 사슬로만 허용한다. `verify`의 참조 무결성 검사는 `promotes`·`promoted-as` 관계만 예외로 둔다.
- `KnowledgeBaseWikiCore`는 `Process()`를 직접 쓰지 않는다. 하위 프로세스는 CommandKit 러너로 부른다. SwiftUI·AppKit을 import하지 않는다.
- 분류 기준선 `since`는 소수 초 형식을 먼저 파싱한다. `requiresClassification`에는 철회된 객체 id 집합을 넘긴다.

## 구현 패턴

- 새 발행 인자는 `LedgerPublishExtras`에 넣고, 옛 호출부용 개별 인자 `publish` 오버로드는 그것으로 위임만 한다.
- CLI 명령 함수는 `run<Name>(store:…arguments:)` 형태로 `WikiCLIShared`에 두고, 실패는 `fail(메시지)`(종료 코드 1)로 끝낸다. 표준 출력은 결과, 표준 에러는 안내·경고다.
- 원장에 쓴 뒤에는 `syncIndexAfterWrite(store)`를 불러 파생 색인·그래프를 맞춘다.
- `WikiCLIShared`의 `CommandBackup`·`CommandInstall`·`CommandBlob`에는 아직 `Process()`가 남아 있다. 이 파일을 고칠 때 `SafeProcessRunner`로 옮기고, 함수 끝까지 옛 변수 참조가 남지 않았는지 빌드로 확인한다.

## 테스트

- 라이브러리 빌드는 통과한다(2026-09-30).
- 테스트 타깃은 `GujoBlobSyncTests.swift:109` 컴파일 오류로 빌드되지 않는다. 이 오류를 고치기 전에는 다른 테스트가 하나도 돌지 않는다.
- 테스트는 임시 디렉터리 루트로 `LedgerStore`를 만든다. 실제 world 경로를 쓰지 않는다. StateRootKit은 테스트 실행 중 호스트 루트를 임시 디렉터리로 바꾼다.
- 정체성·verify를 바꾸면 다음을 반드시 검사한다: 같은 입력의 id 재현, 프런트매터 한 글자 변조 시 "코어 변조", 본문 변조 시 "본문 변조", 같은 id 다른 바이트 발행 실패, 없는 참조 보고, 체크포인트 이후 파일 삭제 시 "삭제 감지".
- 게이트를 바꾸면 다음을 검사한다: 형제 테넌트 인용 거부, 하위 world 인용 거부, 조상 인용 허용, parent 사슬 밖 승격 거부, `AGENT_WIKI_WORLD` 잠금에서 다른 world 발행 거부.
