import Foundation
import Testing
@testable import ProductPortfolioKit

@Suite("Screenshot path seeder")
struct ScreenshotPathSeederTests {
    @Test("discovers preferred store-assets and docs images")
    func discoversPreferred() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("demo-swift", isDirectory: true)
        let out = app.appendingPathComponent("store-assets/out", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let hero = out.appendingPathComponent("hero.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: hero)
        let noise = app.appendingPathComponent("Assets.xcassets/AppIcon.appiconset", isDirectory: true)
        try FileManager.default.createDirectory(at: noise, withIntermediateDirectories: true)
        try Data([0x00]).write(to: noise.appendingPathComponent("icon.png"))

        let found = ScreenshotPathSeeder.discoverScreenshots(in: app)
        #expect(found.map(\.lastPathComponent) == ["hero.png"])
    }

    @Test("seed fills empty screenshotPaths and dry-run leaves store")
    func seedDryAndApply() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let apps = root.appendingPathComponent("apps", isDirectory: true)
        let app = apps.appendingPathComponent("sample-app-swift", isDirectory: true)
        let assets = app.appendingPathComponent("docs/assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        let shot = assets.appendingPathComponent("overview.png")
        try Data([0x01, 0x02]).write(to: shot)

        let portfolio = root.appendingPathComponent("portfolio", isDirectory: true)
        let store = try ProductStore(rootDirectory: portfolio)
        try store.add(
            try Product(
                names: .init(slug: "sample-app-swift", nameKo: "샘플", nameEn: "Sample"),
                pitch: .init(
                    role: "샘플 역할 설명입니다",
                    classification: .productCandidate,
                    buyerPersona: "테스터",
                    salesAngle: "바로 쓴다",
                    categories: [],
                    priceIdea: "무료"
                ),
                surface: .init(readiness: 3, screenshotPaths: [])
            )
        )

        let dry = try ScreenshotPathSeeder.seed(
            in: store,
            options: .init(appsRoot: apps, dryRun: true)
        )
        #expect(dry.updated == 1)
        #expect(try store.show(slug: "sample-app-swift").screenshotPaths.isEmpty)

        let applied = try ScreenshotPathSeeder.seed(
            in: store,
            options: .init(appsRoot: apps, dryRun: false)
        )
        #expect(applied.updated == 1)
        let paths = try store.show(slug: "sample-app-swift").screenshotPaths
        #expect(paths.count == 1)
        #expect(paths[0].hasSuffix("overview.png"))
    }

    private func temporaryRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("shot-seed-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
