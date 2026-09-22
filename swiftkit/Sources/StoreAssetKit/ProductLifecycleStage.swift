import Foundation

/// 상품 생애주기 및 운영 단계 (Stage / Status)
/// 네이버 스마트스토어 및 오프라인 매장 전주기 관리 추상화
public enum ProductLifecycleStage: String, Codable, CaseIterable, Sendable {
    /// 등록준비 (상품 기획 / 미출시 / 검토 단계)
    case draft = "draft"
    /// 판매중 (매장 진열 & 온라인 노출 & POS 결제 가능)
    case onSale = "on_sale"
    /// 예약중 (고객 예약 / 계좌입금 대기 / 현장 홀드)
    case reserved = "reserved"
    /// 판매완료 (팔림 / 재고 소진 / 품절)
    case soldOut = "sold_out"
    /// 처분됨 (파손, 유통기한 경과, 샘플 전환, 폐기 등 매장 감모 처리)
    case disposed = "disposed"
    /// 반품검수 (고객 반품 후 검수/재포장 대기)
    case returned = "returned"
    /// 보관종료 (시즌 종료 / 단종 / 영구 보관)
    case archived = "archived"

    /// 한국어 표시명
    public var titleKo: String {
        switch self {
        case .draft: return "등록준비"
        case .onSale: return "판매중"
        case .reserved: return "예약중"
        case .soldOut: return "팔림(품절)"
        case .disposed: return "처분됨(폐기)"
        case .returned: return "반품검수"
        case .archived: return "보관종료"
        }
    }

    /// 영문 표시명
    public var titleEn: String {
        switch self {
        case .draft: return "Draft"
        case .onSale: return "On Sale"
        case .reserved: return "Reserved"
        case .soldOut: return "Sold Out"
        case .disposed: return "Disposed"
        case .returned: return "Returned"
        case .archived: return "Archived"
        }
    }

    /// 즉시 결제 및 판매 가능 여부
    public var isSalable: Bool {
        self == .onSale
    }

    /// 온라인/스마트스토어 활성 노출 여부
    public var isOnlineActive: Bool {
        self == .onSale
    }

    /// 처분/폐기 상태 여부
    public var isDisposed: Bool {
        self == .disposed
    }

    /// SF Symbol 아이콘 이름
    public var symbolName: String {
        switch self {
        case .draft: return "square.and.pencil"
        case .onSale: return "checkmark.seal.fill"
        case .reserved: return "clock.badge.checkmark"
        case .soldOut: return "cart.fill.badge.minus"
        case .disposed: return "trash.fill"
        case .returned: return "arrow.uturn.backward.circle.fill"
        case .archived: return "archivebox.fill"
        }
    }

    /// 현재 단계에서 이동 가능한 유효한 다음 단계 목록
    public var availableTransitions: [ProductLifecycleStage] {
        switch self {
        case .draft:
            return [.onSale, .archived]
        case .onSale:
            return [.reserved, .soldOut, .disposed, .archived]
        case .reserved:
            return [.onSale, .soldOut, .disposed]
        case .soldOut:
            return [.onSale, .returned, .disposed, .archived]
        case .disposed:
            return [.archived]
        case .returned:
            return [.onSale, .disposed, .archived]
        case .archived:
            return [.draft, .onSale]
        }
    }

    /// 특정 단계로 전이 가능한지 검증
    public func canTransition(to target: ProductLifecycleStage) -> Bool {
        availableTransitions.contains(target)
    }
}

/// 처분 / 폐기 상세 사유
public enum DisposalReason: String, Codable, CaseIterable, Sendable {
    case damaged = "파손/불량"
    case expired = "유통기한 만료"
    case lost = "분실/도난"
    case sample = "매장 시연/샘플 전환"
    case donation = "기부/증정"
    case clearance = "원가 이하 땡처리 처분"
    case other = "기타 처분 사유"
}

/// 처분 / 폐기 상세 기록
public struct ProductDisposalRecord: Codable, Sendable, Equatable {
    public var reason: DisposalReason
    public var quantity: Int
    public var lossAmount: Double
    public var note: String
    public var disposedAt: Date

    public init(
        reason: DisposalReason = .damaged,
        quantity: Int = 1,
        lossAmount: Double = 0.0,
        note: String = "",
        disposedAt: Date = Date()
    ) {
        self.reason = reason
        self.quantity = quantity
        self.lossAmount = lossAmount
        self.note = note
        self.disposedAt = disposedAt
    }
}

/// 단계 전이 이력 엔트리
public struct StageTransitionEntry: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var fromStage: ProductLifecycleStage
    public var toStage: ProductLifecycleStage
    public var timestamp: Date
    public var note: String

    public init(
        id: String = UUID().uuidString,
        fromStage: ProductLifecycleStage,
        toStage: ProductLifecycleStage,
        timestamp: Date = Date(),
        note: String = ""
    ) {
        self.id = id
        self.fromStage = fromStage
        self.toStage = toStage
        self.timestamp = timestamp
        self.note = note
    }
}
