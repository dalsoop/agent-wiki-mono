import Foundation

/// business-api 클라이언트/동기화 에러. 봉투 실패({ok:false})·HTTP 상태·디코드·전송을
/// 한 축으로 모은다.
public enum BusinessCloudError: Error, Equatable, Sendable, CustomStringConvertible {
    /// 401 — Bearer 토큰 누락/잘못됨(서버 인증 게이트 통과 실패).
    case unauthorized
    /// 404 — 엔티티/엔드포인트 없음.
    case notFound
    /// 그 외 비-2xx HTTP 상태. 본문을 같이 실어 원인 추적을 돕는다.
    case http(Int, String)
    /// 봉투 디코드 실패(JSON 구조가 계약과 다름, 도메인 타입 디코드 불가).
    case decode(String)
    /// HTTPClientKit 전송 계층 오류(URLSession·네트워크).
    case transport(String)
    /// 서버가 봉투 failure 로 보고한 에러 메시지.
    case server(String)

    public var description: String {
        switch self {
        case .unauthorized:
            return "BusinessCloud unauthorized (Bearer 토큰 누락/잘못됨)"
        case .notFound:
            return "BusinessCloud not found"
        case .http(let code, let message):
            return "BusinessCloud HTTP \(code): \(message)"
        case .decode(let message):
            return "BusinessCloud decode 실패: \(message)"
        case .transport(let message):
            return "BusinessCloud 전송 오류: \(message)"
        case .server(let message):
            return "BusinessCloud 서버 에러: \(message)"
        }
    }
}
