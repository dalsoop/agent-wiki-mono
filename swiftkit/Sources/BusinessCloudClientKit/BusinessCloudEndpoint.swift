import Foundation

/// business-api 가 노출하는 7개 엔티티. 경로는 App.swift 의
/// `registerSimpleEntity(path:)` · `registerTransactions` · `/sync/changes?entities=`
/// 에서 쓰는 서버 경로 토큰과 1:1 이다.
///
/// **경로 정확값은 `apps/business-api-swift/Sources/BusinessAPI/App.swift` 에서 실측**:
/// `/accounts` · `/cards` · `/subscriptions` · `/businesses` · `/import_batches`
/// (언더스코어 — registerSimpleEntity 호출이 저 경로로 등록한다) · `/attachments` ·
/// `/transactions`(registerTransactions).
public enum BusinessCloudEntity: String, Sendable, CaseIterable {
    case accounts
    case cards
    case subscriptions
    case transactions
    case businesses
    /// Swift enum case 는 camelCase 규칙을 따르되, 서버 경로·/sync/changes CSV 키는
    /// snake_case 임을 path/csvKey 가 보정한다.
    case importBatches
    case attachments

    /// 컬렉션 라우트 경로(앞 `/` 포함). App.swift registerSimpleEntity(path:)/registerTransactions
    /// 에 넘긴 인자 그대로.
    public var path: String {
        switch self {
        case .accounts: return "/accounts"
        case .cards: return "/cards"
        case .subscriptions: return "/subscriptions"
        case .transactions: return "/transactions"
        case .businesses: return "/businesses"
        case .importBatches: return "/import_batches"
        case .attachments: return "/attachments"
        }
    }

    /// `/sync/changes?entities=<csv>` 에 넣을 키(path 에서 앞 `/` 만 뺀 값).
    /// import_batches 만 snake 임을 보정한다.
    public var csvKey: String {
        String(path.dropFirst())
    }
}
