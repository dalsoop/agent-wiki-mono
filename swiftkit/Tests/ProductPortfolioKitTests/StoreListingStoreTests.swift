import Foundation
import ProductPortfolioKit
import Testing

@Suite("StoreListingStore")
struct StoreListingStoreTests {
    @Test func saveCreatesCurrentAndVersionsOnEdit() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("listing-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StoreListingStore(rootDirectory: root)

        var listing = StoreListing(
            identity: .init(slug: "demo-app"),
            copy: .init(name: "데모", subtitle: "한 줄", description: "설명")
        )
        listing = try store.save(listing, note: "v1")
        #expect(listing.versionId == "current")
        #expect(try store.listVersions(slug: "demo-app").isEmpty)

        listing.description = "설명 수정"
        listing = try store.save(listing, note: "v2")
        let versions = try store.listVersions(slug: "demo-app")
        #expect(versions.count == 1)
        #expect(versions[0].note == "v1" || !versions[0].note.isEmpty)

        let restored = try store.restore(slug: "demo-app", versionId: versions[0].versionId)
        #expect(restored.description == "설명")
        #expect(try store.listVersions(slug: "demo-app").count == 2)
    }

    @Test func seedFromProduct() throws {
        let product = try Product(
            names: .init(slug: "seed-app", nameKo: "시드", nameEn: "Seed"),
            pitch: .init(
                role: "역할 문구",
                classification: .productCandidate,
                buyerPersona: "페르소나",
                salesAngle: "판매각 한 줄",
                categories: ["생산성"],
                priceIdea: "월 4,900원"
            ),
            surface: .init(readiness: 5, screenshotPaths: [])
        )
        let listing = StoreListing.seeded(from: product)
        #expect(listing.name == "시드")
        #expect(listing.subtitle == "판매각 한 줄")
        #expect(listing.primaryCTA == "구독")
        #expect(listing.category == "생산성")
    }

    @Test func importAndRemoveImages() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("listing-img-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StoreListingStore(rootDirectory: root)

        var listing = try store.save(
            StoreListing(identity: .init(slug: "img-app"), copy: .init(name: "이미지")),
            note: "base"
        )

        let src = root.appendingPathComponent("src.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: src)

        listing = try store.importImages(
            into: listing,
            from: [src],
            platform: .ios,
            kind: "screenshot"
        )
        #expect(listing.images.count == 1)
        #expect(listing.images[0].platform == "ios")
        #expect(FileManager.default.fileExists(atPath: listing.images[0].path))
        // ios 태그 샷: iPhone 미리보기에만, Mac 필터에는 제외
        #expect(listing.screenshotPaths(for: .ios).count == 1)
        #expect(listing.screenshotPaths(for: .mac).isEmpty)

        let id = listing.images[0].id
        listing = try store.removeImage(from: listing, idOrPath: id)
        #expect(listing.images.isEmpty)
    }
}
