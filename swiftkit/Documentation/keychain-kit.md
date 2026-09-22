# KeychainKit

`KeychainKit`은 macOS/iOS 앱이 Keychain generic-password 항목을 **캐시와 함께** 읽고 쓰는 공용 모듈이다.
라이선스·계정·토큰 저장의 기본 저장소다. 앱이 `SecItem*` 를 직접 부르지 말고 여기를 쓴다.

## 원칙

1. **서비스 칸을 아끼라.** 함대 공용 비밀(예: 라이선스 지갑)은 **서비스 1개**에 모은다.
   `LicenseCacheKit.LicenseKeyVault` (및 구 `LocalLicenseWallet`) →
   `LicenseKeyVault.keychainService` / `entries-v1` 한 칸. 서비스 문자열은 사용자 키체인 계약이라 바꾸지 않는다.
2. **앱별 기록은 그 앱이 쓴다.** 다른 바이너리(CLI·다른 앱)가 `net.ranode.<app>` 에
   `primary-license` 를 대량으로 심으면 macOS ACL 이 **바이너리마다 승인 프롬프트**를 띄운다.
   (실측: 26앱 plant → 비밀번호 반복 입력.)
3. **읽기 타임아웃 오탐을 “없음”으로 캐시하지 않는다.** 타임아웃과 빈 값을 구분한다.
4. **헤드리스**에서는 `interactionNotAllowed` 로 UI 프롬프트를 막되, 구형 ACL 항목은
   SecurityAgent 에서 멈출 수 있다. 그때는 `/usr/bin/security` 를 **외부 프로세스+타임아웃**으로
   격리하는 패턴을 쓴다(`ClaudeRuntimeKit` 참고). 앱 프로세스 안에서 무기한 대기 금지.

## API

- `CachedKeychainStore(service:readTimeout:)`
  - `readTimeout <= 0`: 호출 스레드에서 동기 `SecItemCopyMatching` (지갑 등 정확도 우선).
  - `readTimeout > 0`: 전용 직렬 큐에서 조회 후 상한. 타임아웃 시 `lastReadTimedOut == true`,
    **없음으로 캐시하지 않음**.
- `data` / `string` / `set` / `setData` / `delete` / `invalidate`

## 금지

- 외부 도구가 함대 앱 Keychain 서비스를 루프 돌며 쓰기 (비밀번호 폭주).
- 타임아웃 시 `reset-corrupt` 로 지갑 통째 삭제 (오탐 시 키 전량 유실). 강제 삭제 전 백업·재시도.

## 관련

- `LicenseCacheKit` / `LicenseKeyVault` — Cloud Apps 기기 탭이 소비하는 지갑 1칸 정책
- `LicenseKit` / `LocalLicenseWallet` — 같은 Keychain 칸을 가리키는 구 API
- `docs/app-interop-contract.md` — secret 원문 출력 금지
- `CredentialLifecycleKit` — ACL 프롬프트 없는 스캔(helper 경유)
