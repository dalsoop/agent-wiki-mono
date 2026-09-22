import Foundation

public enum DetailRenderer {
    // Matches a quoted attribute value containing ".../content-assets/<path>" and captures <path>.
    private static let pattern = #"(["'])([^"']*?content-assets/([^"']+))\1"#

    /// All content-asset paths referenced by the HTML, in order, de-duplicated.
    public static func extractAssetPaths(from html: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for match in matches(in: html) {
            let path = match.path
            if seen.insert(path).inserted { result.append(path) }
        }
        return result
    }

    /// Rewrites every content-asset URL to a local relative `./<path>`; leaves other URLs intact.
    public static func rewrite(html: String) -> String {
        guard let regex = compiledPattern() else { return html }
        let ns = html as NSString
        var output = html
        // Replace from the end so ranges stay valid.
        let all = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        for m in all.reversed() {
            let quote = ns.substring(with: m.range(at: 1))
            let path = ns.substring(with: m.range(at: 3))
            let replacement = "\(quote)./\(path)\(quote)"
            let r = Range(m.range(at: 0), in: output)!
            output.replaceSubrange(r, with: replacement)
        }
        return output
    }

    private struct Match { let path: String }

    private static func compiledPattern() -> NSRegularExpression? {
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            FileHandle.standardError.write(
                Data("warning: DetailRenderer pattern failed: \(error.localizedDescription)\n".utf8))
            return nil
        }
    }

    private static func matches(in html: String) -> [Match] {
        guard let regex = compiledPattern() else { return [] }
        let ns = html as NSString
        return regex.matches(in: html, range: NSRange(location: 0, length: ns.length)).map {
            Match(path: ns.substring(with: $0.range(at: 3)))
        }
    }
}
