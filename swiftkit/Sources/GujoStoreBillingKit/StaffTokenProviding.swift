import Foundation

/// Staff Bearer 토큰 공급. 발급(GujoAuthKit)은 이 모듈 밖이다.
///
/// 기본 구현은 Keychain `net.ranode.gujo` / `staff` **읽기만** 한다.
/// 환경변수·UserDefaults·평문 파일은 이 프로토콜의 정본 경로가 아니다.
public protocol StaffTokenProviding: Sendable {
    func staffToken() throws -> String?
}

/// 테스트·스텁 주입용. 파일이나 Keychain 을 열지 않는다.
public struct StaticStaffTokenProvider: StaffTokenProviding {
    public let token: String?

    public init(token: String?) {
        self.token = token
    }

    public func staffToken() throws -> String? { token }
}
