import XCTest
@testable import VaultwardenKit

/// 태그(다축 분류) — 커스텀 필드 규약이라 공식 클라이언트에서도 보인다.
final class VaultTagTests: XCTestCase {
    func testTagsRoundTrip() {
        var item = VaultItem(id: "i1", name: "은행")
        XCTAssertEqual(item.tags, [])
        item.tags = ["사업", "금융", "세무"]
        XCTAssertEqual(item.tags, ["사업", "금융", "세무"])
        // 커스텀 필드 하나로 저장된다(웹에서도 '태그' 필드로 보임)
        XCTAssertEqual(item.fields.filter { $0.name == VaultItem.tagFieldName }.count, 1)
        XCTAssertEqual(item.fields.first { $0.name == VaultItem.tagFieldName }?.value, "사업, 금융, 세무")
        XCTAssertEqual(item.fields.first { $0.name == VaultItem.tagFieldName }?.hidden, false)
    }

    func testTagsTrimAndDropEmpties() {
        var item = VaultItem(id: "i1", name: "x")
        item.tags = ["  사업 ", "", "   ", "금융"]
        XCTAssertEqual(item.tags, ["사업", "금융"])
    }

    func testClearingTagsRemovesField() {
        var item = VaultItem(id: "i1", name: "x")
        item.tags = ["사업"]
        item.tags = []
        XCTAssertTrue(item.fields.isEmpty)
        XCTAssertEqual(item.tags, [])
    }

    func testExistingFieldsPreserved() {
        var item = VaultItem(id: "i1", name: "x")
        item.fields = [VaultField(name: "계정번호", value: "123", hidden: true)]
        item.tags = ["사업"]
        XCTAssertEqual(item.fields.count, 2)
        XCTAssertTrue(item.fields.contains { $0.name == "계정번호" && $0.hidden })
    }

    /// 검색이 태그·필드까지 훑는다(숨김 필드 값은 제외).
    func testSearchIncludesTagsButNotHiddenValues() {
        var item = VaultItem(id: "i1", name: "은행")
        item.tags = ["사업"]
        item.fields.append(VaultField(name: "비밀메모", value: "일급비밀", hidden: true))
        XCTAssertTrue(item.matches("사업"))
        XCTAssertTrue(item.matches("비밀메모"))
        XCTAssertFalse(item.matches("일급비밀"))
    }

    /// 태그 이름 변경 — 항목 안 한 군데만 바꾸고, 이미 새 이름이 있으면 합친다.
    func testRenameTagInItem() {
        var item = VaultItem(id: "i1", name: "은행")
        item.tags = ["사업", "금융", "세무"]
        XCTAssertTrue(item.renameTag(from: "금융", to: "결제"))
        XCTAssertEqual(item.tags, ["사업", "결제", "세무"])
        // 옛 태그 없으면 no-op
        XCTAssertFalse(item.renameTag(from: "없는태그", to: "x"))
        XCTAssertEqual(item.tags, ["사업", "결제", "세무"])
        // 같은 이름 no-op
        XCTAssertFalse(item.renameTag(from: "사업", to: "사업"))
        // 대상이 이미 있으면 중복 제거
        XCTAssertTrue(item.renameTag(from: "세무", to: "사업"))
        XCTAssertEqual(item.tags, ["사업", "결제"])
    }

    func testRenameTagTrimsWhitespace() {
        var item = VaultItem(id: "i1", name: "x")
        item.tags = ["사업"]
        XCTAssertTrue(item.renameTag(from: "  사업  ", to: "  운영  "))
        XCTAssertEqual(item.tags, ["운영"])
    }
}

/// 조직·컬렉션 모델과 카드 저장 계약.
final class VaultOrgTests: XCTestCase {
    func testCollectionDTODecodesBothCasings() throws {
        let upper = #"{"Id":"c1","Name":"2.a|b|c","OrganizationId":"o1"}"#
        let lower = #"{"id":"c2","name":"2.a|b|c","organizationId":"o2"}"#
        let a = try JSONDecoder().decode(CollectionDTO.self, from: Data(upper.utf8))
        let b = try JSONDecoder().decode(CollectionDTO.self, from: Data(lower.utf8))
        XCTAssertEqual(a.organizationId, "o1")
        XCTAssertEqual(b.organizationId, "o2")
    }

    func testOrganizationDTODecodes() throws {
        let json = #"{"Id":"o1","Name":"달숲","Enabled":true,"Key":"4.abc"}"#
        let org = try JSONDecoder().decode(OrganizationDTO.self, from: Data(json.utf8))
        XCTAssertEqual(org.id, "o1")
        XCTAssertEqual(org.name, "달숲")
        XCTAssertEqual(org.enabled, true)
    }

    /// 카드 항목을 저장해도 카드 정보가 유지돼야 한다(2026-08-05 데이터 손실 버그).
    func testCardDTOCarriesAllFields() throws {
        let dto = CardDTO(
            cardholderName: "enc1", brand: "enc2", number: "enc3",
            expMonth: "enc4", expYear: "enc5", code: "enc6"
        )
        let data = try JSONEncoder().encode(dto)
        let decoded = try JSONDecoder().decode(CardDTO.self, from: data)
        XCTAssertEqual(decoded.number, "enc3")
        XCTAssertEqual(decoded.code, "enc6")
    }

    func testIdentityIsEmptyDetection() {
        XCTAssertTrue(VaultIdentity().isEmpty)
        XCTAssertFalse(VaultIdentity(person: .init(firstName: "정한")).isEmpty)
    }

    func testItemCarriesOrgAndCollections() {
        var item = VaultItem(id: "i1", name: "공용 계정")
        item.organizationId = "o1"
        item.collectionIds = ["c1", "c2"]
        XCTAssertEqual(item.organizationId, "o1")
        XCTAssertEqual(item.collectionIds, ["c1", "c2"])
    }
}
