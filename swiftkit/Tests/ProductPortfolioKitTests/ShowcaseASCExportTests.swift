import Foundation
import ProductPortfolioKit
import Testing

@Suite("ShowcaseASCExport")
struct ShowcaseASCExportTests {
    @Test func export_writesIndexAndProductJSON_fromListingCopy() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("asc-export-test-\(UUID().uuidString)", isDirectory: true)
        let packageRoot = root.appendingPathComponent("showcase", isDirectory: true)
        let listingsRoot = packageRoot.appendingPathComponent("listings", isDirectory: true)
        let outRoot = packageRoot.appendingPathComponent("asc-export", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: listingsRoot, withIntermediateDirectories: true)

        // Real image file used by preferredShots via listing.images
        let imgDir = listingsRoot
            .appendingPathComponent("demo-app", isDirectory: true)
            .appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: imgDir, withIntermediateDirectories: true)
        let macShot = imgDir.appendingPathComponent("mac.png")
        let iosShot = imgDir.appendingPathComponent("ios.png")
        try Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]).write(to: macShot)
        try Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]).write(to: iosShot)

        let listing = StoreListing(
            identity: .init(slug: "demo-app", note: "test"),
            copy: .init(
                name: "데모앱",
                subtitle: "한 줄 부제",
                description: "ASC 설명 본문입니다.",
                promotionalText: "프로모",
                whatsNew: "새 기능"
            ),
            merch: .init(
                keywords: "데모, 테스트",
                category: "생산성",
                priceLabel: "무료",
                primaryCTA: "받기",
                images: [
                    StoreListingImage(
                        path: macShot.path,
                        platform: "mac",
                        kind: "screenshot",
                        originalName: "mac.png"
                    ),
                    StoreListingImage(
                        path: iosShot.path,
                        platform: "ios",
                        kind: "screenshot",
                        originalName: "ios.png"
                    ),
                ]
            )
        )
        let listingStore = StoreListingStore(rootDirectory: listingsRoot)
        _ = try listingStore.save(listing, note: "seed")

        let product = try Product(
            names: .init(slug: "demo-app", nameKo: "데모앱", nameEn: "Demo"),
            pitch: .init(
                role: "역할",
                classification: .productCandidate,
                buyerPersona: "사용자",
                salesAngle: "판매각",
                categories: ["생산성"],
                priceIdea: "무료"
            ),
            surface: .init(readiness: 5, screenshotPaths: [])
        )

        let result = try ShowcaseASCExport.export(
            products: [product],
            packageRoot: packageRoot,
            outputRoot: outRoot,
            listingStore: listingStore
        )

        #expect(result.count == 1)
        #expect(FileManager.default.fileExists(atPath: result.indexPath))
        let productJSON = outRoot.appendingPathComponent("demo-app.json")
        #expect(FileManager.default.fileExists(atPath: productJSON.path))
        #expect(FileManager.default.fileExists(atPath: outRoot.appendingPathComponent("demo-app.md").path))
        #expect(FileManager.default.fileExists(atPath: outRoot.appendingPathComponent("README.md").path))

        let data = try Data(contentsOf: productJSON)
        let decoded = try JSONDecoder().decode(ShowcaseASCRecord.self, from: data)
        #expect(decoded.slug == "demo-app")
        #expect(decoded.name == "데모앱")
        #expect(decoded.description == "ASC 설명 본문입니다.")
        #expect(decoded.subtitle == "한 줄 부제")
        #expect(decoded.macScreenshotPaths.contains(macShot.path))
        #expect(decoded.iosScreenshotPaths.contains(iosShot.path))
        #expect(!decoded.macScreenshotPaths.isEmpty)
        #expect(!decoded.iosScreenshotPaths.isEmpty)

        // index is array of records
        let indexData = try Data(contentsOf: URL(fileURLWithPath: result.indexPath))
        let index = try JSONDecoder().decode([ShowcaseASCRecord].self, from: indexData)
        #expect(index.count == 1)
        #expect(index[0].name == "데모앱")
    }

    @Test func record_usesListingFieldsOverProductDefaults() throws {
        let product = try Product(
            names: .init(slug: "pref-app", nameKo: "제품이름", nameEn: "Product"),
            pitch: .init(
                role: "역할 기본",
                classification: .productCandidate,
                buyerPersona: "페르소나",
                salesAngle: "판매 기본",
                categories: ["도구"],
                priceIdea: "월 1,000원"
            ),
            surface: .init(readiness: 5, screenshotPaths: [])
        )
        let listing = StoreListing(
            identity: .init(slug: "pref-app"),
            copy: .init(
                name: "리스팅이름",
                subtitle: "리스팅 부제",
                description: "리스팅 설명",
                promotionalText: "리스팅 프로모"
            ),
            merch: .init(
                category: "생산성",
                priceLabel: "일회성 9,900원",
                primaryCTA: "구매"
            )
        )
        let rec = ShowcaseASCExport.record(product: product, listing: listing)
        #expect(rec.name == "리스팅이름")
        #expect(rec.subtitle == "리스팅 부제")
        #expect(rec.description == "리스팅 설명")
        #expect(rec.primaryCategory == "생산성")
        #expect(rec.priceLabel == "일회성 9,900원")
        #expect(rec.primaryCTA == "구매")
    }
}
