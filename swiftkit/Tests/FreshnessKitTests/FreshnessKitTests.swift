import XCTest
@testable import FreshnessKit

final class SourceFreshnessTests: XCTestCase {
    private func tempApp() -> String {
        let dir = NSTemporaryDirectory() + "sf-\(UUID().uuidString)"
        do { try FileManager.default.createDirectory(atPath: dir + "/Sources/Foo", withIntermediateDirectories: true) } catch { _ = error }
        return dir
    }
    private func write(_ path: String, mtime: Int) throws {
        FileManager.default.createFile(atPath: path, contents: Data("x".utf8))
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: Double(mtime))], ofItemAtPath: path)
    }

    /// raw lstat 기반 walk 가 소스 트리의 최신 mtime 을 정확히 집고 .build/dot 은 제외한다.
    func testLatestSourceMTimePicksNewestSkipsBuildAndDotfiles() throws {
        let app = tempApp()
        defer { try? FileManager.default.removeItem(atPath: app) }
        try write(app + "/Sources/Foo/a.swift", mtime: 1_000_000)   // 오래된 소스
        try write(app + "/Sources/Foo/b.swift", mtime: 2_000_000)   // 최신 소스 ← 정답
        try FileManager.default.createDirectory(
            atPath: app + "/Sources/Foo/.build", withIntermediateDirectories: true)
        try write(app + "/Sources/Foo/.build/x", mtime: 9_000_000)  // .build → 무시
        try write(app + "/Sources/Foo/.hidden", mtime: 8_000_000)   // dotfile → 무시

        XCTAssertEqual(SourceFreshnessScanner().latestSourceMTime(appDir: app), 2_000_000)
    }

    /// 병렬 evaluateAll 이 순차 evaluate 와 동일 결과 + 입력 순서 보존 + 데드락 없이 완료.
    func testEvaluateAllParallelMatchesSequentialAndPreservesOrder() async throws {
        let fm = FileManager.default
        var apps: [String] = []
        defer { apps.forEach { try? fm.removeItem(atPath: $0) } }
        // 10개 앱, 각기 다른 소스 mtime.
        var items: [(appDir: String, installedBundlePath: String?)] = []
        for k in 0..<10 {
            let app = NSTemporaryDirectory() + "pa-\(UUID().uuidString)"
            try fm.createDirectory(atPath: app + "/Sources/M", withIntermediateDirectories: true)
            try write(app + "/Sources/M/f.swift", mtime: 1_700_000_000 + k * 100)
            apps.append(app)
            items.append((app, nil))
        }
        let scanner = SourceFreshnessScanner()
        let parallel = await scanner.evaluateAll(items)
        let sequential = items.map { scanner.evaluate(appDir: $0.appDir, installedBundlePath: $0.installedBundlePath) }
        XCTAssertEqual(parallel.count, 10)
        XCTAssertEqual(parallel, sequential)                       // 순서·값 동일
        XCTAssertEqual(parallel.map(\.sourceMTime), (0..<10).map { 1_700_000_000 + $0 * 100 })
        let serialCap = scanner.evaluateAllSync(items, maxConcurrent: 1)
        XCTAssertEqual(serialCap, sequential)
    }

    func testEvaluateAllEmptyReturnsEmpty() async {
        let r = await SourceFreshnessScanner().evaluateAll([])
        XCTAssertTrue(r.isEmpty)
    }

    func testNotInstalledWhenNoBundleButHasSource() throws {
        let app = tempApp()
        defer { try? FileManager.default.removeItem(atPath: app) }
        try write(app + "/Sources/Foo/a.swift", mtime: 1_500_000)
        let f = SourceFreshnessScanner().evaluate(appDir: app, installedBundlePath: nil)
        XCTAssertEqual(f.state, .notInstalled)
        XCTAssertEqual(f.sourceMTime, 1_500_000)
    }

    /// 소스가 설치본 build epoch 보다 60초 넘게 새로우면 stale, 아니면 upToDate.
    func testStaleVsUpToDateAgainstInstalledBuild() throws {
        let app = tempApp()
        defer { try? FileManager.default.removeItem(atPath: app) }
        try write(app + "/Sources/Foo/a.swift", mtime: 1_700_000_000)
        // 가짜 설치 번들 — Contents/Info.plist 에 CFBundleVersion(=ship epoch).
        func bundle(buildEpoch: Int) throws -> String {
            let b = NSTemporaryDirectory() + "b-\(UUID().uuidString).app"
            try FileManager.default.createDirectory(atPath: b + "/Contents", withIntermediateDirectories: true)
            let plist = "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict>"
                + "<key>CFBundleVersion</key><string>\(buildEpoch)</string></dict></plist>"
            try plist.write(toFile: b + "/Contents/Info.plist", atomically: true, encoding: .utf8)
            return b
        }
        let older = try bundle(buildEpoch: 1_699_000_000)   // 소스보다 오래됨 → stale
        let newer = try bundle(buildEpoch: 1_700_000_100)   // 소스보다 새로움 → upToDate
        defer { try? FileManager.default.removeItem(atPath: older); try? FileManager.default.removeItem(atPath: newer) }
        XCTAssertEqual(SourceFreshnessScanner().evaluate(appDir: app, installedBundlePath: older).state, .stale)
        XCTAssertEqual(SourceFreshnessScanner().evaluate(appDir: app, installedBundlePath: newer).state, .upToDate)
    }
}
