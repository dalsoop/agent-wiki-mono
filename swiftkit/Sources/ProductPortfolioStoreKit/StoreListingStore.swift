import Foundation
import os

private let logger = Logger(subsystem: "net.ranode.ProductPortfolioKit", category: "store-listing")

public enum StoreListingStoreError: Error, Equatable, LocalizedError, Sendable {
    case notFound(String)
    case versionNotFound(slug: String, versionId: String)
    case invalidSlug(String)
    case imageNotFound(String)
    case unsupportedImage(String)

    public var errorDescription: String? {
        switch self {
        case let .notFound(slug):
            "리스팅이 없습니다: \(slug)"
        case let .versionNotFound(slug, versionId):
            "버전을 찾을 수 없습니다: \(slug) @ \(versionId)"
        case let .invalidSlug(slug):
            "잘못된 slug: \(slug)"
        case let .imageNotFound(path):
            "이미지 없음: \(path)"
        case let .unsupportedImage(path):
            "지원하지 않는 이미지: \(path)"
        }
    }
}

/// `~/.product-portfolio/showcase/listings/<slug>/`
/// - `current.json` 작업본
/// - `versions/<id>.json` 저장 스냅샷 (append-only)
/// - `images/` 업로드 스크린샷·아이콘
public struct StoreListingStore: Sendable {
    public static let allowedImageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "tif", "tiff",
    ]

    public let rootDirectory: URL

    public init(rootDirectory: URL = Self.defaultRootDirectory) {
        self.rootDirectory = rootDirectory.standardizedFileURL
    }

    public static var defaultRootDirectory: URL {
        ShowcasePackageReader.defaultRoot()
            .appendingPathComponent("listings", isDirectory: true)
    }

    public func slugDirectory(slug: String) -> URL {
        rootDirectory.appendingPathComponent(slug, isDirectory: true)
    }

    public func imagesDirectory(slug: String) -> URL {
        slugDirectory(slug: slug).appendingPathComponent("images", isDirectory: true)
    }

    public func currentURL(slug: String) -> URL {
        slugDirectory(slug: slug).appendingPathComponent("current.json")
    }

    public func versionsDirectory(slug: String) -> URL {
        slugDirectory(slug: slug).appendingPathComponent("versions", isDirectory: true)
    }

    public func versionURL(slug: String, versionId: String) -> URL {
        versionsDirectory(slug: slug)
            .appendingPathComponent(versionId)
            .appendingPathExtension("json")
    }

    public func exists(slug: String) -> Bool {
        FileManager.default.fileExists(atPath: currentURL(slug: slug).path)
    }

    /// 디스크 current 로드. 없으면 nil.
    public func loadCurrent(slug: String) throws -> StoreListing? {
        try requireValidSlug(slug)
        let url = currentURL(slug: slug)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try decode(url)
    }

    public func loadCurrentOrThrow(slug: String) throws -> StoreListing {
        guard let listing = try loadCurrent(slug: slug) else {
            throw StoreListingStoreError.notFound(slug)
        }
        return listing
    }

    /// current 가 있으면 그대로, 없으면 Product(+landing) 로 시드한 뒤 저장.
    public func loadOrSeed(
        product: Product,
        landingMarkdown: String? = nil,
        persistSeed: Bool = true
    ) throws -> StoreListing {
        if let existing = try loadCurrent(slug: product.slug) {
            return existing
        }
        var seeded = StoreListing.seeded(from: product, landingMarkdown: landingMarkdown)
        if persistSeed {
            seeded = try save(seeded, note: seeded.note.isEmpty ? "seed" : seeded.note)
        }
        return seeded
    }

    /// 현재 작업본을 저장한다.
    /// - 기존 current 가 내용이 다르면 versions/ 에 스냅샷을 남긴 뒤 덮어쓴다.
    /// - 반환 listing 의 versionId 는 항상 `"current"`.
    @discardableResult
    public func save(_ listing: StoreListing, note: String? = nil) throws -> StoreListing {
        try requireValidSlug(listing.slug)
        let fm = FileManager.default
        let dir = slugDirectory(slug: listing.slug)
        let versionsDir = versionsDirectory(slug: listing.slug)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try fm.createDirectory(at: versionsDir, withIntermediateDirectories: true)

        try archivePreviousIfNeeded(current: listing)

        var next = listing
        next.versionId = "current"
        next.savedAt = StoreListing.nowISO8601()
        if let note {
            next.note = note
        }
        try write(next, to: currentURL(slug: listing.slug))
        return next
    }

    private func archivePreviousIfNeeded(current: StoreListing) throws {
        guard let previous = try loadCurrent(slug: current.slug),
              contentDiffers(previous, current) else { return }
        var snapshot = previous
        snapshot.versionId = StoreListing.makeVersionId()
        if snapshot.savedAt.isEmpty {
            snapshot.savedAt = StoreListing.nowISO8601()
        }
        try write(snapshot, to: versionURL(slug: current.slug, versionId: snapshot.versionId))
    }

    public func listVersions(slug: String) throws -> [StoreListingVersionInfo] {
        try requireValidSlug(slug)
        let dir = versionsDirectory(slug: slug)
        guard FileManager.default.fileExists(atPath: dir.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "json" }

        var infos: [StoreListingVersionInfo] = []
        for url in urls {
            let listing = try decode(url)
            infos.append(StoreListingVersionInfo(from: listing))
        }
        return infos.sorted { $0.versionId > $1.versionId }
    }

    public func loadVersion(slug: String, versionId: String) throws -> StoreListing {
        try requireValidSlug(slug)
        if versionId == "current" {
            return try loadCurrentOrThrow(slug: slug)
        }
        let url = versionURL(slug: slug, versionId: versionId)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw StoreListingStoreError.versionNotFound(slug: slug, versionId: versionId)
        }
        return try decode(url)
    }

    /// 스냅샷을 current 로 복원. 복원 전 current 는 versions 에 남긴다.
    @discardableResult
    public func restore(slug: String, versionId: String, note: String? = nil) throws -> StoreListing {
        let snapshot = try loadVersion(slug: slug, versionId: versionId)
        var restored = snapshot
        restored.versionId = "current"
        restored.note = note ?? "restored-from-\(versionId)"
        return try save(restored, note: restored.note)
    }

    public func listSlugs() throws -> [String] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: rootDirectory.path) else { return [] }
        let urls = try fm.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return urls
            .filter { url in
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
                    return false
                }
                return fm.fileExists(atPath: currentURL(slug: url.lastPathComponent).path)
            }
            .map(\.lastPathComponent)
            .sorted()
    }

    // MARK: - Images

    /// 외부 파일을 listings/<slug>/images/ 로 복사하고 listing.images 에 추가 후 저장.
    @discardableResult
    public func importImages(
        into listing: StoreListing,
        from sourceURLs: [URL],
        platform: StoreListingPlatform? = nil,
        kind: String = "screenshot",
        note: String? = "image-upload"
    ) throws -> StoreListing {
        try requireValidSlug(listing.slug)
        let fm = FileManager.default
        let imagesDir = imagesDirectory(slug: listing.slug)
        try fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)

        var next = listing
        if kind == "icon" {
            // 아이콘은 1장만 — 기존 icon 제거(파일은 유지, 메타만 교체 가능)
            next.images.removeAll { $0.kind == "icon" }
        }

        for source in sourceURLs {
            let standardized = source.standardizedFileURL
            guard fm.fileExists(atPath: standardized.path) else {
                throw StoreListingStoreError.imageNotFound(standardized.path)
            }
            let ext = standardized.pathExtension.lowercased()
            guard Self.allowedImageExtensions.contains(ext) else {
                throw StoreListingStoreError.unsupportedImage(standardized.path)
            }

            let id = UUID().uuidString.lowercased()
            let platformTag = platform.map { "-\($0.rawValue)" } ?? ""
            let kindTag = kind == "icon" ? "-icon" : ""
            let destName = "\(id.prefix(8))\(platformTag)\(kindTag).\(ext)"
            let dest = imagesDir.appendingPathComponent(destName)
            if fm.fileExists(atPath: dest.path) {
                try fm.removeItem(at: dest)
            }
            try fm.copyItem(at: standardized, to: dest)

            next.images.append(
                StoreListingImage(
                    id: id,
                    path: dest.path,
                    platform: platform?.rawValue,
                    kind: kind,
                    originalName: standardized.lastPathComponent
                )
            )
        }

        return try save(next, note: note)
    }

    /// id 또는 path 로 이미지 메타 제거. `deleteFile` 이면 images/ 파일도 삭제.
    @discardableResult
    public func removeImage(
        from listing: StoreListing,
        idOrPath: String,
        deleteFile: Bool = true,
        note: String? = "image-remove"
    ) throws -> StoreListing {
        var next = listing
        let before = next.images
        next.images.removeAll { image in
            if image.id == idOrPath || image.path == idOrPath { return true }
            return image.path.hasSuffix("/\(idOrPath)")
        }
        guard next.images.count != before.count else {
            throw StoreListingStoreError.imageNotFound(idOrPath)
        }
        if deleteFile {
            cleanupRemovedImageFiles(before: before, remaining: next.images, slug: listing.slug)
        }
        return try save(next, note: note)
    }

    private func cleanupRemovedImageFiles(before: [StoreListingImage], remaining: [StoreListingImage], slug: String) {
        let remainingIds = Set(remaining.map(\.id))
        let removed = before.filter { !remainingIds.contains($0.id) }
        for image in removed {
            let url = URL(fileURLWithPath: image.path)
            guard FileManager.default.fileExists(atPath: url.path),
                  url.path.contains("/listings/\(slug)/images/") else { continue }
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                logger.error("failed to remove image file: \(error.localizedDescription)")
            }
        }
    }

    /// 순서를 id 배열 기준으로 재배치 (없는 id 는 뒤에 유지).
    @discardableResult
    public func reorderImages(
        of listing: StoreListing,
        orderedIds: [String],
        note: String? = "image-reorder"
    ) throws -> StoreListing {
        var next = listing
        var byId = Dictionary(uniqueKeysWithValues: next.images.map { ($0.id, $0) })
        var ordered: [StoreListingImage] = []
        for id in orderedIds {
            if let image = byId.removeValue(forKey: id) {
                ordered.append(image)
            }
        }
        ordered.append(contentsOf: byId.values)
        next.images = ordered
        return try save(next, note: note)
    }

    public func deleteListing(slug: String) throws {
        try requireValidSlug(slug)
        let dir = slugDirectory(slug: slug)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
    }

    public func renameListing(from oldSlug: String, to newSlug: String) throws {
        try requireValidSlug(oldSlug)
        try requireValidSlug(newSlug)
        let oldDir = slugDirectory(slug: oldSlug)
        let newDir = slugDirectory(slug: newSlug)
        guard FileManager.default.fileExists(atPath: oldDir.path) else { return }
        if FileManager.default.fileExists(atPath: newDir.path) {
            try FileManager.default.removeItem(at: newDir)
        }
        try FileManager.default.moveItem(at: oldDir, to: newDir)
        if var current = try loadCurrent(slug: newSlug) {
            current.slug = newSlug
            try write(current, to: currentURL(slug: newSlug))
        }
    }

    // MARK: - Private

    private func requireValidSlug(_ slug: String) throws {
        guard Product.isValidSlug(slug) else {
            throw StoreListingStoreError.invalidSlug(slug)
        }
    }

    private func contentDiffers(_ a: StoreListing, _ b: StoreListing) -> Bool {
        let fieldsA: [AnyHashable] = [
            a.name, a.subtitle, a.description, a.promotionalText,
            a.whatsNew, a.keywords, a.category, a.priceLabel, a.primaryCTA
        ]
        let fieldsB: [AnyHashable] = [
            b.name, b.subtitle, b.description, b.promotionalText,
            b.whatsNew, b.keywords, b.category, b.priceLabel, b.primaryCTA
        ]
        return fieldsA != fieldsB || a.images != b.images
    }

    private func decode(_ url: URL) throws -> StoreListing {
        try JSONDecoder().decode(StoreListing.self, from: Data(contentsOf: url))
    }

    private func write(_ listing: StoreListing, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(listing)
        data.append(0x0A)
        try data.write(to: url, options: .atomic)
    }
}
