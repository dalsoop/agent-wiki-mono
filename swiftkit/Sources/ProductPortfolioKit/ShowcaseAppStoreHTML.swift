import Foundation

public struct ShowcaseAppStoreHTMLResult: Codable, Equatable, Sendable {
    public let indexPath: String
    public let productPages: [String]
    public let count: Int
    public let platform: String

    public init(indexPath: String, productPages: [String], count: Int, platform: String) {
        self.indexPath = indexPath
        self.productPages = productPages
        self.count = count
        self.platform = platform
    }
}

/// 앱스토어 목록 목업 HTML (로컬 파일).
/// 카피는 `StoreListing`(있으면) → Product 시드 순으로 채운다.
public enum ShowcaseAppStoreHTML {
    public static func preferredShots(
        for product: Product,
        platform: StoreListingPlatform = .mac,
        listing: StoreListing? = nil,
        limit: Int = 8
    ) -> [URL] {
        // 리스팅에 업로드한 샷이 있으면 그게 1순위.
        if let listing {
            let uploaded = ShowcasePackageReader.existingImageURLs(
                from: listing.screenshotPaths(for: platform)
            )
            if !uploaded.isEmpty {
                return Array(uploaded.prefix(limit))
            }
        }
        let urls = ShowcasePackageReader.displayableImageURLs(for: product)
        return urls.sorted { lhs, rhs in
            let l = score(path: lhs.path, platform: platform)
            let r = score(path: rhs.path, platform: platform)
            if l != r { return l > r }
            return lhs.lastPathComponent < rhs.lastPathComponent
        }
        .prefix(limit)
        .map { $0 }
    }

    private static func score(path: String, platform: StoreListingPlatform) -> Int {
        let lower = path.lowercased()
        var value = 0
        if lower.contains("/store-assets/out/") { value += 50 }
        if lower.contains("hero") { value += 30 }
        if lower.contains("appstore") { value += 25 }
        if lower.contains("detail") { value += 18 }
        if lower.contains("thumbnail") { value += 10 }
        if lower.hasSuffix(".png") { value += 3 }
        if lower.contains("demo") { value -= 5 }
        switch platform {
        case .ios:
            if lower.contains("iphone") || lower.contains("ios") || lower.contains("mobile") {
                value += 40
            }
            if lower.contains("9x16") || lower.contains("9-16") || lower.contains("portrait") {
                value += 20
            }
        case .mac:
            if lower.contains("mac") || lower.contains("desktop") {
                value += 15
            }
        }
        return value
    }

    /// packageRoot/appstore-html[/ios]/ 아래 index + 제품 페이지 생성.
    public static func export(
        products: [Product],
        packageRoot: URL = ShowcasePackageReader.defaultRoot(),
        platform: StoreListingPlatform = .mac,
        listingStore: StoreListingStore? = nil
    ) throws -> ShowcaseAppStoreHTMLResult {
        let folderName = platform == .ios ? "appstore-html-ios" : "appstore-html"
        let root = packageRoot.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let listings = listingStore ?? StoreListingStore(
            rootDirectory: packageRoot.appendingPathComponent("listings", isDirectory: true)
        )

        var pages: [String] = []
        var resolved: [(Product, StoreListing)] = []
        for product in products {
            let landing = ShowcasePackageReader.landingMarkdown(
                slug: product.slug,
                root: packageRoot
            )
            let listing = try listings.loadOrSeed(
                product: product,
                landingMarkdown: landing,
                persistSeed: false
            )
            resolved.append((product, listing))
            let pageURL = try writeProductPage(
                product: product,
                listing: listing,
                platform: platform,
                under: root
            )
            pages.append(pageURL.path)
        }
        let indexURL = root.appendingPathComponent("index.html")
        try indexHTML(items: resolved, platform: platform)
            .write(to: indexURL, atomically: true, encoding: .utf8)
        return ShowcaseAppStoreHTMLResult(
            indexPath: indexURL.path,
            productPages: pages,
            count: products.count,
            platform: platform.rawValue
        )
    }

    private static func writeProductPage(
        product: Product,
        listing: StoreListing,
        platform: StoreListingPlatform,
        under root: URL
    ) throws -> URL {
        let dir = root.appendingPathComponent(product.slug, isDirectory: true)
        let shotsDir = dir.appendingPathComponent("shots", isDirectory: true)
        try FileManager.default.createDirectory(at: shotsDir, withIntermediateDirectories: true)

        let sources = preferredShots(for: product, platform: platform, listing: listing)
        var relativeShots: [String] = []
        for (index, source) in sources.enumerated() {
            let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension
            let name = String(format: "%02d.%@", index + 1, ext)
            let dest = shotsDir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: source, to: dest)
            relativeShots.append("shots/\(name)")
        }

        let html = productHTML(
            product: product,
            listing: listing,
            platform: platform,
            shotRelativePaths: relativeShots
        )
        let page = dir.appendingPathComponent("index.html")
        try html.write(to: page, atomically: true, encoding: .utf8)
        return page
    }

    private static func esc(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func indexHTML(
        items: [(Product, StoreListing)],
        platform: StoreListingPlatform
    ) -> String {
        let cards = items.map { product, listing -> String in
            let name = listing.name.isEmpty
                ? (product.nameKo.isEmpty ? product.slug : product.nameKo)
                : listing.name
            let sub = listing.subtitle.isEmpty
                ? (product.salesAngle.isEmpty ? product.role : product.salesAngle)
                : listing.subtitle
            let price = listing.priceLabel.isEmpty ? product.priceIdea : listing.priceLabel
            return """
            <a class="card" href="\(esc(product.slug))/index.html">
              <div class="icon">\(esc(String(name.prefix(1))))</div>
              <div>
                <div class="name">\(esc(name))</div>
                <div class="sub">\(esc(sub))</div>
                <div class="meta">r=\(product.readiness) · \(esc(price))</div>
              </div>
            </a>
            """
        }.joined(separator: "\n")

        let title = platform == .ios ? "App Store (iPhone) 미리보기 목록" : "Mac App Store 미리보기 목록"
        return """
        <!doctype html>
        <html lang="ko">
        <head>
          <meta charset="utf-8"/>
          <meta name="viewport" content="width=device-width, initial-scale=1"/>
          <title>\(esc(title))</title>
          <style>
            :root { color-scheme: light dark; font-family: -apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo", sans-serif; }
            body { margin: 0; background: #f5f5f7; color: #1d1d1f; }
            header { padding: 20px 28px; background: rgba(255,255,255,.85); backdrop-filter: blur(12px); border-bottom: 1px solid #d2d2d7; position: sticky; top: 0; }
            h1 { margin: 0; font-size: 22px; }
            .badge { font-size: 12px; color: #6e6e73; margin-top: 4px; }
            main { max-width: 880px; margin: 0 auto; padding: 24px; display: grid; gap: 12px; }
            .card { display: flex; gap: 14px; align-items: center; padding: 16px; background: #fff; border-radius: 16px; text-decoration: none; color: inherit; box-shadow: 0 1px 3px rgba(0,0,0,.06); }
            .card:hover { box-shadow: 0 4px 16px rgba(0,0,0,.08); }
            .icon { width: 56px; height: 56px; border-radius: 14px; background: linear-gradient(135deg,#0a84ff,#64d2ff); color: #fff; display:grid; place-items:center; font-weight:700; font-size: 22px; flex: none; }
            .name { font-weight: 700; font-size: 17px; }
            .sub { color: #6e6e73; font-size: 13px; margin-top: 2px; }
            .meta { color: #86868b; font-size: 12px; margin-top: 6px; }
          </style>
        </head>
        <body>
          <header>
            <h1>\(esc(title))</h1>
            <div class="badge">로컬 목업 · 실제 App Store 아님 · listing 카피 + store-assets 샷</div>
          </header>
          <main>
            \(cards.isEmpty ? "<p>대상 제품 없음</p>" : cards)
          </main>
        </body>
        </html>
        """
    }

    private static func productHTML(
        product: Product,
        listing: StoreListing,
        platform: StoreListingPlatform,
        shotRelativePaths: [String]
    ) -> String {
        let name = listing.name.isEmpty
            ? (product.nameKo.isEmpty ? product.slug : product.nameKo)
            : listing.name
        let sub = listing.subtitle.isEmpty
            ? (product.salesAngle.isEmpty ? product.role : product.salesAngle)
            : listing.subtitle
        let description = listing.description.isEmpty ? sub : listing.description
        let price = listing.priceLabel.isEmpty
            ? (product.priceIdea.isEmpty ? "가격 미정" : product.priceIdea)
            : listing.priceLabel
        let cta = listing.primaryCTA.isEmpty ? "구매" : listing.primaryCTA
        let categoryLabel = listing.category.isEmpty
            ? product.categories.prefix(5).joined(separator: ", ")
            : listing.category
        let cats: String = {
            if !listing.category.isEmpty {
                return "<span class=\"chip\">\(esc(listing.category))</span>"
            }
            return product.categories.prefix(5).map {
                "<span class=\"chip\">\(esc($0))</span>"
            }.joined()
        }()
        let isPhone = platform == .ios
        let shots = shotRelativePaths.enumerated().map { index, path in
            """
            <figure class="shot\(index == 0 ? " active" : "")" data-i="\(index)">
              <img src="\(esc(path))" alt="screenshot \(index + 1)"/>
            </figure>
            """
        }.joined()
        let thumbs = shotRelativePaths.enumerated().map { index, path in
            """
            <button type="button" class="thumb\(index == 0 ? " on" : "")" data-i="\(index)">
              <img src="\(esc(path))" alt="thumb \(index + 1)"/>
            </button>
            """
        }.joined()
        let whatsNewSection: String = {
            guard !listing.whatsNew.isEmpty else { return "" }
            return """
            <section>
              <h2>새로운 기능</h2>
              <p>\(esc(listing.whatsNew))</p>
            </section>
            """
        }()
        let promoSection: String = {
            guard !listing.promotionalText.isEmpty else { return "" }
            return """
            <section>
              <h2>프로모션</h2>
              <p>\(esc(listing.promotionalText))</p>
            </section>
            """
        }()
        let storeTitle = platform.storeChromeTitle
        let bodyClass = isPhone ? "phone" : "mac"
        let stageClass = isPhone ? "stage phone-stage" : "stage"

        return """
        <!doctype html>
        <html lang="ko">
        <head>
          <meta charset="utf-8"/>
          <meta name="viewport" content="width=device-width, initial-scale=1"/>
          <title>\(esc(name)) · \(esc(storeTitle)) 미리보기</title>
          <style>
            :root { color-scheme: light dark; font-family: -apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo", sans-serif; }
            body { margin: 0; background: #f5f5f7; color: #1d1d1f; }
            body.phone { background: #e8e8ed; }
            header { display:flex; justify-content:space-between; align-items:center; padding: 14px 24px; background: rgba(255,255,255,.9); border-bottom: 1px solid #d2d2d7; position: sticky; top: 0; backdrop-filter: blur(12px); }
            header a { color: #0066cc; text-decoration: none; font-size: 14px; }
            .badge { font-size: 12px; color: #6e6e73; background: #e8e8ed; padding: 4px 10px; border-radius: 999px; }
            main { max-width: 980px; margin: 0 auto; padding: 28px 20px 48px; }
            body.phone main { max-width: 430px; }
            .hero { display:flex; gap: 18px; align-items: flex-start; margin-bottom: 28px; }
            body.phone .hero { flex-direction: column; align-items: stretch; }
            .icon { width: 104px; height: 104px; border-radius: 24px; background: linear-gradient(135deg,#0a84ff,#64d2ff); color:#fff; display:grid; place-items:center; font-size: 40px; font-weight: 700; box-shadow: 0 8px 24px rgba(0,0,0,.12); flex:none; }
            body.phone .icon { width: 72px; height: 72px; border-radius: 16px; font-size: 28px; }
            .title { font-size: 32px; font-weight: 800; margin: 0 0 6px; letter-spacing: -0.02em; }
            body.phone .title { font-size: 24px; }
            .sub { color: #6e6e73; font-size: 17px; line-height: 1.35; margin: 0 0 10px; }
            body.phone .sub { font-size: 14px; }
            .chips { display:flex; flex-wrap:wrap; gap: 6px; }
            .chip { font-size: 12px; background: #e8e8ed; padding: 3px 8px; border-radius: 999px; }
            .cta-wrap { margin-left: auto; text-align: right; min-width: 140px; }
            body.phone .cta-wrap { margin-left: 0; text-align: left; }
            .cta { border: 0; background: #0071e3; color: #fff; font-weight: 700; font-size: 16px; padding: 10px 22px; border-radius: 980px; }
            .price { margin-top: 8px; font-size: 12px; color: #6e6e73; max-width: 200px; }
            body.mac .price { margin-left: auto; }
            .stage { background: #fff; border-radius: 20px; padding: 18px; box-shadow: 0 1px 3px rgba(0,0,0,.06); }
            .phone-stage { border-radius: 28px; }
            .shot { display:none; margin: 0; }
            .shot.active { display:block; }
            .shot img { width: 100%; max-height: 520px; object-fit: contain; border-radius: 12px; background: #fbfbfd; }
            body.phone .shot img { max-height: 640px; border-radius: 18px; }
            .thumbs { display:flex; gap: 10px; overflow-x: auto; padding: 14px 2px 4px; }
            .thumb { border: 2px solid transparent; padding: 0; background: none; border-radius: 8px; cursor: pointer; flex: none; }
            .thumb.on { border-color: #0071e3; }
            .thumb img { width: 104px; height: 66px; object-fit: cover; border-radius: 6px; display:block; }
            body.phone .thumb img { width: 72px; height: 128px; }
            section { margin-top: 28px; }
            h2 { font-size: 20px; margin: 0 0 8px; }
            p { margin: 0; line-height: 1.5; color: #1d1d1f; white-space: pre-wrap; }
            .muted { color: #6e6e73; font-size: 13px; }
          </style>
        </head>
        <body class="\(bodyClass)">
          <header>
            <a href="../index.html">← 목록</a>
            <div class="badge">\(esc(storeTitle)) · 미리보기 · 실제 스토어 아님</div>
          </header>
          <main>
            <div class="hero">
              <div class="icon">\(esc(String(name.prefix(1))))</div>
              <div style="flex:1">
                <h1 class="title">\(esc(name))</h1>
                <p class="sub">\(esc(sub))</p>
                <div class="chips">\(cats.isEmpty ? "<span class=\"chip\">\(esc(categoryLabel))</span>" : cats)</div>
              </div>
              <div class="cta-wrap">
                <button class="cta" type="button" disabled>\(esc(cta))</button>
                <div class="price">\(esc(price))</div>
              </div>
            </div>
            <div class="\(stageClass)">
              \(shots.isEmpty ? "<p>스크린샷 없음</p>" : shots)
              <div class="thumbs">\(thumbs)</div>
            </div>
            <section>
              <h2>설명</h2>
              <p>\(esc(description))</p>
            </section>
            \(promoSection)
            \(whatsNewSection)
            <section>
              <h2>이 앱이 하는 일</h2>
              <p>\(esc(product.role.isEmpty ? listing.promotionalText : product.role))</p>
            </section>
            <section>
              <h2>이런 분께</h2>
              <p>\(esc(product.buyerPersona.isEmpty ? "—" : product.buyerPersona))</p>
            </section>
            <p class="muted" style="margin-top:24px">listing version: \(esc(listing.versionId)) · saved \(esc(listing.savedAt)) · \(esc(listing.note))</p>
          </main>
          <script>
            const shots = [...document.querySelectorAll('.shot')];
            const thumbs = [...document.querySelectorAll('.thumb')];
            function show(i) {
              shots.forEach((el, idx) => el.classList.toggle('active', idx === i));
              thumbs.forEach((el, idx) => el.classList.toggle('on', idx === i));
            }
            thumbs.forEach(btn => btn.addEventListener('click', () => show(Number(btn.dataset.i))));
          </script>
        </body>
        </html>
        """
    }
}
