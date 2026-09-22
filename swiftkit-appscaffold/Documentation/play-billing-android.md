# Play Billing — Android 연동 메모

Swift 원장: `PlayBillingManaged` (`swiftkit-appscaffold`).

## Gradle

```gradle
dependencies {
    implementation("com.android.billingclient:billing-ktx:7.1.1")
}
```

## 흐름

1. `BillingClient` 연결 · `queryProductDetailsAsync`
2. `launchBillingFlow`
3. `PurchasesUpdatedListener` 에서 성공 시
   - 서버 검증(권장) 또는
   - 로컬 브리지: `PlayBillingManaged.recordPurchase(productID, purchaseToken)`
4. 앱 Info.plist:
   - `SwiftAppDistributionPrimary` = `play`
   - `PlayBillingProductIDs` = SKU 목록
   - 판매 빌드에서만 `PlayBillingEnforceEntitlement` = true

## 테스트

```bash
# macOS 단위: 토큰 스토어
# GUJO_ENFORCE_PLAY=1 로 페이월 강제
```

mono 에 순수 Android 앱 바이너리가 생기기 전에도 Swift 원장·스캔 시그니처는 고정한다.
