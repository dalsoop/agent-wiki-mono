import Foundation
import Testing
@testable import ProductPortfolioKit

@Suite("ProductPortfolioKit")
struct ProductStoreTests {
    @Test("valid product keeps every sales field")
    func validProduct() throws {
        let product = try fixture()
        #expect(product.slug == "sample-app")
        #expect(product.nameKo == "샘플 앱")
        #expect(product.classification == .productCandidate)
        #expect(product.readiness == 4)
        #expect(product.screenshotPaths == ["docs/sample.png"])
    }

    @Test("slug rejects uppercase and unsafe path components")
    func invalidSlug() {
        #expect(throws: ProductValidationError.self) {
            _ = try fixture(slug: "../Bad App")
        }
    }

    @Test("readiness stays in zero through five")
    func invalidReadiness() {
        #expect(throws: ProductValidationError.self) {
            _ = try fixture(readiness: 6)
        }
    }

    @Test("add persists a JSON file and show reads it")
    func roundTrip() throws {
        let store = try temporaryStore()
        let product = try fixture()
        try store.add(product)

        #expect(try store.show(slug: product.slug) == product)
        #expect(FileManager.default.fileExists(atPath: store.productsDirectory.appendingPathComponent("sample-app.json").path))
    }

    @Test("list sorts products by slug")
    func sortedList() throws {
        let store = try temporaryStore()
        try store.add(fixture(slug: "zulu-app"))
        try store.add(fixture(slug: "alpha-app"))

        #expect(try store.list().map(\.slug) == ["alpha-app", "zulu-app"])
    }

    @Test("add protects an existing product")
    func duplicateAdd() throws {
        let store = try temporaryStore()
        try store.add(fixture())

        #expect(throws: ProductStoreError.self) {
            try store.add(fixture())
        }
    }

    @Test("show reports a missing slug")
    func missingShow() throws {
        let store = try temporaryStore()
        #expect(throws: ProductStoreError.self) {
            _ = try store.show(slug: "missing-app")
        }
    }

    @Test("save replaces an existing product")
    func saveReplaces() throws {
        let store = try temporaryStore()
        try store.add(fixture())
        try store.save(fixture(role: "바뀐 역할"))

        #expect(try store.show(slug: "sample-app").role == "바뀐 역할")
    }

    @Test("inventory seed maps legacy fields and preserves existing files")
    func seedMapping() throws {
        let store = try temporaryStore()
        let input = store.rootDirectory.appendingPathComponent("inventory.json")
        let data = Data("""
        [{"app":"seed-app","readme_role":"반복 업무를 **없앤다**","v0_class":"internal-tool","v0_readiness":3}]
        """.utf8)
        try data.write(to: input)

        let first = try InventorySeeder.seed(from: input, into: store)
        let second = try InventorySeeder.seed(from: input, into: store)
        let product = try store.show(slug: "seed-app")

        #expect(first.created == 1)
        #expect(second.skipped == 1)
        #expect(product.role == "반복 업무를 없앤다")
        #expect(product.classification == .internalTool)
        #expect(product.readiness == 3)
        // 판매 문구는 시드가 추측하지 않는다
        #expect(product.buyerPersona.isEmpty)
        #expect(product.salesAngle.isEmpty)
        #expect(product.priceIdea.isEmpty)
    }

    @Test("enrich only strips role markdown without inventing sales copy")
    func enrichExistingProducts() throws {
        let store = try temporaryStore()
        try store.add(
            fixture(
                role: "AI 세션이 **CLI**로 조종한다",
                buyerPersona: "",
                salesAngle: "",
                priceIdea: ""
            )
        )
        let result = try InventorySeeder.enrichExisting(in: store)
        let product = try store.show(slug: "sample-app")

        #expect(result.updated == 1)
        #expect(product.role == "AI 세션이 CLI로 조종한다")
        #expect(product.buyerPersona.isEmpty)
        #expect(product.salesAngle.isEmpty)
        #expect(product.priceIdea.isEmpty)
    }

    @Test("product generator builds from package evidence without sales templates")
    func productGeneratorFromEvidence() throws {
        let evidence = AppPackageEvidence(
            slug: "agent-ssot-swift",
            directoryURL: URL(fileURLWithPath: "/tmp/agent-ssot-swift"),
            readmeText: "# Title\n\n**에이전트** 규칙을 `SSOT`로 맞춘다.\n",
            hasPackageSwift: true,
            hasTests: true,
            hasSources: true
        )
        let product = try ProductGenerator.make(from: evidence)
        #expect(product.slug == "agent-ssot-swift")
        #expect(product.role == "에이전트 규칙을 SSOT로 맞춘다.")
        #expect(product.classification == .internalTool)
        #expect(product.readiness == 3)
        #expect(product.buyerPersona.isEmpty)
        #expect(product.salesAngle.isEmpty)
        #expect(product.priceIdea.isEmpty)
        #expect(ProductField.sales.isMissing(in: product))
        #expect(!ProductField.role.isMissing(in: product))
    }

    @Test("portfolio index joins product with evaluation and draft scores")
    func portfolioIndexAndDraft() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pss-portfolio-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let productStore = try ProductStore(rootDirectory: root)
        let product = try fixture(
            slug: "join-app",
            readiness: 4,
            buyerPersona: "개발자",
            salesAngle: "각도",
            priceIdea: "가격"
        )
        try productStore.add(product)
        let evalStore = EvaluationStore(root: PortfolioPaths.evaluations(root: root))
        try evalStore.save(try EvaluationDraftFactory.make(from: product))
        let index = PortfolioIndex(productStore: productStore, evaluationStore: evalStore)
        let cards = try index.cards()
        let status = try index.status()
        #expect(cards.count == 1)
        #expect(cards[0].hasEvaluation)
        #expect(cards[0].salesCopyComplete)
        #expect(status.evaluationCount == 1)
        #expect(status.productsWithoutEvaluation == 0)
        #expect(status.averageOverallScore != nil)
    }

    @Test("app catalog sync creates products from apps root")
    func appCatalogSyncCreates() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pss-sync-\(UUID().uuidString)", isDirectory: true)
        let apps = root.appendingPathComponent("apps", isDirectory: true)
        let appDir = apps.appendingPathComponent("demo-tool-swift", isDirectory: true)
        try FileManager.default.createDirectory(at: appDir.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: appDir.appendingPathComponent("Tests"), withIntermediateDirectories: true)
        try "// swift-tools-version: 6.0\n".write(
            to: appDir.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "# Demo\n\n데모 도구 한 줄 역할입니다.\n".write(
            to: appDir.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try ProductStore(rootDirectory: root.appendingPathComponent("portfolio"))
        let result = try AppCatalogSync.sync(appsRoot: apps, into: store)
        let product = try store.show(slug: "demo-tool-swift")

        #expect(result.scanned == 1)
        #expect(result.created == 1)
        #expect(product.role.contains("데모 도구"))
        #expect(product.buyerPersona.isEmpty)
    }

    @Test("markdown export includes product identity and pitch")
    func markdownExport() throws {
        let output = ProductExporter.markdown(try fixture())
        #expect(output.contains("# 샘플 앱"))
        #expect(output.contains("구매 이유"))
        #expect(output.contains("sample-app"))
    }

    @Test("legacy product JSON without visuals decodes as empty slots")
    func visualsDecodeDefaultEmpty() throws {
        let jsonString = """
        {
          "slug": "legacy-app",
          "nameKo": "레거시",
          "nameEn": "Legacy",
          "role": "역할",
          "classification": "product-candidate",
          "buyerPersona": "",
          "salesAngle": "",
          "categories": [],
          "priceIdea": "",
          "readiness": 2,
          "screenshotPaths": ["a.png"]
        }
        """
        let data = Data(jsonString.utf8)
        let product = try JSONDecoder().decode(Product.self, from: data)
        #expect(product.visuals.isEmpty)
        #expect(product.screenshotPaths == ["a.png"])
        #expect(product.hasAnyScreenshotAsset)
    }

    @Test("visual draft creates planned slots and imports screenshot paths")
    func visualDraftFactory() throws {
        let store = try temporaryStore()
        let product = try fixture(slug: "visual-app")
        try store.add(product)

        let first = try ProductVisualDraftFactory.applyToStore(store, slug: "visual-app")
        let drafted = try store.show(slug: "visual-app")
        #expect(first.updated == 1)
        #expect(drafted.visuals.count >= 3)
        #expect(drafted.visuals.contains { $0.id == "hero" && $0.status == .planned })
        #expect(drafted.visuals.contains {
            $0.status == .generated && $0.path == "docs/sample.png"
        })
        #expect(!drafted.visuals.contains { ProductCopy.isBlank($0.prompt) })

        let second = try ProductVisualDraftFactory.applyToStore(store, slug: "visual-app")
        #expect(second.updated == 0)
        #expect(second.unchanged == 1)

        let status = try PortfolioIndex(
            productStore: store,
            evaluationStore: EvaluationStore(root: PortfolioPaths.evaluations(root: store.rootDirectory))
        ).status()
        #expect(status.visuals.noPlan == 0)
        #expect(status.visuals.planned >= 2)
        #expect(status.visuals.generated >= 1)
    }

    @Test("markGenerated promotes planned slot and merges screenshotPaths")
    func markGeneratedSlot() throws {
        let store = try temporaryStore()
        var product = try fixture(slug: "mark-app")
        product = try product.replacing(
            Product.Patch(
                surface: .init(
                    screenshotPaths: [],
                    visuals: [
                        ProductVisual(
                            id: "hero",
                            kind: .hero,
                            status: .planned,
                            aspect: "16:9",
                            prompt: "hero prompt"
                        ),
                    ]
                )
            )
        )
        try store.add(product)

        let next = try ProductVisualDraftFactory.markGenerated(
            in: store,
            slug: "mark-app",
            slotID: "hero",
            path: "visuals/mark-app/hero.jpg"
        )
        #expect(next.visuals.first?.status == .generated)
        #expect(next.visuals.first?.path == "visuals/mark-app/hero.jpg")
        #expect(next.screenshotPaths.contains("visuals/mark-app/hero.jpg"))
        #expect(throws: ProductVisualError.self) {
            _ = try ProductVisualDraftFactory.markGenerated(
                on: next,
                slotID: "missing",
                path: "x.png"
            )
        }
    }

    @Test("screenshots field considers generated visual paths")
    func screenshotsMissingUsesVisuals() throws {
        var product = try fixture(slug: "shot-app", readiness: 1)
        product = try product.replacing(
            Product.Patch(
                surface: .init(
                    screenshotPaths: [],
                    visuals: [
                        ProductVisual(
                            id: "s1",
                            kind: .screenshot,
                            status: .generated,
                            aspect: "16:10",
                            prompt: "ui",
                            path: "docs/ui.png"
                        ),
                    ]
                )
            )
        )
        #expect(!ProductField.screenshots.isMissing(in: product))
        #expect(product.hasAnyScreenshotAsset)

        let empty = try product.replacing(
            Product.Patch(
                surface: .init(
                    screenshotPaths: [],
                    visuals: [
                        ProductVisual(
                            id: "hero",
                            kind: .hero,
                            status: .planned,
                            aspect: "16:9",
                            prompt: "hero only"
                        ),
                    ]
                )
            )
        )
        #expect(ProductField.screenshots.isMissing(in: empty))
    }

    @Test("store listing delete and rename lifecycle")
    func storeListingLifecycle() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("listing-test-\(UUID().uuidString)", isDirectory: true)
        let listingStore = StoreListingStore(rootDirectory: tempRoot)
        let product = try fixture(slug: "test-app")
        let listing = StoreListing.seeded(from: product)

        _ = try listingStore.save(listing)
        #expect(listingStore.exists(slug: "test-app"))

        // Rename
        try listingStore.renameListing(from: "test-app", to: "renamed-app")
        #expect(!listingStore.exists(slug: "test-app"))
        #expect(listingStore.exists(slug: "renamed-app"))
        let loaded = try listingStore.loadCurrent(slug: "renamed-app")
        #expect(loaded?.slug == "renamed-app")

        // Delete
        try listingStore.deleteListing(slug: "renamed-app")
        #expect(!listingStore.exists(slug: "renamed-app"))
    }

    private func fixture(
        slug: String = "sample-app",
        role: String = "설명 작성을 빠르게 한다",
        readiness: Int = 4,
        buyerPersona: String = "독립 개발자",
        salesAngle: String = "제품 설명을 한곳에서 관리",
        priceIdea: String = "일회성 19,000원"
    ) throws -> Product {
        try Product(
            names: .init(slug: slug, nameKo: "샘플 앱", nameEn: "Sample App"),
            pitch: .init(
                role: role,
                classification: .productCandidate,
                buyerPersona: buyerPersona,
                salesAngle: salesAngle,
                categories: ["생산성"],
                priceIdea: priceIdea
            ),
            surface: .init(readiness: readiness, screenshotPaths: ["docs/sample.png"])
        )
    }

    private func temporaryStore() throws -> ProductStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("product-showcase-tests-\(UUID().uuidString)", isDirectory: true)
        return try ProductStore(rootDirectory: root)
    }
}
