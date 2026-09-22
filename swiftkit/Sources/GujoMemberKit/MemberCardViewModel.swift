import Foundation

/// 고객 카드 한 장 — 요약·기기·구독·최근 문의 슬롯.
/// SwiftUI 를 의존하지 않는 순수 뷰모델. 소비 앱이 이 값을 화면에 올린다.
public struct MemberCardViewModel: Sendable, Equatable, Hashable, Identifiable, Codable {
    public var member: Member
    public var devices: [MemberDevice]
    public var subscription: MemberSubscriptionSummary?
    public var recentInquiry: MemberRecentInquiry?

    public init(
        member: Member,
        devices: [MemberDevice] = [],
        subscription: MemberSubscriptionSummary? = nil,
        recentInquiry: MemberRecentInquiry? = nil
    ) {
        self.member = member
        self.devices = devices
        self.subscription = subscription
        self.recentInquiry = recentInquiry
    }

    public var id: String { member.id }

    public var activeDeviceCount: Int {
        devices.filter(\.active).count
    }

    public var lastSeenAt: Date? {
        devices.compactMap(\.lastUsedAt).max()
    }

    public var subscriptionLine: String {
        guard let subscription else { return "none" }
        if let product = subscription.productName, !product.isEmpty {
            return "\(subscription.status) · \(product)"
        }
        return subscription.status
    }

    public var deviceLine: String {
        "\(activeDeviceCount)/\(devices.count)"
    }

    public var inquiryLine: String? {
        guard let recentInquiry else { return nil }
        let subject = recentInquiry.subject.isEmpty ? "#\(recentInquiry.id)" : recentInquiry.subject
        return "[\(recentInquiry.status)] \(subject)"
    }

    /// 보존기간이 지난 카드는 이메일·이름을 마스킹한다. 원본 `member` 는 바꾸지 않는다.
    public func redacted(policy: PIIRetentionPolicy, now: Date = Date()) -> MemberCardViewModel {
        guard let createdAt = member.createdAt, policy.isExpired(createdAt: createdAt, now: now) else {
            return self
        }
        var copy = self
        copy.member.name = policy.maskName(member.name)
        copy.member.email = policy.maskEmail(member.email)
        return copy
    }
}
