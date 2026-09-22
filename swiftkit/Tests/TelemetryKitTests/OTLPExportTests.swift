import XCTest
import EndpointRouterKit
@testable import TelemetryKit

final class OTLPExportTests: XCTestCase {
    func testPayloadCarriesServiceName() throws {
        let metrics = [
            OTLPExport.Metric(
                name: "touched_sessions",
                description: "touched",
                dataPoints: [
                    .init(value: 5, attributes: ["document.path": "/a.md"]),
                ]
            ),
        ]
        let payload = OTLPExport.payload(serviceName: "agent-document-usage", metrics: metrics)
        let json = try XCTUnwrap(String(data: try OTLPExport.jsonData(payload), encoding: .utf8))
        XCTAssertTrue(json.contains("\"service.name\""))
        XCTAssertTrue(json.contains("agent-document-usage"))
        XCTAssertTrue(json.contains("\"gauge\""))
        XCTAssertTrue(json.contains("/a.md"))
    }

    func testDefaultEndpointComesFromEndpointRouterKitOtel() {
        let base = EndpointRouter.string("otel")
        if base.isEmpty {
            XCTAssertEqual(OTLPExport.defaultEndpoint, URL(fileURLWithPath: "/invalid-otel"))
        } else {
            XCTAssertEqual(
                OTLPExport.defaultEndpoint,
                EndpointRouter.joining(base, path: "v1/metrics")
            )
        }
    }
}
