import Foundation

/// 상품 이미지 개별 아이템 모델
public struct ProductImageItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var fileName: String
    public var caption: String
    public var sortOrder: Int
    public var isRepresentative: Bool

    public init(
        id: String = UUID().uuidString,
        fileName: String,
        caption: String = "",
        sortOrder: Int = 0,
        isRepresentative: Bool = false
    ) {
        self.id = id
        self.fileName = fileName
        self.caption = caption
        self.sortOrder = sortOrder
        self.isRepresentative = isRepresentative
    }
}

/// 상품 미디어 갤러리 (대표 이미지 1장 + 추가 이미지 배열 최대 9장)
public struct ProductMediaGallery: Codable, Sendable, Equatable {
    /// 네이버 스마트스토어 권장 추가 이미지 최대 개수
    public static let maxAdditionalImages: Int = 9

    /// 대표 이미지 (필수 또는 기본)
    public var representativeImage: ProductImageItem?

    /// 추가 이미지 배열 (네이버 스마트스토어 규격: 최대 9장)
    public var additionalImages: [ProductImageItem]

    public init(
        representativeImage: ProductImageItem? = nil,
        additionalImages: [ProductImageItem] = []
    ) {
        self.representativeImage = representativeImage
        self.additionalImages = additionalImages
    }

    /// 파일명 목록으로부터 갤러리 초기화
    public init(representativeFileName: String?, additionalFileNames: [String] = []) {
        if let rep = representativeFileName, !rep.isEmpty {
            self.representativeImage = ProductImageItem(fileName: rep, isRepresentative: true)
        } else {
            self.representativeImage = nil
        }
        self.additionalImages = additionalFileNames.enumerated().map { idx, name in
            ProductImageItem(fileName: name, sortOrder: idx, isRepresentative: false)
        }
    }

    /// 모든 이미지 목록 (대표 이미지가 맨 앞)
    public var allImages: [ProductImageItem] {
        var list: [ProductImageItem] = []
        if let rep = representativeImage {
            list.append(rep)
        }
        list.append(contentsOf: additionalImages)
        return list
    }

    /// 추가 이미지를 더 등록할 수 있는지 여부
    public var canAddMoreAdditionalImages: Bool {
        additionalImages.count < Self.maxAdditionalImages
    }

    /// 추가 이미지 등록
    @discardableResult
    public mutating func addAdditionalImage(fileName: String, caption: String = "") -> Bool {
        guard canAddMoreAdditionalImages else { return false }
        let item = ProductImageItem(
            fileName: fileName,
            caption: caption,
            sortOrder: additionalImages.count,
            isRepresentative: false
        )
        additionalImages.append(item)
        return true
    }

    /// 추가 이미지 삭제
    public mutating func removeAdditionalImage(id: String) {
        additionalImages.removeAll { $0.id == id }
        reindexSortOrders()
    }

    /// 추가 이미지 순서 변경 (Swap)
    public mutating func moveAdditionalImage(fromIndex: Int, toIndex: Int) {
        guard additionalImages.indices.contains(fromIndex),
              additionalImages.indices.contains(toIndex) else { return }
        let item = additionalImages.remove(at: fromIndex)
        additionalImages.insert(item, at: toIndex)
        reindexSortOrders()
    }

    /// 대표 이미지 설정
    public mutating func setRepresentativeImage(fileName: String, caption: String = "") {
        self.representativeImage = ProductImageItem(
            fileName: fileName,
            caption: caption,
            sortOrder: 0,
            isRepresentative: true
        )
    }

    /// 추가 이미지 중 하나를 대표 이미지로 승격
    public mutating func promoteToRepresentative(id: String) {
        guard let index = additionalImages.firstIndex(where: { $0.id == id }) else { return }
        let target = additionalImages.remove(at: index)
        let oldRepresentative = self.representativeImage

        self.representativeImage = ProductImageItem(
            id: target.id,
            fileName: target.fileName,
            caption: target.caption,
            sortOrder: 0,
            isRepresentative: true
        )

        if let old = oldRepresentative {
            var restored = old
            restored.isRepresentative = false
            additionalImages.insert(restored, at: index)
        }
        reindexSortOrders()
    }

    /// 순서 인덱스 재정렬
    private mutating func reindexSortOrders() {
        for idx in additionalImages.indices {
            additionalImages[idx].sortOrder = idx
        }
    }
}
