import Testing
import Foundation
@testable import StoreAssetKit

@Suite("StoreAssetKit Product Media & Detail Page Tests")
struct ProductMediaAssetTests {

    @Test("ProductMediaGallery basic operations")
    func testGalleryOperations() {
        var gallery = ProductMediaGallery(representativeFileName: "rep.jpg", additionalFileNames: ["sub1.jpg", "sub2.jpg"])
        #expect(gallery.representativeImage?.fileName == "rep.jpg")
        #expect(gallery.additionalImages.count == 2)
        #expect(gallery.allImages.count == 3)

        // 추가
        let added = gallery.addAdditionalImage(fileName: "sub3.jpg", caption: "3번컷")
        #expect(added)
        #expect(gallery.additionalImages.count == 3)
        #expect(gallery.additionalImages.last?.caption == "3번컷")

        // 승격
        if let sub1 = gallery.additionalImages.first {
            gallery.promoteToRepresentative(id: sub1.id)
            #expect(gallery.representativeImage?.fileName == "sub1.jpg")
            #expect(gallery.additionalImages.contains(where: { $0.fileName == "rep.jpg" }))
        }
    }

    @Test("ProductDetailPage HTML rendering")
    func testDetailPageHtmlRender() {
        let detail = ProductDetailPage.standardDefaults(productName: "프리미엄 린넨 셔츠", manufacturer: "구조 ai", origin: "국산")
        let html = detail.renderHTML(imageUrls: ["https://example.com/img1.jpg", "https://example.com/img2.jpg"])

        #expect(html.contains("프리미엄 린넨 셔츠"))
        #expect(html.contains("구조 ai"))
        #expect(html.contains("https://example.com/img1.jpg"))
        #expect(html.contains("상품 정보 제공 고시"))
    }

    @Test("ProductLifecycleStage transitions and properties")
    func testLifecycleTransitions() {
        let onSale = ProductLifecycleStage.onSale
        #expect(onSale.isSalable)
        #expect(onSale.isOnlineActive)
        #expect(!onSale.isDisposed)
        #expect(onSale.canTransition(to: .soldOut))
        #expect(onSale.canTransition(to: .reserved))
        #expect(onSale.canTransition(to: .disposed))

        let disposed = ProductLifecycleStage.disposed
        #expect(!disposed.isSalable)
        #expect(disposed.isDisposed)
        #expect(disposed.titleKo == "처분됨(폐기)")

        let soldOut = ProductLifecycleStage.soldOut
        #expect(!soldOut.isSalable)
        #expect(soldOut.canTransition(to: .onSale)) // 재입고

        let record = ProductDisposalRecord(
            reason: .damaged,
            quantity: 2,
            lossAmount: 28000,
            note: "배송 파손"
        )
        #expect(record.reason == .damaged)
        #expect(record.quantity == 2)
        #expect(record.lossAmount == 28000)
    }
}
