import Foundation

/// Gujo 인증 진입점(계약 §4).
///
/// ```swift
/// let session = try await GujoAuth.staff.login(client: "gujo-commerce-desk") { prompt in
///     await showDeviceCodeSheet(prompt.userCode, prompt.verificationURI)   // 앱 안 표준 프롬프트
/// }
/// try await GujoAuth.staff.require(.ordersRefund)
/// ```
///
/// 기본 인스턴스는 macOS Keychain + agent-vault 폴백 + EndpointRouterKit `gujo-core` 다.
/// Linux Cloud Apps 는 별도 패키지이며 파일 세션(`FileSessionStore`)을 쓴다. iOS 클라이언트가 아니다.
/// 테스트·특수 환경은 `GujoStaffAuth(http:store:fallback:baseURL:)` 로 직접 만든다.
public enum GujoAuth {
    public static let staff = GujoStaffAuth()
    public static let buyer = GujoBuyerAuth()
}
