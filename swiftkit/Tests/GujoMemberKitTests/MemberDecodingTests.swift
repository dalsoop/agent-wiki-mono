import Foundation
import Testing
@testable import GujoMemberKit

@Test("commerce/staff/customers 목록 — Int·String id 와 admin 태그를 정규화한다")
func decodeCommerceStaffCustomers() throws {
    let data = try fixture("commerce-staff-customers")
    let envelope = try MemberJSON.decoder().decode(StaffCustomerListEnvelope.self, from: data)
    #expect(envelope.data.count == 2)
    #expect(envelope.meta?.count == 2)
    #expect(envelope.meta?.nextCursor == nil)

    let ada = envelope.data[0]
    #expect(ada.id == "7")
    #expect(ada.email == "ada@example.com")
    #expect(ada.name == "Ada Lovelace")
    #expect(ada.locale == "ko")
    #expect(ada.tags == ["vip"])
    #expect(ada.createdAt != nil)

    let bob = envelope.data[1]
    #expect(bob.id == "8")
    #expect(bob.tags == ["admin"])
    #expect(bob.name.isEmpty)
    #expect(bob.displayName == "bob@example.com")
}

@Test("commerce/staff/customers 상세 — 기기·구독으로 고객 카드를 조립한다")
func decodeCommerceStaffCustomerDetailIntoCard() throws {
    let data = try fixture("commerce-staff-customer-detail")
    let payload = try MemberJSON.decoder().decode(CustomerDetailFixture.self, from: data)
    #expect(payload.data.id == "7")
    #expect(payload.devices.data.count == 2)

    let subscription = try #require(payload.data.subscriptions.first)
    let card = MemberCardViewModel(
        member: payload.data.member,
        devices: payload.devices.data,
        subscription: subscription
    )
    #expect(card.activeDeviceCount == 1)
    #expect(card.deviceLine == "1/2")
    #expect(card.subscriptionLine == "active · Tool")
    #expect(card.lastSeenAt == payload.devices.data[1].lastUsedAt)
}

@Test("support/staff 문의 — user_id 로 회원을 만들고 최근 문의 슬롯을 채운다")
func decodeSupportStaffInquiriesIntoCard() throws {
    let data = try fixture("support-staff-inquiries")
    let envelope = try MemberJSON.decoder().decode(StaffInquiryListEnvelope.self, from: data)
    let record = try #require(envelope.data.first)
    #expect(record.userId == "9")
    #expect(record.userEmail == "ada@example.com")
    #expect(record.inquiry.id == "42")
    #expect(record.inquiry.preview == "카드 거절")

    let card = MemberCardViewModel(
        member: record.member,
        recentInquiry: record.inquiry
    )
    #expect(card.member.id == "9")
    #expect(card.member.email == "ada@example.com")
    #expect(card.inquiryLine == "[open] 결제 실패")
}

private func fixture(_ name: String) throws -> Data {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures", isDirectory: true)
        .appendingPathComponent("\(name).json")
    return try Data(contentsOf: url)
}

/// 상세 픽스처 전용 — 킷 공개 API 가 아닌 테스트 봉투.
private struct CustomerDetailFixture: Decodable {
    var data: Detail
    var devices: StaffDeviceListEnvelope

    struct Detail: Decodable {
        var id: String
        var email: String
        var name: String?
        var locale: String?
        var createdAt: Date?
        var subscriptions: [MemberSubscriptionSummary]
        var isAdmin: Bool?

        enum CodingKeys: String, CodingKey {
            case id, email, name, locale, subscriptions
            case createdAt = "created_at"
            case isAdmin = "is_admin"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try MemberJSON.decodeIdentifier(container, key: CodingKeys.id)
            email = try container.decode(String.self, forKey: .email)
            name = try container.decodeIfPresent(String.self, forKey: .name)
            locale = try container.decodeIfPresent(String.self, forKey: .locale)
            createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
            subscriptions = try container.decodeIfPresent([MemberSubscriptionSummary].self, forKey: .subscriptions) ?? []
            isAdmin = try container.decodeIfPresent(Bool.self, forKey: .isAdmin)
        }

        var member: Member {
            var tags: [String] = []
            if isAdmin == true { tags.append("admin") }
            return Member(
                id: id,
                name: name ?? "",
                email: email,
                locale: locale,
                createdAt: createdAt,
                tags: tags
            )
        }
    }
}
