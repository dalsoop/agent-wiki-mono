# GujoAuthKit · GujoStaffAPIKit — Gujo 스태프 인증 계약 v1

두 킷은 gujo.ai 스태프 인증(계약 §1·§2·§4)과 스태프 API(§5)의 **유일한 Swift 이행체**다.
앱은 토큰·호스트·ability 이름을 직접 다루지 않고 이 킷만 쓴다.

## 규칙 요약

| 축 | 정본 |
|---|---|
| 호스트 | EndpointRouterKit `gujo-core` 키(`EndpointRouter.gujoCore`). 앱은 하드코딩 금지, `GUJO_ENDPOINT_GUJO_CORE` env 로 재지정 |
| 스태프 세션 | Keychain service `net.ranode.gujo` · account `staff` (토큰·abilities·expires_at JSON) |
| 구매자 세션 | 같은 service · account `buyer` |
| 러너·CI 폴백 | agent-vault 카드 `tenant:gujo` 필드 `staff-token` — Keychain 이 비었을 때만, GUI 는 항상 device-code 우선 |
| env | **읽지 않는다.** `GUJO_STAFF_TOKEN`·`GUJO_OPS_TOKEN`·`GUJO_INTAKE_TOKEN`·`GUJO_SKILL_STORE_TOKEN` 은 `importLegacy()` 일회성 이관에서만 본다 |
| 사용자 프롬프트 | `user_code`·`verification_uri` 는 `present` 훅으로 앱에 전달. 킷은 터미널에 출력하지 않는다 |

## GujoAuthKit

```swift
import GujoAuthKit

// 로그인 — 앱이 user_code·URL 을 앱 안 표준 프롬프트에 띄운다
let session = try await GujoAuth.staff.login(client: "gujo-commerce-desk") { prompt in
    await MainActor.run { model.deviceCodePrompt = prompt }   // userCode · verificationURI · expiresAt
}

let current = try await GujoAuth.staff.current()             // Keychain → agent-vault 폴백
try await GujoAuth.staff.require(.ordersRefund)              // 없으면 .missingAbility(.ordersRefund)
await GujoAuth.staff.logout()                                // 로컬 삭제 + POST /api/staff/logout(204)
let report = await GujoAuth.staff.importLegacy()             // env/파일 → Keychain, 삭제 안내 반환
```

- 서버 경로: `POST /api/staff/device/authorize` → `POST /api/staff/device/token` 폴링
  (200 승인 · 428 대기 · 429 slow_down · 410 expired_token · 403 access_denied), `GET /api/staff/me`, `POST /api/staff/logout`.
- `StaffAbility` 는 서버 ability 이름과 1:1(PascalCase 30개). 새 ability 는 서버·킷을 같은 MR 에서 올린다.
- `GujoAuthError.missingAbility` 의 설명문은 ability 이름을 포함한다 — 앱 오류 표면이 그대로 보여준다.
- 구매자 흐름(`/api/cli/device/*`)은 `GujoAuth.buyer` 로 같은 모양이다.
- `importLegacy()` 는 `gst_` 토큰만 `/api/staff/me` 로 검증해 받아들이고, 옛 토큰(`ops`·`intake`·`skill-store`)은
  `unsupported` 로 보고한다. 파일은 **삭제하지 않고** `filesToDelete`·`guidance` 로 사용자에게 안내한다.

### 테스트 주입

`GujoStaffAuth(http:store:fallback:baseURL:sleep:now:)` — `HTTPClient` 스텁 · `InMemorySessionStore` ·
`StaticStaffTokenFallback`/`NoStaffTokenFallback` · no-op sleep · 고정 시계로 오프라인 테스트한다.

## GujoStaffAPIKit

```swift
import GujoStaffAPIKit

let api = GujoStaffAPI.shared                       // GujoAuth.staff 세션을 쓴다
let page = try await api.commerce.customers.index(search: "kim", page: 1)
let order = try await api.commerce.orders.refund(77, RefundRequest(amount: 12000, reason: "duplicate"))
try await api.support.inquiries.close(5)
let packages = try await api.ops.packages.list()
try await api.intake.storeReleasesIntake(ReleaseIntake(slug: "s", version: "1.0.0", sha256: "…"))
try await api.skills.publish(SkillPublish(slug: "my-skill", version: "2.0.0", manifest: manifest))
```

- 네임스페이스: `commerce`(customers·products·orders·subscriptions·events) · `support`(inquiries·reports) ·
  `ops`(health·packages·devices·installJobs·runners·receiptsIngest·audit) · `intake`(store·lecture) ·
  `skills`(publish·delete·deprecate).
- 라우트 정본은 `GujoStaffRoutes` 한 곳(`/api/commerce/staff`, `/api/support/staff`, `/ops/v1`,
  `/store/releases/intake`, `/lecture/releases/intake`, `/api/skills`).
- 각 호출은 요구 ability 를 **먼저 로컬 검사**(`GujoAuthError.missingAbility`)하고, 서버 403 은
  `GujoStaffAPIError.forbidden(required:serverAbility:path:)` 로 — `missingAbilityName` 이 항상 채워진다.
- 상태 매핑: 401 `unauthorized` · 404 `notFound` · 400/409/422 `validation` · 5xx `server` · 204 `Empty`.
- 응답 봉투: Laravel `{data:[…], meta:{…}}` 와 맨몸 배열/객체 모두 `Page`/`Single` 로 받는다.

## 보안 경계

- 토큰은 Keychain 과 agent-vault 카드에만 산다. 로그·오류 메시지에 토큰을 싣지 않는다.
- 폴백(agent-vault) 세션은 Keychain 에 저장하지 않는다 — 카드가 정본이다.
- 라이브러리는 실서버를 테스트에서 치지 않는다. 모든 테스트는 인메모리 스텁이다.
