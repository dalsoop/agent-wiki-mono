import XCTest
import PluginKit
@testable import GujoStoreOpsCore

final class CatalogV1BridgeTests: XCTestCase {
    func testParseMinimalIndex() throws {
        let json = """
        {
          "format": "catalog-v1",
          "packages": {
            "net.ranode.demo": {
              "name": "Demo",
              "summary": "hello",
              "versions": [
                {
                  "versionName": "1.0.0",
                  "versionCode": 1,
                  "apk": { "url": "apks/demo.apk", "size": 100 }
                }
              ]
            }
          }
        }
        """.data(using: .utf8)!
        let base = URL(string: "https://catalog.example")!
        let pkgs = try CatalogV1Bridge.parseIndex(json, baseURL: base)
        XCTAssertEqual(pkgs.count, 1)
        XCTAssertEqual(pkgs[0].packageName, "net.ranode.demo")
        XCTAssertEqual(pkgs[0].displayName, "Demo")
        XCTAssertEqual(pkgs[0].versionCode, 1)
        XCTAssertEqual(pkgs[0].installURL?.absoluteString, "https://catalog.example/install/net.ranode.demo.apk")
    }

    func testRejectWrongFormat() {
        let json = #"{"format":"nope","packages":{"a":{}}}"#.data(using: .utf8)!
        XCTAssertThrowsError(try CatalogV1Bridge.parseIndex(json, baseURL: URL(string: "https://x")!))
    }

    #if os(macOS)
    func testAdbParseDevices() {
        let raw = """
        List of devices attached
        SERIAL1 device product:foo model:Pixel_7 device:panther
        SERIAL2 offline
        """
        let devices = AdbClient.parseDevices(raw)
        XCTAssertEqual(devices.count, 2)
        XCTAssertEqual(devices[0].serial, "SERIAL1")
        XCTAssertTrue(devices[0].isReady)
        XCTAssertFalse(devices[1].isReady)
    }
    #endif

    func testCatalogV1PluginWithPluginRegistry() async throws {
        let registry = PluginRegistry()
        let plugin = CatalogV1Plugin()
        await registry.register(plugin)

        let resolved = registry.get(id: "catalog-v1-bridge")
        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.id, "catalog-v1-bridge")

        let json = """
        {
          "format": "catalog-v1",
          "packages": {
            "net.ranode.demo": {
              "name": "Demo",
              "summary": "hello"
            }
          }
        }
        """.data(using: .utf8)!
        // argv 규약: argv[0]=base64(data), argv[1]=baseURL
        let res = try await resolved?.execute(
            action: "parseIndex",
            argv: [json.base64EncodedString(), "https://catalog.example"])
        XCTAssertEqual(res?["status"] as? String, "ok")
        XCTAssertEqual(res?["count"] as? Int, 1)
    }
}

