import Foundation
import StateRootKit

/// `~/.product-portfolio/showcase/` 아래 랜딩·first-run 문서와
/// 제품 `screenshotPaths` / generated 비주얼 경로의 존재 여부를 읽는다.
public enum ShowcasePackageReader {
    public static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "tif", "tiff",
    ]

    public static func defaultRoot() -> URL {
        StateRootKit.url(for: ".product-portfolio/showcase")
    }

    public static func landingURL(slug: String, root: URL = defaultRoot()) -> URL {
        root
            .appendingPathComponent("landings", isDirectory: true)
            .appendingPathComponent("\(slug).md")
    }

    public static func firstRunURL(slug: String, root: URL = defaultRoot()) -> URL {
        root
            .appendingPathComponent("first-run", isDirectory: true)
            .appendingPathComponent("\(slug).md")
    }

    public static func loadUTF8Text(at url: URL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    public static func landingMarkdown(
        slug: String,
        root: URL = defaultRoot()
    ) -> String? {
        loadUTF8Text(at: landingURL(slug: slug, root: root))
    }

    public static func firstRunMarkdown(
        slug: String,
        root: URL = defaultRoot()
    ) -> String? {
        loadUTF8Text(at: firstRunURL(slug: slug, root: root))
    }

    /// 경로 문자열이 가리키는 파일이 이미지로 존재하면 URL 로 반환.
    public static func existingImageURLs(from paths: [String]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for raw in paths {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let url = URL(fileURLWithPath: trimmed).standardizedFileURL
            let key = url.path
            guard !seen.contains(key) else { continue }
            guard imageExtensions.contains(url.pathExtension.lowercased()) else { continue }
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            seen.insert(key)
            result.append(url)
        }
        return result
    }

    /// screenshotPaths + generated 비주얼 path 중 디스크에 있는 이미지만.
    public static func displayableImageURLs(for product: Product) -> [URL] {
        var paths = product.screenshotPaths
        for path in product.generatedVisualPaths where !paths.contains(path) {
            paths.append(path)
        }
        return existingImageURLs(from: paths)
    }
}
