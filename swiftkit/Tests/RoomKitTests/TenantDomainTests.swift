import Testing
import Foundation
@testable import RoomKit

@Suite("TenantDomain 및 RoomSpec tenantID 호환성 테스트")
struct TenantDomainTests {

    @Test("TenantID 정규화: tenant: 및 @ 접두사 처리 및 slug 동등성")
    func testTenantIDNormalization() {
        let t1 = TenantID("personal")
        let t2 = TenantID("tenant:personal")
        let t3 = TenantID("tenant-personal")
        let t4 = TenantID("@personal")

        #expect(t1.slug == "personal")
        #expect(t2.slug == "personal")
        #expect(t3.slug == "personal")
        #expect(t4.slug == "personal")
        #expect(t1 == t2)
        #expect(t2 == t3)
        #expect(t3 == t4)
        #expect(t1.logicalID == "tenant:personal")
        #expect(t1.description == "tenant:personal")
    }

    @Test("TenantRegistry built-in 테넌트 매핑 및 번들 ID 판정")
    func testTenantRegistryResolutions() {
        let registry = TenantRegistry.shared
        let personal = registry.resolve(id: .personal)
        #expect(personal.name == "Personal")
        #expect(personal.symbol == "person.fill")
        #expect(personal.colorHex == "#5E5CE6")

        let gujo = registry.resolve(id: .gujo)
        #expect(gujo.name == "Gujo")
        #expect(gujo.symbol == "globe.asia.australia")

        let agentAppDomain = registry.resolve(bundleID: "net.ranode.agent-room-terminal")
        #expect(agentAppDomain.tenantID == .personal)

        let gujoAppDomain = registry.resolve(bundleID: "net.ranode.gujo-cloud")
        #expect(gujoAppDomain.tenantID == .gujo)
    }

    @Test("RoomSpec tenantID 하위 호환 직렬화: tenant 와 tenantID 상호 복원")
    func testRoomSpecTenantIDCompatibility() throws {
        let spec = RoomSpec(
            roomID: UUID(),
            tenantID: .personal,
            task: "테넌트 도메인 검증",
            verdict: "pass"
        )

        #expect(spec.tenant == "personal")
        #expect(spec.tenantID == .personal)

        let data = try JSONEncoder().encode(spec)
        let jsonStr = try #require(String(data: data, encoding: .utf8))
        #expect(jsonStr.contains("\"tenant\":\"personal\""))
        #expect(jsonStr.contains("\"tenantID\":\"tenant:personal\""))

        // 구버전 JSON (tenant 키만 있는 경우) 디코딩 호환
        let legacyJSON = try #require("""
        {
            "roomID": "\(spec.roomID.uuidString)",
            "tenant": "gujo",
            "task": "레거시 방",
            "verdict": "ok",
            "walls": {
                "filesystem": { "denyRead": [], "allowRead": [], "allowWrite": [], "denyWrite": [] },
                "network": { "allowedDomains": [], "deniedDomains": [], "allowLocalBinding": false },
                "executables": { "mode": "hostPath" }
            }
        }
        """.data(using: .utf8))

        let decoded = try JSONDecoder().decode(RoomSpec.self, from: legacyJSON)
        #expect(decoded.tenantID == .gujo)
        #expect(decoded.tenant == "gujo")
    }
}
