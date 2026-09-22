# LicenseKit

`LicenseKit`은 macOS 앱이 활성화 기록, 검증 주기, 오프라인 유예를 일관되게 관리하도록 하는 공용 SwiftKit 모듈이다. 라이선스 키와 활성화 ID는 `KeychainLicenseRecordStore`에만 저장한다.

**함대 기본 게이트는 이제 `GujoManaged` 다** (`swiftkit-appscaffold/Documentation/gujo-managed.md`). `RanodeApp` 스캐폴드는 `GujoManaged` trait 를 켠 앱에서 이쪽을 쓰고, 이 문서의 `LicenseKit`/`GujoStoreLicenseProvider` 는 trait 를 안 켰을 때의 폴백 경로로 남아 있다. 새 앱을 게이트할 때는 여기가 아니라 `gujo-managed.md` 부터 본다.

## Gujo Store 기기 라이선스

`GujoStoreLicenseProvider`는 Gujo Core의 RFC 8628 기기 승인과 product entitlement API를 사용한다.

- 앱은 `POST /api/cli/device/authorize`에 숫자 `product_id`를 보낸 뒤 브라우저 승인을 연다.
- 승인 뒤 받은 토큰은 해당 제품의 `products.read` 권한만 가지며, Keychain에만 저장한다.
- `GET /api/products/{id}/license`로 구매 권한을 확인하고, 다른 제품의 토큰은 확정 invalid 처리한다.
- `POST /api/products/{id}/license/device/revoke`는 현재 Mac의 제품 전용 키만 해제한다.
- 새 기능을 막을 때만 `LicenseEntitlementState.allowsLicensedFeatures`를 사용한다. 복원·내보내기처럼 고객 데이터를 회수하는 기능에는 사용하지 않는다.

출시 앱은 Info.plist 등에 Core API URL과 Store 상품의 `gujo_product_id`를 넣어야 한다. 판매자 API key, 결제 webhook secret, 결제 처리 코드는 네이티브 앱에 넣지 않는다.

## 제품 정책과 분리

이 모듈은 라이선스 상태만 제공한다. 어떤 기능을 유료로 막을지는 각 앱이 결정한다. 데이터 복구·내보내기·검증처럼 사용자의 기존 데이터를 안전하게 다루는 기능은 라이선스 상태와 무관하게 제공해야 한다.

`LicenseManager`는 다음 원칙을 고정한다.

- 확정된 무효·만료 응답은 즉시 로컬 기록을 제거한다.
- 네트워크·서버 일시 오류만 마지막 정상 검증 시점부터 제한된 유예 기간을 허용한다.
- 기기 해제 요청은 제공자가 확인한 뒤에만 로컬 기록을 삭제한다.

## Gujo Store 연동

판매 정본은 Gujo Software Store다. 이 모듈은 특정 외부 판매자에 의존하지 않으며, Gujo Store가 제공할 계정 기반 entitlement·기기 연결 API의 `LicenseProvider` 구현을 추가하는 위치다.

앱은 고객에게 일련번호를 요구하지 않고 Gujo 계정으로 기기를 연결해야 한다. 계정 로그인은 Core의 RFC 8628 device authorization 흐름을 재사용하고, Store의 결제 완료·환불 상태와 Core entitlement를 서버에서 연결한 뒤에만 앱이 검증한다.

판매자 관리자 비밀값, 결제 웹훅 비밀값, 사용자 계정 비밀번호는 앱에 넣지 않는다. 실제 제공자 구현은 다음 서버 계약이 먼저 확정된 뒤 추가한다.

- 구매 entitlement 조회와 상태(활성·환불·해지)
- 제품별 기기 활성화 한도와 기기 해제
- 짧은 권한 범위의 기기 토큰 발급·회수
- 앱이 검증할 제품 ID와 서명된 응답
