# GujoManaged — 앱을 Cloud Apps 에 물리는 법

**최종 갱신: 2026-08-05 · v3 · 정본** — 변경 이력은 문서 맨 끝 참고.

**2026-09-21:** 라이선스 게이트는 퇴역했다. `.gujoManaged()` 와 `exitIfNotEntitled*` 는
항상 통과한다. Cloud Apps 는 **업데이트(Sparkle) 원장**만 맡는다.

앱마다 라이선스 키·활성화·오프라인 유예를 굴리지 않는다. 앱의 관심사는 셋뿐이다:
① Cloud Apps 가 깔려 있나 ② 연결됐나 ③ 지금 이 앱을 쓸 수 있나. 판정은 Cloud Apps 의
dual-entry CLI(`gujo-cloud-apps`)에 묻는다 — 원장이 거기 있고, 앱이 그걸 복제하면
정본이 둘이 된다.

## 채택 — 두 줄

`Package.swift` 에서 trait 를 켠다.

```swift
.package(path: "../../swiftkit-appscaffold", traits: ["GujoManaged"]),
```

**GUI** 루트 뷰 뒤에 한 줄:

```swift
ContentView(model: model)
    .gujoManaged()
```

**CLI**(dual-entry) 진입에 한 줄:

```swift
await GujoManaged.exitIfNotEntitled()
```

둘 다 해야 한다. `gujoManaged()` 는 `View` extension 이라 **창만** 막는다.
실측(2026-08-05) 관리되는 앱 130개 전부가 dual-entry CLI 를 갖고 있었고 그 CLI 는
원장에 묻지 않았다 — CLAUDE.md 가 "앱 고유 기능 제어는 소유 앱 CLI 우선" 이라고
못박은 바로 그 진입점이 게이트 밖이었다. 창만 막는 건 결제 게이트가 아니라 장식이다.

CLI 타깃은 `AppScaffoldKit` 의존을 추가한다(Foundation 전용 경로다 — AppKit 안 끌어온다).

## trait 만 켜고 호출을 빼먹으면

컴파일이 안 깨져서 **눈에 안 띈다**. 배선은 끌어오고 관리는 안 받는 상태가 되고,
겉보기엔 managed 인데 아니다. 실측 90개가 이 상태였다. 현황은:

```bash
gujo-managed-adoption-manager scan            # 함대 채택 현황
gujo-managed-adoption-manager show <앱디렉터리>  # 앱 하나의 판정 근거
```

## 판정 실패는 통과시킨다

못 물어본 것과 권한이 없는 것은 다르다. Cloud Apps 가 꺼져 있거나 오프라인이면
마지막으로 확인된 상태를 쓰고, 그것도 없으면 통과시킨다. 이걸 섞으면 비행기에서
산 앱이 안 열리고, CLI 는 자동화가 통째로 멈춘다. 결제 게이트의 엄격함은
Cloud Apps 쪽에서 지킨다.

`help` · `version` · `capabilities` 는 CLI 에서 항상 통과한다 — 계약 조회라
막으면 상호운용 레지스트리가 깨지고 무엇이 왜 막혔는지조차 못 읽는다.

## 채널별 권한 원장

**통합 API (권장 — 앱은 이것만 알면 된다):**

```swift
ContentView().entitlementManaged()
// Info.plist SwiftAppDistributionPrimary / EntitlementChannel 로 원장 선택
```

| 채널 | GUI 게이트 | 원장 | 상태 |
|---|---|---|---|
| **직판** (Mac Developer ID) | `.entitlementManaged()` / `.gujoManaged()` | Gujo Cloud Apps | 운영 |
| **App Store** (iOS / Mac) | `.entitlementManaged()` / `.appStoreManaged()` | StoreKit 2 | 운영 (상품 ID 없으면 fail-open) |
| **Google Play** | `.entitlementManaged()` / `.playBillingManaged()` | Play Billing | 스캐폴드 fail-open |
| **사설 스토어** | `.entitlementManaged()` / `.privateLicenseManaged()` | 서명 라이선스 | 스캐폴드 fail-open |

App Store 함대 GUI 는 `.entitlementManaged()` 로 통일한다 (agent-board 스파이크 → 전량 이전).
전용 `.appStoreManaged()` 는 하위 호환으로 남긴다.

**상품 카탈로그 · enforce · NicePay/TestFlight 사람 게이트** 정본:
`channel-entitlements.md` (같은 폴더).

- App Store: `AppStoreProductIDs` 는 카탈로그, 페이월은 `AppStoreEnforceEntitlement=true` 일 때만.
- Play: 구매 토큰 `PlayBillingManaged.recordPurchase` + enforce 플래그.
- 사설: `PrivateLicensePublicKey` + sl1 토큰 → `SignedLicenseCodec` 실검증.

관리 앱 `gujo-managed-adoption-manager` 가 채널→배선 갭을 스캔한다.

## iOS 앱 — GUI 에 `.gujoManaged()` 금지 (사고 2026-08-05)

`GujoManaged.status()` 는 **macOS 전용** 개념을 확인한다 — `/Applications/Gujo Cloud
Apps.app` 존재 여부, PATH 의 `gujo-cloud-apps` CLI. iPad 에는 이 둘 다 있을 수 없다.

`.gujoManaged()` 를 iOS 의 실제 화면에 걸면 상태가 항상 `cloudAppsMissing` 으로
떨어지고, "Gujo Cloud Apps 설치가 필요합니다" 대기 화면이 콘텐츠를 **영구히** 가린다
— 설치할 방법 자체가 없어서 앱이 완전히 막힌다(실측: pdf-editor-ios 등 7개 앱,
커밋 `40850f5db5`). 컴파일은 되고 테스트도 통과하므로 **빌드로는 못 잡는다.**

규칙:

- iOS GUI 에는 `.gujoManaged()` 를 **걸지 않는다**. App Store 채널은 **`.entitlementManaged()`**
  (또는 하위 호환 `.appStoreManaged()`).
- Info.plist: `SwiftAppDistributionChannels = appstore`, `AppStoreProductIDs = [...]`
  (상품 ID 비어 있으면 fail-open — 벽돌 방지).
- macOS + iOS 를 같이 선언한 앱이 진짜 macOS 창을 갖고 있으면(예:
  `proxmox-operations-manager-swift`) 그 창에만 `#if os(macOS)` 로 `.gujoManaged()` 를 건다.
- macOS 쪽이 `swift test` 호스트 컴파일용 형식적 스텁이면(iOS 전용 앱들 대부분)
  GUI 는 App Store 게이트, **CLI** 는 개발 머신용 `GujoManaged.exitIfNotEntitled()` 가능
  (`memo-vault-ios` CLI 전례).
- `@main enum ... { static func main() async { ... } }` 형태(top-level 문 불가)면
  CLI 게이트 호출을 `main()` 본문 **첫 줄**에 넣는다.

## 부트스트랩 면제 (결정 2026-08-05)

게이트를 걸면 순환이 생기는 앱만 면제한다. **둘뿐이다.**

| 앱 | 왜 |
|---|---|
| `gujo-cloud-apps` | 원장 소유자 — 자기를 막으면 아무도 판정을 못 받는다 |
| `app-build-manager` | Cloud Apps 를 **설치하는** 도구다 |

정본은 `GujoManaged.bootstrapExemptBundleIDs` 이고 테스트로 고정돼 있다.
"이것도 운영 도구" 라는 이유로 목록을 늘리면 경계가 물러지고, 그러면 구조적 의존이
이름만 남는다. 승인 매니저를 포함해 나머지는 전부 게이트한다.

## 테스트

이 코드는 `#if GujoManaged` 안에 있어서 **기본 `swift test` 로는 컴파일조차 안 된다.**
2026-08-05 이전에는 그래서 계약 테스트 3건이 조용히 안 돌고 있었다(5 tests/2 suites →
trait 켜면 8/3). 지금은 `scripts/ci-changed-package-tests.py` 가 trait 를 선언한
패키지를 **기본 구성과 전부 켠 구성 둘 다** 돌린다.

```bash
swift test                                   # trait off
swift test --traits GujoManaged              # trait on
```

## ship 우회 — `--skip-gujo-managed-gate`

`app-build-manager ship <앱> <채널>` 은 게이트 안 걸린 앱을 기본으로 막는다.
이 플래그는 그 차단을 **의도적으로** 뚫는 탈출구다.

정당한 경우: 앱이 진짜 macOS GUI 를 안 갖고 있어서(iOS 전용, 위 규칙대로 CLI 만
게이트) `ScaffoldAnalyzer` 가 오탐하는 임시 구간, 또는 마이그레이션 진행 중이라
후속 커밋이 이미 잡혀 있는 경우.

부당한 경우: 그냥 채택 작업이 귀찮아서 영구히 우회. **`container-manager-swift`
가 실제 사례다** — "로그인 벽" 이라는 근거 없는 이유로 이 플래그를 박아두고
반년 가까이 게이트를 안 걸었다(재검토 후 해소, 커밋 `bdbed756df`). 플래그가
있다고 해서 우회가 정당해지지 않는다 — 근거를 커밋 메시지에 남기고, 임시면
후속 이슈를 남긴다.

## 변경 이력

이 문서는 다른 소스 파일과 동일하게 git 으로만 버전 관리한다 — 별도 배포판·태그
없음. "버전"은 이 절의 항목 수다. 고칠 때 위 본문과 함께 이 절에 한 줄 추가한다.

| 버전 | 날짜 | 내용 | 커밋 |
|---|---|---|---|
| v1 | 2026-08-04 | 최초 작성 — 채택 두 줄, trait-only 함정, 판정 실패 fail-open, 부트스트랩 면제 | (통합 이력) |
| v2 | 2026-08-05 | GUI 만 막던 게이트를 CLI 까지 진짜 게이트로 확장 | `7d18d90a08` |
| v3 | 2026-08-05 | iOS GUI 브릭 사고 규칙 추가 · `--skip-gujo-managed-gate` 정당/부당 기준 추가 | `40850f5db5`, `bdbed756df` |
