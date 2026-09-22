import Foundation
import ProductPortfolioKit
import Testing

@Suite("ShowcasePackageReader")
struct ShowcasePackageReaderTests {
    @Test func existingImageURLs_filtersMissingAndNonImages() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("showcase-reader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let png = dir.appendingPathComponent("hero.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: png)
        let txt = dir.appendingPathComponent("note.txt")
        try "hi".write(to: txt, atomically: true, encoding: .utf8)

        let urls = ShowcasePackageReader.existingImageURLs(from: [
            png.path,
            txt.path,
            dir.appendingPathComponent("missing.jpg").path,
            "  ",
            png.path,
        ])
        #expect(urls.map(\.path) == [png.path])
    }

    @Test func landingAndFirstRun_loadFromShowcaseRoot() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("showcase-pkg-\(UUID().uuidString)", isDirectory: true)
        let landings = root.appendingPathComponent("landings", isDirectory: true)
        let firstRun = root.appendingPathComponent("first-run", isDirectory: true)
        try FileManager.default.createDirectory(at: landings, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: firstRun, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "# 랜딩".write(
            to: landings.appendingPathComponent("demo-app.md"),
            atomically: true,
            encoding: .utf8
        )
        try "# 첫실행".write(
            to: firstRun.appendingPathComponent("demo-app.md"),
            atomically: true,
            encoding: .utf8
        )

        #expect(ShowcasePackageReader.landingMarkdown(slug: "demo-app", root: root) == "# 랜딩")
        #expect(ShowcasePackageReader.firstRunMarkdown(slug: "demo-app", root: root) == "# 첫실행")
        #expect(ShowcasePackageReader.landingMarkdown(slug: "nope", root: root) == nil)
    }

    @Test func displayableImageURLs_mergesGeneratedVisuals() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("showcase-vis-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let a = dir.appendingPathComponent("a.png")
        let b = dir.appendingPathComponent("b.jpg")
        try Data([1]).write(to: a)
        try Data([2]).write(to: b)

        let product = try Product(
            names: .init(slug: "demo-app", nameKo: "데모", nameEn: "Demo"),
            pitch: .init(
                role: "역할 한 줄 이상입니다",
                classification: .productCandidate,
                buyerPersona: "페르소나",
                salesAngle: "판매각",
                categories: [],
                priceIdea: "가격"
            ),
            surface: .init(
                readiness: 3,
                screenshotPaths: [a.path],
                visuals: [
                    ProductVisual(
                        id: "hero",
                        kind: .hero,
                        status: .generated,
                        aspect: "16:9",
                        prompt: "x",
                        path: b.path
                    ),
                ]
            )
        )
        let urls = ShowcasePackageReader.displayableImageURLs(for: product)
        #expect(Set(urls.map(\.path)) == Set([a.path, b.path]))
    }
}
