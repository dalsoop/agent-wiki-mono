# 채널별 권한 · 상품 카탈로그 · 사람 게이트

**최종 갱신: 2026-08-07**

> **따라하기 온보딩 (사람이 읽을 진입점)**  
> - GUI: GujoManagedAdoptionManager 첫 실행 / 설정 → 사람 할 일 안내 다시 보기  
> - CLI: `gujo-managed-adoption-manager guide`  
> - 앱 문서: `apps/gujo-managed-adoption-manager-swift/docs/HUMAN-ONBOARDING.md`  
> 정본 단계 배열: `HumanOnboardingPlaybook`

앱 GUI 는 `.entitlementManaged()` 한 줄. 원장은 채널이 고른다.

| 채널 | 원장 | enforce 키 | 기본 |
|---|---|---|---|
| direct | GujoManaged (Cloud Apps) | (항상 판정) | 운영 |
| appstore | AppStoreManaged (StoreKit 2) | `AppStoreEnforceEntitlement` / `GUJO_ENFORCE_STOREKIT=1` | **카탈로그만** (enforce false) |
| play | PlayBillingManaged | `PlayBillingEnforceEntitlement` / `GUJO_ENFORCE_PLAY=1` | 카탈로그 + 토큰 스토어 |
| private | PrivateLicenseManaged | 공개키 존재 시 자동 강제 | 공개키 없으면 fail-open |

## App Store 상품 ID

함대 관례:

```text
{CFBundleIdentifier}.pro          # 비소모 잠금해제 (기본)
{CFBundleIdentifier}.subscription # 구독(선택)
```

Info.plist:

```xml
<key>AppStoreProductIDs</key>
<array>
  <string>net.ranode.example.pro</string>
</array>
<!-- 페이월은 상품을 App Store Connect 에 만들고 샌드박스 검증 후 true -->
<key>AppStoreEnforceEntitlement</key>
<false/>
```

**절대 금지:** enforce true + Connect 에 없는 상품 ID → 전 사용자 벽돌.

### 샌드박스 E2E (사람)

1. App Store Connect → 앱 → 구독/비소모 상품 생성 (위 ID 와 **문자열 일치**)
2. StoreKit Configuration 파일 또는 샌드박스 테스터
3. 로컬: `GUJO_ENFORCE_STOREKIT=1` 로 페이월 강제 후 구매 흐름
4. 통과 후 plist `AppStoreEnforceEntitlement` = true 로 승격 · ship

## Google Play

Android 모듈 (아직 mono 에 앱 바이너리 없음 — 스캐폴드 계약):

```gradle
implementation("com.android.billingclient:billing-ktx:7.1.1")
```

구매 성공 시:

```swift
PlayBillingManaged.recordPurchase(productID: sku, token: purchaseToken)
```

`PlayBillingEnforceEntitlement=true` 이면 기록된 토큰만 통과.

## 사설 서명 라이선스

발급 (운영 머신, secret 은 vault):

```swift
let sk = SignedLicenseCodec.generatePrivateKey()
let pk = try SignedLicenseCodec.publicKey(privateKey: sk)
let token = try SignedLicenseCodec.issue(claims, privateKey: sk)
// token → 고객 / license.sl1
// pk → Info.plist PrivateLicensePublicKey
```

앱:

```xml
<key>PrivateLicensePublicKey</key>
<string>…base64url…</string>
<key>PrivateLicenseProductID</key>
<string>net.ranode.example</string>
```

토큰: env `GUJO_SIGNED_LICENSE` 또는 `~/Library/Application Support/<bundleId>/license.sl1`.

## 사람 게이트 — NicePay (직판)

에이전트가 끝낼 수 없음. 체크리스트:

1. [ ] NicePay 가맹 승인 · MID / Key 발급
2. [ ] Infisical/vault 에 `nicepay` 항목 (채팅·위키 원문 금지)
3. [ ] `apps.gujo.ai` / subscription 결제 경로에 게이트웨이 연결
4. [ ] agent-browser 로 샌드박스 카드 그리드 E2E (이미 PaymentBrowserProfile 지원)
5. [ ] 실카드 1회 스모크 · 영수증 · 웹훅 원장 확인

관련 앱: `agent-browser` (NicePay iframe/postMessage), `pg-merchant-ops`.

## 사람 게이트 — TestFlight

1. [ ] Apple Developer · App Store Connect 앱 레코드
2. [ ] Distribution 인증서 · App Store 프로비저닝
3. [ ] `xcodebuild -exportArchive` / Transporter / `altool` 업로드
4. [ ] 내부 테스터 그룹 · 초대
5. [ ] 샌드박스 StoreKit + enforce true 빌드 검증

iOS 함대 ship 은 프로파일 사람 발급 전까지 **시뮬/디바이스 개발 서명** 만.

## 스캔

```bash
gujo-managed-adoption-manager scan
# 권한 미배선 0 · 채널 미선언 0 유지
```
