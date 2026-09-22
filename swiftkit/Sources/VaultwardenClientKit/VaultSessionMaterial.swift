import Foundation

/// dual-entry 세션 이관 페이로드 (GUI 메모리 → CLI 프로세스).
/// 로그·디스크에 쓰지 말 것. 소켓 1회 전송 전용.
public struct VaultSessionMaterial: Sendable, Equatable {
    public var userKeyRaw: Data
    public var accessToken: String?
    public var refreshToken: String?
    public var endpoint: ServerEndpoint
    public var email: String
    public var kdf: Int
    public var iterations: Int

    public init(
        userKeyRaw: Data,
        accessToken: String?,
        refreshToken: String?,
        endpoint: ServerEndpoint,
        email: String,
        kdf: Int,
        iterations: Int
    ) {
        self.userKeyRaw = userKeyRaw
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.endpoint = endpoint
        self.email = email
        self.kdf = kdf
        self.iterations = iterations
    }
}
