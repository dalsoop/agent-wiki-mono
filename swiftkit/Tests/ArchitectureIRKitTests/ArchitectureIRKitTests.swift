import Testing
@testable import ArchitectureIRKit
import Foundation

@Suite("ArchitectureIRKit Tests")
struct ArchitectureIRKitTests {

    @Test("IR Document Validation and Deterministic Serialization")
    func testIRSerialization() throws {
        let node1 = ArchitectureNode(
            id: "app:test-app",
            name: "Test App",
            type: .app,
            district: .agent,
            tetrahedron: TetrahedronSurfaceCompletion(
                gui: SurfaceFacet(status: .implemented),
                core: SurfaceFacet(status: .implemented),
                cli: SurfaceFacet(status: .implemented),
                statemirror: SurfaceFacet(status: .implemented)
            ),
            sourceEvidence: SourceEvidence(filePath: "apps/test-app/Package.swift"),
            wikiId: "8c804009"
        )

        let node2 = ArchitectureNode(
            id: "swiftkit:CommandKit",
            name: "CommandKit",
            type: .swiftkit,
            district: .core,
            tetrahedron: TetrahedronSurfaceCompletion(
                gui: SurfaceFacet(status: .notApplicable),
                core: SurfaceFacet(status: .implemented),
                cli: SurfaceFacet(status: .notApplicable),
                statemirror: SurfaceFacet(status: .notApplicable)
            ),
            sourceEvidence: SourceEvidence(filePath: "swiftkit/Sources/CommandKit/System.swift")
        )

        let edge = ArchitectureEdge(
            source: "app:test-app",
            target: "swiftkit:CommandKit",
            type: .dependsOn,
            contract: EdgeContract(kind: .directImport)
        )

        let doc = ArchitectureIRDocument(
            metadata: ArchitectureMetadata(
                monorepoVersion: "1.0.0",
                gitSha: "abcdef123456",
                governanceSummary: GovernanceSummary(
                    processComplianceRate: 1.0,
                    ruleOfThreeCandidatesCount: 0,
                    tetrahedronMaturityRate: 1.0,
                    totalNodesCount: 2,
                    totalEdgesCount: 1
                )
            ),
            nodes: [node1, node2],
            edges: [edge]
        )

        let data = try ArchitectureIRCodec.encode(doc, pretty: true, validate: true)
        #expect(!data.isEmpty)

        let decoded = try ArchitectureIRCodec.decode(from: data, validate: true)
        #expect(decoded.nodes.count == 2)
        #expect(decoded.edges.count == 1)
        #expect(decoded.nodes[0].name == "Test App")
    }
}
