import Foundation

/// GujoAuthKit 오류. 토큰 원문은 어떤 케이스에도 싣지 않는다.
public enum GujoAuthError: Error, Equatable, Sendable, LocalizedError {
    /// 로그인된 스태프 세션이 없다(Keychain 비어 있고 agent-vault 폴백도 없음).
    case notLoggedIn
    /// 세션은 있으나 만료됐다.
    case sessionExpired(expiresAt: Date)
    /// 필요한 ability 가 세션에 없다. 이름이 그대로 실린다.
    case missingAbility(StaffAbility)
    /// 서버 410 `expired_token` — device code 가 만료됐다.
    case deviceCodeExpired
    /// 서버 403 `access_denied` — 스태프가 아니거나 거부됐다.
    case accessDenied
    /// EndpointRouterKit 에 호스트 키가 없다(원장·폴백 모두 비어 있음).
    case endpointMissing(key: String)
    /// 응답 JSON 이 계약과 다르다.
    case malformedResponse(String)
    /// 계약에 없는 HTTP 상태.
    case unexpectedStatus(Int, error: String?)
    /// 전송 계층 실패(네트워크 등). 원문은 진단용 메시지만.
    case transport(String)
    /// 로그인 폴링이 취소됐다.
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            return "Gujo 스태프 로그인이 필요합니다."
        case .sessionExpired(let at):
            return "Gujo 스태프 세션이 만료됐습니다(\(ISO8601DateFormatter().string(from: at))). 다시 로그인하세요."
        case .missingAbility(let ability):
            return "이 작업에는 스태프 권한 '\(ability.rawValue)' 이(가) 필요합니다."
        case .deviceCodeExpired:
            return "기기 승인 코드가 만료됐습니다. 로그인을 다시 시작하세요."
        case .accessDenied:
            return "스태프 승인이 거부됐습니다(스태프 계정이 아니거나 거부됨)."
        case .endpointMissing(let key):
            return "EndpointRouterKit 키 '\(key)' 가 비어 있습니다. app-build-manager endpoints 원장을 확인하세요."
        case .malformedResponse(let detail):
            return "Gujo 서버 응답이 계약과 다릅니다: \(detail)"
        case .unexpectedStatus(let status, let error):
            return "Gujo 서버가 예상 밖 상태를 돌려줬습니다(HTTP \(status)\(error.map { ", \($0)" } ?? ""))."
        case .transport(let detail):
            return "Gujo 서버에 연결할 수 없습니다: \(detail)"
        case .cancelled:
            return "로그인이 취소됐습니다."
        }
    }
}
