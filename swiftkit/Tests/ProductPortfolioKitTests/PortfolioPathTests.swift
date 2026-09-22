import Foundation
import Testing
@testable import ProductPortfolioKit

@Suite("PortfolioPath")
struct PortfolioPathTests {
    private let home = "/Users/example"

    @Test("makingPortable rewrites home absolute prefix to tilde form")
    func makingPortableHomeAbsolute() {
        let absolute = "\(home)/.product-portfolio/visuals/sample-app/hero.jpg"
        #expect(PortfolioPath.makingPortable(absolute, home: home)
            == "~/.product-portfolio/visuals/sample-app/hero.jpg")
    }

    @Test("makingPortable leaves non-home paths unchanged")
    func makingPortableOutsideHome() {
        let absolute = "/opt/data/shot.png"
        #expect(PortfolioPath.makingPortable(absolute, home: home) == absolute)
    }

    @Test("makingPortable keeps already-portable tilde paths")
    func makingPortableAlreadyTilde() {
        let portable = "~/.product-portfolio/visuals/sample-app/hero.jpg"
        #expect(PortfolioPath.makingPortable(portable, home: home) == portable)
    }

    @Test("expandingTilde resolves tilde to the given home")
    func expandingTildeResolves() {
        let portable = "~/.product-portfolio/visuals/sample-app/hero.jpg"
        #expect(PortfolioPath.expandingTilde(portable, home: home)
            == "\(home)/.product-portfolio/visuals/sample-app/hero.jpg")
    }

    @Test("expandingTilde is identity for absolute non-tilde paths")
    func expandingTildeAbsoluteIdentity() {
        let absolute = "\(home)/.product-portfolio/visuals/sample-app/hero.jpg"
        #expect(PortfolioPath.expandingTilde(absolute, home: home) == absolute)
    }

    @Test("round-trip home absolute → portable → expanded equals original")
    func roundTrip() {
        let absolute = "\(home)/.product-portfolio/visuals/x/screenshot-main.jpg"
        let portable = PortfolioPath.makingPortable(absolute, home: home)
        let expanded = PortfolioPath.expandingTilde(portable, home: home)
        #expect(portable == "~/.product-portfolio/visuals/x/screenshot-main.jpg")
        #expect(expanded == absolute)
    }

    @Test("markGenerated stores portable path when given home absolute path")
    func markGeneratedStoresPortable() throws {
        let product = try Product(
            names: .init(slug: "sample-app", nameKo: "샘플", nameEn: "Sample"),
            pitch: .init(
                role: "role",
                classification: .productCandidate,
                buyerPersona: "persona",
                salesAngle: "angle",
                categories: ["tools"],
                priceIdea: "free"
            ),
            surface: .init(
                readiness: 4,
                screenshotPaths: [],
                visuals: [
                    ProductVisual(
                        id: "hero",
                        kind: .hero,
                        status: .planned,
                        aspect: "16:9",
                        prompt: "prompt"
                    ),
                ]
            )
        )
        let absolute = "\(NSHomeDirectory())/.product-portfolio/visuals/sample-app/hero.jpg"
        let marked = try ProductVisualDraftFactory.markGenerated(
            on: product,
            slotID: "hero",
            path: absolute
        )
        #expect(marked.visuals[0].status == .generated)
        #expect(marked.visuals[0].path == "~/.product-portfolio/visuals/sample-app/hero.jpg")
        #expect(marked.screenshotPaths == ["~/.product-portfolio/visuals/sample-app/hero.jpg"])
        #expect(
            PortfolioPath.expandingTilde(marked.visuals[0].path ?? "")
                == absolute
        )
    }

    @Test("fileExists expands tilde before checking")
    func fileExistsExpandsTilde() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("portfolio-path-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("probe.jpg")
        try Data([0xFF, 0xD8, 0xFF]).write(to: file)

        let home = dir.path
        let portable = "~/probe.jpg"
        #expect(PortfolioPath.fileExists(portable, home: home))
        #expect(!PortfolioPath.fileExists("~/missing.jpg", home: home))
    }
}
