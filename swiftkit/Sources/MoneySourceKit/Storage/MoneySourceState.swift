import Foundation
import StateMirrorKit

/// 돈 유입원(Money Source) 패밀리 앱의 StateMirror 표준 스키마.
public struct MoneySourceAppState: Codable, Sendable {
    public var status: String
    public var generatedAt: Date
    public var totalLoaded: Int      // 로드된 전체 공고/상품 수
    public var matchedCount: Int     // "내 상태" 매칭(접수중) 수
    public var usedSample: Bool      // API 키 없음/실패로 샘플 표시 중
    public var profileSummary: String // "소상공인 · 서울 · 금융"
    public var note: String?         // 폴백 사유 등 안내

    public init(
        status: String = "ok",
        generatedAt: Date = Date(),
        totalLoaded: Int = 0,
        matchedCount: Int = 0,
        usedSample: Bool = false,
        profileSummary: String = "",
        note: String? = nil
    ) {
        self.status = status
        self.generatedAt = generatedAt
        self.totalLoaded = totalLoaded
        self.matchedCount = matchedCount
        self.usedSample = usedSample
        self.profileSummary = profileSummary
        self.note = note
    }
}

public enum MoneySourceStateMirror {
    public static func publish(app: String, state: MoneySourceAppState) {
        StateMirror.publish(app: app, state)
    }
}
