import XCTest
import EndpointRouterKit
@testable import GujoStoreOpsCore

final class CatalogArtifactURLTests: XCTestCase {
    func testInternalHttpsBecomesHttp() {
        let host = CatalogArtifactURL.hostKR
        guard let u = EndpointRouter.joining("https://\(host)", path: "apks/net.ranode.gujostore-1.apk") else {
            XCTFail("expected catalog-kr https URL")
            return
        }
        let out = CatalogArtifactURL.downloadURL(from: u)
        XCTAssertEqual(out.scheme, "http")
        XCTAssertEqual(out.host, host)
        XCTAssertEqual(out.path, "/apks/net.ranode.gujostore-1.apk")
    }

    func testHttpUnchanged() {
        let host = CatalogArtifactURL.hostKR
        guard let u = EndpointRouter.joining("http://\(host)", path: "apks/x.apk") else {
            XCTFail("expected catalog-kr http URL")
            return
        }
        XCTAssertEqual(CatalogArtifactURL.downloadURL(from: u), u)
    }

    func testPublicHttpsUnchanged() {
        guard let u = EndpointRouter.joining(EndpointRouter.apps, path: "apks/x.apk") else {
            XCTFail("expected apps joining URL")
            return
        }
        XCTAssertEqual(CatalogArtifactURL.downloadURL(from: u), u)
    }

    func testParquetHostAlsoRewritten() {
        let host = CatalogArtifactURL.hostParquet
        guard let u = EndpointRouter.joining("https://\(host)", path: "install/foo.apk") else {
            XCTFail("expected catalog-parquet https URL")
            return
        }
        let out = CatalogArtifactURL.downloadURL(from: u)
        XCTAssertEqual(out.scheme, "http")
        XCTAssertEqual(out.host, host)
    }
}
