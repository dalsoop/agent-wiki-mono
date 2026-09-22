# CommandKit

`CommandKit`은 로컬 프로세스 실행의 공용 경계다. 앱이 `Process` 를 직접 돌리면
타임아웃·취소·stderr 수집이 제각각 되어 감사가 끊긴다.

## 원칙

1. **실행은 `CommandRunning` 프로토콜** — 테스트에서 목킹 가능.
2. **기본 구현 `ProcessCommandRunner`** — 타임아웃·종료 코드·stdout/stderr 정규화.
3. UI/CLI 가 같은 러너를 주입받아 결과 계약이 갈라지지 않게 한다.
4. `waitUntilExit` 무한 대기는 금지 — 러너 타임아웃 또는 명시적 취소.

## API (개념)

- `CommandRunning.run(_ executable:args:timeout:) async -> CommandResult`
- `CommandResult`: ok, exitCode, stdout, stderr, timedOut

## 채택 체크리스트

- [ ] Package에 `CommandKit`
- [ ] 새 셸/바이너리 호출은 Kit 경유
- [ ] 기존 raw `Process` 는 이관 (감사 TODO: usability-cutoff)

## 관련

- `PrivilegedKit` — 관리자 권한 배치 (Security 프레임워크)
- `RemoteExecKit` — 원격 SSH (로컬 Process 와 분리)
