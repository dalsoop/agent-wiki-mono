import XCTest
@testable import InteropKit

final class SparkleProductIndexTests: XCTestCase {
    func testLoadSkipsIOSPrefersSwiftAndRoundtripsJSON() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("spi-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try writeApp(at: root.appendingPathComponent("sample-ios"), id: 151, bundle: "net.ranode.ios")
        try writeApp(at: root.appendingPathComponent("sample"), id: 151, bundle: "net.ranode.sample")
        try writeApp(at: root.appendingPathComponent("sample-swift"), id: 151, bundle: "net.ranode.mac")
        let map = SparkleProductIndex.load(appsRoot: root)
        XCTAssertEqual(map[151], "net.ranode.mac")
        let decoded = try SparkleProductIndex.map(fromJSON: SparkleProductIndex.jsonData(from: map))
        XCTAssertEqual(decoded, map)
        try FileManager.default.removeItem(at: root)
    }

    func testEmbedWritesResourceWhenMapNonEmpty() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("spi-embed-\(UUID().uuidString)", isDirectory: true)
        try writeApp(at: root.appendingPathComponent("demo-swift"), id: 9, bundle: "net.ranode.demo")
        let app = FileManager.default.temporaryDirectory
            .appendingPathComponent("Demo.app", isDirectory: true)
        let n = try SparkleProductIndex.embed(intoAppBundle: app, appsRoot: root)
        XCTAssertEqual(n, 1)
        XCTAssertEqual(SparkleProductIndex.loadFromAppBundle(app)[9], "net.ranode.demo")
        try FileManager.default.removeItem(at: root)
        try FileManager.default.removeItem(at: app)
    }

    func testEnclosingAppBundleFindsAppFromHelpersCLI() {
        let helper = "/tmp/GujoCloudApps.app/Contents/Helpers/gujo-cloud-apps"
        XCTAssertEqual(
            SparkleProductIndex.enclosingAppBundle(from: helper)?.path,
            "/tmp/GujoCloudApps.app")
        XCTAssertNil(SparkleProductIndex.enclosingAppBundle(from: "/usr/bin/true"))
    }

    func testEmbedSkipsEmptyScan() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("spi-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let app = FileManager.default.temporaryDirectory
            .appendingPathComponent("Empty.app", isDirectory: true)
        XCTAssertEqual(try SparkleProductIndex.embed(intoAppBundle: app, appsRoot: root), 0)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: SparkleProductIndex.resourceURL(inAppBundle: app).path))
        try FileManager.default.removeItem(at: root)
    }

    private func writeApp(at app: URL, id: Int, bundle: String) throws {
        let packaging = app.appendingPathComponent("Packaging", isDirectory: true)
        try FileManager.default.createDirectory(at: packaging, withIntermediateDirectories: true)
        try """
        {"binding":{"product_id":\(id)}}
        """.write(to: app.appendingPathComponent("gujo-product.json"), atomically: true, encoding: .utf8)
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>CFBundleIdentifier</key><string>\(bundle)</string>
        </dict></plist>
        """.write(to: packaging.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
    }
}
