import Foundation
import LocalizationKit

public final class LibraryController: Sendable {
    private let api: GujoAPI
    private let installations: InstallationStore
    private let productsDir: URL
    private let downloadEngine: DownloadEngine
    private let registeredFolderIds: Set<UUID>?

    public init(
        api: GujoAPI,
        installations: InstallationStore,
        productsDir: URL = AppPaths.productsDir,
        downloadEngine: DownloadEngine = DownloadEngine(),
        registeredFolderIds: Set<UUID>? = nil
    ) {
        self.api = api
        self.installations = installations
        self.productsDir = productsDir
        self.downloadEngine = downloadEngine
        self.registeredFolderIds = registeredFolderIds
    }

    /// Cached copy of the shared product-content CSS. Fetched once, reused for every
    /// thumbnail/detail render so the gujo styles (incl. @keyframes animations) apply.
    private let cssCache = ContentCSSCache()
    private func contentCss() async -> String {
        await cssCache.value { [api] in
            do {
                return try await api.productContentCss()
            } catch {
                FileHandle.standardError.write(
                    Data("warning: product content CSS fetch failed: \(error)\n".utf8))
                return ""
            }
        }
    }

    public func loadLibrary() async throws -> [LibraryRow] {
        let items = try await api.library()
        return items.map { LibraryRow(item: $0, status: installations.aggregateStatus(for: $0, inFolderIds: registeredFolderIds)) }
    }

    /// Downloads the bundle and unzips it into `<folder.path>/<slug>/`, then records the install
    /// keyed by (folder, product). Reinstalling overwrites the existing subdir.
    public func install(_ item: LibraryItem, into folder: Folder) async throws {
        guard let bundle = item.bundle, bundle.available else {
            throw DownloadError(message: CLILocalization.format("LibraryController.message", item.product.id))
        }
        let slug = ProgramSlug.make(id: item.product.id, name: item.product.name)
        let folderURL = URL(fileURLWithPath: folder.path, isDirectory: true).standardizedFileURL
        let dest = folderURL.appendingPathComponent(slug, isDirectory: true).standardizedFileURL
        guard dest.path.hasPrefix(folderURL.path + "/") else {
            throw DownloadError(message: CLILocalization.format("LibraryController.message-2", item.product.id))
        }
        let zip = try await api.downloadBundle(id: item.product.id)
        defer {
            do {
                try FileManager.default.removeItem(at: zip)
            } catch {
                FileHandle.standardError.write(
                    Data("warning: install zip cleanup failed: \(error)\n".utf8))
            }
        }
        guard let expected = item.bundle?.sha256?.lowercased(), !expected.isEmpty else {
            throw DownloadError(message: CLILocalization.format("LibraryController.message-3", item.product.id))
        }
        let actual = try downloadEngine.sha256Hex(of: zip)
        guard actual == expected else {
            throw DownloadError(message: CLILocalization.format("LibraryController.message-4", item.product.id))
        }
        try await downloadEngine.unzip(zip, into: dest)
        try installations.record(Installation(
            folderId: folder.id,
            productId: item.product.id,
            slug: slug,
            name: item.product.name,
            bundleSha256: item.bundle?.sha256,
            installedAt: Date(),
            sizeBytes: item.bundle?.size ?? 0
        ))
    }

    /// Downloads detail_html + referenced content assets into products/<id>/, rewrites to local
    /// relative URLs, writes detail.html, and returns its URL for the WebView to load.
    public func renderDetail(for item: LibraryItem) async throws -> URL {
        let detail = try await api.productDetail(id: item.product.id)
        let html = detail.detail_html ?? LibraryRenderChrome.emptyDetailHTML
        let dir = productsDir.appendingPathComponent(String(item.product.id), isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for path in DetailRenderer.extractAssetPaths(from: html) {
            let data = try await api.contentAsset(id: item.product.id, path: path)
            let assetURL = dir.appendingPathComponent(path).standardizedFileURL
            guard assetURL.path.hasPrefix(dir.standardizedFileURL.path + "/") else {
                throw DownloadError(message: "unsafe asset path: \(path)")
            }
            try FileManager.default.createDirectory(at: assetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: assetURL, options: .atomic)
        }
        let rewritten = DetailRenderer.rewrite(html: html)
        let css = await contentCss()
        // The product CSS is light-only; without a dark override the detail pane
        // renders as a white sheet under the app's dark chrome. Placed after the
        // product CSS so the body colors win in dark mode.
        let darkCss = LibraryRenderChrome.darkCss
        let page = "<!doctype html><meta charset=\"utf-8\"><meta name=\"color-scheme\" content=\"light dark\"><style>\(css)</style><style>\(darkCss)</style><body>\(rewritten)</body>"
        let detailURL = dir.appendingPathComponent("detail.html")
        try page.write(to: detailURL, atomically: true, encoding: .utf8)
        return detailURL
    }

    /// Renders an item's `thumbnail_html` (if any) the same way as `renderDetail`: downloads the
    /// referenced content assets into products/<id>/, rewrites to local relative URLs, writes
    /// thumb.html, and returns its URL. Returns nil when there is no thumbnail HTML.
    public func renderThumbnail(for item: LibraryItem) async throws -> URL? {
        guard let html = item.thumbnail_html, !html.isEmpty else { return nil }
        let dir = productsDir.appendingPathComponent(String(item.product.id), isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for path in DetailRenderer.extractAssetPaths(from: html) {
            let data = try await api.contentAsset(id: item.product.id, path: path)
            let assetURL = dir.appendingPathComponent(path).standardizedFileURL
            guard assetURL.path.hasPrefix(dir.standardizedFileURL.path + "/") else {
                throw DownloadError(message: "unsafe asset path: \(path)")
            }
            try FileManager.default.createDirectory(at: assetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: assetURL, options: .atomic)
        }
        let rewritten = DetailRenderer.rewrite(html: html)
        let css = await contentCss()
        // Scale the whole thumbnail to fit the box (contain) so it's fully visible without scrolling.
        let layoutCss = LibraryRenderChrome.thumbnailLayoutCss
        let fitJs = LibraryRenderChrome.thumbnailFitJavaScript
        let page = "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><style>\(css)</style><style>\(layoutCss)</style><body><div class=\"gpd2-mainimg-thumb-html\" id=\"thumbroot\">\(rewritten)</div><script>\(fitJs)</script></body>"
        let thumbURL = dir.appendingPathComponent("thumb.html")
        try page.write(to: thumbURL, atomically: true, encoding: .utf8)
        return thumbURL
    }

    /// Fetches the AI install-prompt markdown for a product (the text the user pastes into
    /// Claude/Codex to auto-install it). Resolves `ai_prompt_path` from the detail endpoint,
    /// then downloads it via the content-asset endpoint. Returns nil when no prompt is exposed.
    public func installPrompt(for item: LibraryItem) async throws -> String? {
        let detail = try await api.productDetail(id: item.product.id)
        guard let path = detail.ai_prompt_path, !path.isEmpty else { return nil }
        let data = try await api.contentAsset(id: item.product.id, path: path)
        return String(decoding: data, as: UTF8.self)
    }

    /// Fetches the raw bytes of the product's hero image via the content-asset endpoint.
    /// Returns nil when the item has no `hero_path`.
    public func heroImageData(for item: LibraryItem) async throws -> Data? {
        guard let path = item.hero_path, !path.isEmpty else { return nil }
        return try await api.contentAsset(id: item.product.id, path: path)
    }

    /// 갤러리 스크린샷처럼 임의 content asset 바이트를 받는다.
    /// 경로가 비면 nil.
    public func assetImageData(for item: LibraryItem, path: String) async throws -> Data? {
        guard !path.isEmpty else { return nil }
        return try await api.contentAsset(id: item.product.id, path: path)
    }

    /// 사용법·아키텍처 문서처럼 content asset 을 UTF-8 텍스트로 받는다.
    /// 경로가 비면 nil.
    public func assetText(for item: LibraryItem, path: String) async throws -> String? {
        guard !path.isEmpty else { return nil }
        let data = try await api.contentAsset(id: item.product.id, path: path)
        return String(decoding: data, as: UTF8.self)
    }

    /// Fetches the product detail response (detail_html, ai_prompt_path, gallery) for an item.
    public func productDetail(for item: LibraryItem) async throws -> ProductDetailResponse {
        try await api.productDetail(id: item.product.id)
    }

    /// Removes the installed subdir for (folder, product) and the install record. Does NOT touch the
    /// user's registered folder itself.
    public func remove(from folder: Folder, productId: Int) throws {
        try InstallationManager(installations: installations).remove(from: folder, productId: productId)
    }
}

/// 공유 CSS 를 한 번만 받아 재사용하는 메모 캐시.
///
/// 예전엔 `LibraryController` 의 `private var cachedCss` 였다. 확인과 저장 사이에
/// `await` 이 끼어 있어서 상세와 썸네일 렌더가 겹치면 같은 CSS 를 두 번 받아오고
/// 저장까지 경쟁했다 — 그래서 컨트롤러가 `@unchecked Sendable` 이어야 했다.
/// 캐시만 actor 로 떼면 컨트롤러는 전부 `let` 이 되어 검사 없이 Sendable 이고,
/// 받아오는 작업 자체를 붙들어 두므로 겹친 호출이 요청 하나를 함께 기다린다.
private actor ContentCSSCache {
    private var inFlight: Task<String, Never>?

    func value(fetch: @escaping @Sendable () async -> String) async -> String {
        if let t = inFlight { return await t.value }
        let t = Task { await fetch() }
        inFlight = t
        return await t.value
    }
}
