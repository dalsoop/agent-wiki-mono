# 보안 정책

## 보호 대상

| 자산 | 위치 | 위협 |
|---|---|---|
| 원장 객체 | 각 world의 `objects/` | 덮어쓰기·삭제·변조로 에이전트 함대에 틀린 지식이 퍼지는 것 |
| 원본 blob | 각 world의 `blobs/` | 변조된 바이트가 원격으로 전파되는 것 |
| 개인·테넌트 world 내용 | `person-*`, 테넌트 world 루트 | 공유 world(`gujo-wiki`)나 다른 테넌트로 새어 나가는 것 |
| S3(R2) 자격 증명 | 환경 변수 또는 world 로컬 설정(커밋 대상 아님) | 공개 저장소·원장·로그에 노출되는 것 |
| 백업 자격 증명 | 백업 설정 | 백업 스냅샷 열람 |

## 인증

이 시스템에는 로그인이 없다. 원장은 로컬 파일이고, 파일 시스템 권한과 원격 저장소(GitLab 멤버십, R2 키)가 접근을 결정한다. 앱 코드는 world 접근 권한을 검사하지 않는다.

- 모든 CLI 진입점은 `GujoManaged.exitIfNotEntitledSync()`를 가장 먼저 부른다. 보안 이슈 있음, 비공개 추적.
- 작성자(`author`)는 호출 환경이 정하며, 발행 시점에는 검증하지 않는다.
- 작성자 검증은 사후 감사뿐이다. world 루트나 그 상위 디렉터리에 `.wiki/authors.json`(git 커미터 → actor 매핑)이 있으면 `verify`가 ledger 2 객체의 author와 그 객체를 커밋한 커미터를 대조한다. 매핑이 없으면 감사를 건너뛰고, world가 git 저장소가 아니면 "author 감사 불가" 위반을 낸다.

## world 격리 (권한 모델)

| 주체 | 동작 | 허용 조건 |
|---|---|---|
| 어느 world의 발행 | 같은 world 객체 인용 | 항상 |
| 하위 world의 발행 | 상위(parent 사슬) world 객체 인용 | 항상 |
| 상위 world의 발행 | 하위 world 객체 인용 | 거부 ("cite is upward-only") |
| 테넌트 world의 발행 | 같은 parent를 가진 형제 테넌트 객체 인용 | 거부 ("sibling tenant cite refused") |
| 어느 world | 관계없는 world 객체 인용 | 거부 |
| 하위 world | parent 사슬의 world로 승격 | 허용 |
| 어느 world | parent 사슬 밖으로 승격 | 거부. 단 parent가 없는 world는 등록된 대상이면 허용 |
| `AGENT_WIKI_WORLD`가 설정된 프로세스 | `--world`로 다른 world를 지정한 `publish`·`promotion publish` | 거부 |
| `agent-wiki-reader` 사용자 | `publish`, `capture`, `classify`, `rollback`, `checkpoint`, `promotion`, `task`, `agent`, `batch`, `policy`, `okf-export`, `weight`, `fleet`(하위 명령 전부), `init`, `hook` | 거부(종료 코드 64) |

인용 게이트는 인용 id가 들어 있는 world를 등록된 모든 world를 스캔해 찾는다. 접두어가 여러 world에 걸리면 world를 정하지 못해 "없는 객체 참조"로 거부한다.

## 감사 대상

`agent-wiki verify`가 다음을 위반으로 출력하고 종료 코드 2로 끝난다.
- 파일을 읽지 못함, 필수 프런트매터 누락, id 중복, 파일명과 id 불일치.
- 본문 sha256 불일치("본문 변조"), 64자 id의 코어 재해시 불일치("코어 변조").
- supersedes·retracts·cite(승격 관계 제외)가 없는 객체를 가리킴.
- 승격 영수증의 출처 필드 누락, repo 출처의 commit 포함 여부 불일치, repoId 불일치.
- 최신 체크포인트 대비 객체 감소("삭제 감지")나 집합 해시 불일치.
- 작업 그래프 위반, author와 커미터 불일치(`authors.json`이 있을 때).
- 기준선 이후 미분류 지식, 파생 색인이 디스크보다 뒤처짐.

## 자격 증명

- R2 blob 자격 증명은 환경 변수 `GUJO_S3_*` 또는 커밋되지 않는 world 로컬 설정에서 읽는다. 소스와 원장 객체에 키 값을 넣지 않는다.
- `backup`은 백업 설정 파일의 password나 환경 변수 `RESTIC_PASSWORD`가 있어야 실행되고, 둘 다 없으면 실패한다. 비밀번호 기본값은 코드에 없다. 원격 조회 자격 증명 처리는 보안 이슈 있음, 비공개 추적.
- git 원격 인증은 호스트의 SSH·git 설정을 그대로 쓴다. `GujoSync`는 `GIT_TERMINAL_PROMPT=0`으로 대화형 비밀번호 입력을 막는다.

## 민감 데이터

- `person-*` world와 테넌트 world는 이 Mac 1인칭 기록이다. 이 저장소의 테스트 픽스처·문서·커밋에 그 내용을 옮기지 않는다.
- 발행 시 `authoring` 필드는 환경에서 얻은 런타임·세션 정보를 기록한다. 이 값은 정체성 밖이지만 파일에는 저장되므로, 비밀이 들어갈 수 있는 환경 값을 authoring으로 흘리지 않는다.
- 이 저장소는 GitHub 공개 저장소(`dalsoop/agent-wiki-mono`)다. 내부 호스트 이름·계정 전용 엔드포인트가 이미 코드에 있으므로 새로 추가하지 않는다.
