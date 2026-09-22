import Foundation
import Testing
@testable import GujoMemberKit

@Test("기본 보존기간은 메일러와 같은 1095일이다")
func defaultRetentionIsLegalThreeYears() {
    let policy = PIIRetentionPolicy.legalDefault
    #expect(policy.retentionDays == 1095)
    #expect(PIIRetentionPolicy.legalRetentionDays == 1095)
}

@Test("만료 판정 — 경계일은 만료로 본다")
func expirationBoundary() {
    let policy = PIIRetentionPolicy(retentionDays: 10)
    let created = Date(timeIntervalSince1970: 1_700_000_000)
    let expiry = policy.expirationDate(from: created)
    #expect(expiry == created.addingTimeInterval(10 * PIIRetentionPolicy.secondsPerDay))
    #expect(!policy.isExpired(createdAt: created, now: expiry.addingTimeInterval(-1)))
    #expect(policy.isExpired(createdAt: created, now: expiry))
    #expect(policy.isExpired(createdAt: created, now: expiry.addingTimeInterval(1)))
}

@Test("이메일·이름 마스킹")
func maskingHelpers() {
    let policy = PIIRetentionPolicy.legalDefault
    #expect(policy.maskEmail("ada@example.com") == "a**@example.com")
    #expect(policy.maskEmail("a@b.c") == "*@b.c")
    #expect(policy.maskEmail("plain") == "p****")
    #expect(policy.maskName("Ada") == "A**")
    #expect(policy.maskName("한") == "*")
}

@Test("만료된 카드만 마스킹한다")
func cardRedactionRespectsExpiry() {
    let created = Date(timeIntervalSince1970: 1_000_000_000)
    let member = Member(
        id: "7",
        name: "Ada",
        email: "ada@example.com",
        createdAt: created
    )
    let card = MemberCardViewModel(member: member)
    let policy = PIIRetentionPolicy(retentionDays: 1)
    let fresh = card.redacted(policy: policy, now: created.addingTimeInterval(60))
    #expect(fresh.member.email == "ada@example.com")
    let expired = card.redacted(
        policy: policy,
        now: created.addingTimeInterval(PIIRetentionPolicy.secondsPerDay)
    )
    #expect(expired.member.email == "a**@example.com")
    #expect(expired.member.name == "A**")
    #expect(card.member.email == "ada@example.com")
}
