import Foundation
import Testing
@testable import GujoMemberKit

@Test("검색 쿼리 직렬화 — 빈 칸은 빼고 limit 은 항상 붙는다")
func searchQuerySerialization() {
    let empty = MemberSearchQuery()
    #expect(empty.serializedQuery == "limit=50")

    let query = MemberSearchQuery(
        email: "ada@example.com",
        name: "Ada",
        tag: "vip",
        locale: "ko",
        limit: 20,
        cursor: "7"
    )
    #expect(query.serializedQuery == "email=ada@example.com&name=Ada&tag=vip&locale=ko&limit=20&cursor=7")
    #expect(query.queryItems.count == 6)
}

@Test("검색 쿼리 매칭")
func searchQueryMatchesMember() {
    let member = Member(
        id: "7",
        name: "Ada Lovelace",
        email: "ada@example.com",
        locale: "ko",
        tags: ["vip"]
    )
    #expect(MemberSearchQuery(email: "ADA@").matches(member))
    #expect(MemberSearchQuery(name: "love").matches(member))
    #expect(MemberSearchQuery(tag: "VIP").matches(member))
    #expect(MemberSearchQuery(locale: "ko").matches(member))
    #expect(!MemberSearchQuery(tag: "admin").matches(member))
    #expect(!MemberSearchQuery(email: "bob@").matches(member))
}

@Test("공백 필드와 limit 하한")
func searchQueryNormalizes() {
    let query = MemberSearchQuery(email: "  ", name: " Ada ", limit: 0)
    #expect(query.email == nil)
    #expect(query.name == "Ada")
    #expect(query.limit == 1)
    #expect(query.serializedQuery == "name=Ada&limit=1")
}
