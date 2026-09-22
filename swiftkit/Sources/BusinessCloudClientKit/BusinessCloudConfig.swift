import Foundation

// Phase 2 — Chunk B: business-api 전용 동기화 클라이언트 킷.
// 이 킷은 **business-api-swift 서버 계약에 고정**돼 있다. 서버 무관 generic 동기화 엔진이
// 아니라 — 엔드포인트·봉투·content_hash·커서·테넌트 헤더 전부 이 킷 안에 자체완결한다.
// generic 추상은 HTTPClientKit(원시 전송) 과 LocalSyncStore(로컬 저장소 adapter) 만이다.

/// business-api 런타임 접속 구성. baseURL/토큰/timeout.
///
/// 토큰은 테넌트 자격(앱 측에서 gujo 계정 → BUSINESS_API_TOKEN 해석). 이 킷은 전달받은
/// 토큰을 `Authorization: Bearer <token>` 로 매 요청(인증 면제 엔드포인트 제외)에 붙인다.
///
/// 파일럿 기본값은 내부/터널 주소를 상정한 placeholder. 앱이 init 시점에 실제 baseURL/토큰을
/// 채운다.
public struct BusinessCloudConfig: Sendable, Equatable {
    public let baseURL: URL
    public let token: String
    public let timeout: TimeInterval

    public init(baseURL: URL, token: String, timeout: TimeInterval = 30) {
        self.baseURL = baseURL
        self.token = token
        self.timeout = timeout
    }
}
