# InteropKit

`InteropKit`은 앱 상호운용 계약(`docs/app-interop-contract.md`)의 **코드 정본**이다.
CLI 출력 봉투, capabilities, 레지스트리 타입을 한곳에 둔다.

## 봉투

성공 / 실패 키 이름은 바꾸지 않는다 (orca 형식 채택).

```json
{"ok": true, "result": { ... }}
{"ok": false, "error": {"message": "..."}}
```

- `Envelope.ok` / `Envelope.fail` — Codable
- `Envelope.okObject` / `Envelope.failObject` — `[String: Any]` 경로
- Exit: 성공 0, 사용법 64, 실행 실패 비영

CLI 가 bare JSON 이나 줄글만 내면 에이전트 계약 위반이다. **`--json` 경로는 봉투 필수.**

## capabilities

모든 PATH CLI 는 `capabilities [--json]` 을 제공하고, 가능하면 설치 후 레지스트리에 올린다.

```text
<cli> capabilities --json
```

`Capabilities` 타입: name, version, cli, commands[], state[], health, depends[].

## 레지스트리

`~/.agent-apps/registry.json` — 앱 발견 SSOT. ship 이 capabilities 스냅샷을 upsert.

## 앱 채택 체크리스트

1. Package에 `InteropKit` (CLI 타깃).
2. `capabilities` 가 `Envelope.ok(caps)` 로 출력.
3. 기계 소비 명령은 `--json` + 봉투.
4. GUI 앱이면 같은 Core 를 CLI 가 호출 (복제 로직 금지).

## 관련

- 정본 계약: `docs/app-interop-contract.md`
- 관측: `StateMirrorKit`
