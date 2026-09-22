import Foundation
import Testing
@testable import VaultwardenKit

/// CipherDTO 는 서버가 대소문자 키를 섞어 써서 인코더·디코더를 손으로 쓴다.
/// 그래서 프로퍼티만 늘리고 세 곳(CodingKeys·init(from:)·encode(to:))을 안 고치면
/// **컴파일은 되고 값만 조용히 사라진다.** 그 사고가 실제로 났으므로 라운드트립을 못 박는다.
@Suite("CipherDTO 직렬화")
struct CipherDTOCodingTests {
    private func roundTrip(_ dto: CipherDTO) throws -> CipherDTO {
        let data = try JSONEncoder().encode(dto)
        return try JSONDecoder().decode(CipherDTO.self, from: data)
    }

    @Test("신원·조직·컬렉션이 왕복에서 살아남는다")
    func identityAndOrgSurviveRoundTrip() throws {
        var dto = CipherDTO(type: 4, name: "enc-name")
        dto.identity = IdentityDTO(person: .init(firstName: "enc-first", lastName: "enc-last"))
        dto.organizationId = "org-1"
        dto.collectionIds = ["col-1", "col-2"]

        let decoded = try roundTrip(dto)
        #expect(decoded.identity?.firstName == "enc-first")
        #expect(decoded.identity?.lastName == "enc-last")
        #expect(decoded.organizationId == "org-1")
        #expect(decoded.collectionIds == ["col-1", "col-2"])
    }

    @Test("인코딩 결과에 신원·조직 키가 실제로 들어간다")
    func encodedPayloadCarriesIdentity() throws {
        var dto = CipherDTO(type: 4)
        dto.identity = IdentityDTO(person: .init(firstName: "enc-first"))
        dto.organizationId = "org-1"
        let object = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(dto)
        ) as? [String: Any]
        #expect(object?["identity"] != nil)
        #expect(object?["organizationId"] as? String == "org-1")
    }

    @Test("서버의 대문자 키도 읽는다")
    func decodesPascalCaseKeys() throws {
        let json = """
        {"Type":4,"Identity":{"FirstName":"enc-first"},"OrganizationId":"org-9","CollectionIds":["c1"]}
        """
        let decoded = try JSONDecoder().decode(CipherDTO.self, from: Data(json.utf8))
        #expect(decoded.type == 4)
        #expect(decoded.identity?.firstName == "enc-first")
        #expect(decoded.organizationId == "org-9")
        #expect(decoded.collectionIds == ["c1"])
    }

    @Test("카드·보안메모도 왕복에서 살아남는다")
    func cardAndSecureNoteSurvive() throws {
        var card = CipherDTO(type: 3)
        card.card = CardDTO(number: "enc-number", code: "enc-code")
        #expect(try roundTrip(card).card?.number == "enc-number")

        var note = CipherDTO(type: 2)
        note.secureNote = SecureNoteDTO(type: 0)
        #expect(try roundTrip(note).secureNote != nil)
    }
}
