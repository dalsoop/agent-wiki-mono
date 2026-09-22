# StateMirrorKit

`StateMirrorKit`은 GUI 앱이 핵심 상태를 **스크린샷 없이** 파일로 게시하는 관측 채널이다.
에이전트·스케줄러는 `~/.swift-app-state/<앱>.json` 을 읽는다.

## 원칙

- GUI 앱 완료 계약의 한 면이다 (GUI · Core · CLI · **StateMirror**).
- 요약만 게시한다. secret·토큰·전체 로그 금지.
- 실패·복구 가능 상태도 게시한다 (막혔는데 mirror 는 ok 인 상태 금지).

## 채택 패턴

```swift
// 기동 시
mirror = StateMirrorAutoTicker(app: "MyApp") { model.mirrorSnapshot }
```

- `app` 슬러그는 파일명·관제 앱과 일치.
- 스냅샷은 가벼운 구조체 (Codable 또는 `[String: Any]` 계약은 앱별 문서).

## 표준 건강 필드 (함대 계약, 2026-08-23~)

모든 게시 앱의 `state` 는 다음 두 필드를 같은 규칙으로 갖는다 — 앱마다 제각각이면
"모든 앱에 감시"가 성립하지 않는다(사용자 지시: 모든 앱에 다 똑같이 깔려야 가치).

| 필드 | 계약 |
|------|------|
| `status` | `"ok" | "error"` — `lastError` 유무에서 파생. 파생은 `StateMirrorHealth.status(lastError:)` 로 통일 |
| `lastError` | `String?` — **nil 이면 키를 아예 생략** (빈 문자열 센티널 금지). 화면에 띄운 에러 문구의 원문(`String(describing:)`) |

- 에러를 화면에만 띄우고 미러에 안 싣는 것이 금지인 이유: 보고된 오류의 원문을
  소급할 수 없다(VW 키체인 -25293 사고, 2026-08-23).
- `app` 키는 **kebab slug** (`vaultwarden-client`). PascalCase 는 `swift-app-router state`
  CLI 가 파일을 못 찾는다(폴백이 없음).
- typed `State` Codable — 키 순서·추가 필드는 자유, 위 두 키의 의미만 계약이다.

## 최소 필드 권장

| 필드 | 의미 |
|------|------|
| 앱/화면 식별 | 어디를 보고 있는지 |
| 개수·상태 요약 | agents, panes, connected 등 |
| 최근 오류 | 한 줄 |
| updatedAt | 신선도 |

## 금지

- mirror 를 쓰기 API 로 쓰기 (소비 앱이 파일을 고쳐 상태를 바꾸기).
- 민감 원문을 mirror 에 넣기.

## 관련

- `docs/app-interop-contract.md` — 4면 계약
- CLI: `swift-app-router state <앱>` 등 관측 도구
