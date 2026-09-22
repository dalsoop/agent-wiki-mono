import Foundation

/// app-quality-loop evidence JSON → 0...100 종합 점수.
///
/// 정본 디렉터리: `~/.product-portfolio/quality-loop/`
/// 파일 이름: `<slug>.json` 또는 `<slug>-evidence.json`
///
/// 지원 형태:
/// 1. score_app.py 입력 — `categories.<name>.score` + 가중치
/// 2. score_app.py 출력 — 최상위 `score`
/// 3. 최소 `{ "score": 88 }`
public enum QualityLoopEvidenceLoader {
    public static var defaultRoot: URL {
        PortfolioPaths.defaultRoot.appendingPathComponent("quality-loop", isDirectory: true)
    }

    /// app-quality-loop `score_app.py` DEFAULT_WEIGHTS 와 동일.
    public static let defaultWeights: [String: Double] = [
        "correctness": 25,
        "tests": 20,
        "ux": 15,
        "architecture": 15,
        "integration": 10,
        "docs_ops": 10,
        "git_hygiene": 5,
    ]

    /// 디렉터리 안 JSON을 읽어 slug → 0...100 맵.
    public static func loadScores(
        from directory: URL,
        fileManager: FileManager = .default
    ) -> [String: Double] {
        guard fileManager.fileExists(atPath: directory.path),
              let urls = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              )
        else { return [:] }

        var map: [String: Double] = [:]
        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let score = score(from: data)
            else { continue }
            for slug in candidateSlugs(for: url, data: data) {
                // 더 높은 점수를 남기지 않고 파일 순서 마지막이 이기면 안 됨 — 첫 유효값 유지,
                // 동일 slug 여러 파일이면 더 최근 mtime 우선은 단순화해 max 사용.
                if let existing = map[slug] {
                    map[slug] = max(existing, score)
                } else {
                    map[slug] = score
                }
            }
        }
        return map
    }

    /// evidence/score JSON 한 건 → 0...100.
    public static func score(from data: Data) -> Double? {
        guard let object = PortfolioJSON.object(from: data) else {
            return nil
        }
        if let direct = number(object["score"]), (0...100).contains(direct) {
            return direct
        }
        guard let categories = object["categories"] as? [String: Any] else { return nil }

        var weights = defaultWeights
        if let custom = object["weights"] as? [String: Any] {
            for (key, value) in custom {
                if let w = number(value), w > 0 { weights[key] = w }
            }
        }

        var totalWeight = 0.0
        var weighted = 0.0
        for (category, weight) in weights {
            guard let row = categories[category] as? [String: Any],
                  let categoryScore = number(row["score"]),
                  (0...100).contains(categoryScore)
            else { continue }
            totalWeight += weight
            weighted += categoryScore * weight
        }
        guard totalWeight > 0 else { return nil }
        let result = weighted / totalWeight
        return (result * 100).rounded() / 100
    }

    private static func candidateSlugs(for url: URL, data: Data) -> [String] {
        var slugs: [String] = []
        let base = url.deletingPathExtension().lastPathComponent
        let trimmed = base.hasSuffix("-evidence")
            ? String(base.dropLast("-evidence".count))
            : base
        if Evaluation.isValid(slug: trimmed) {
            slugs.append(trimmed)
        }
        if let object = PortfolioJSON.object(from: data) {
            if let app = object["app"] as? String {
                // "apps/foo-swift" 또는 경로
                let last = URL(filePath: app).lastPathComponent
                if Evaluation.isValid(slug: last) { slugs.append(last) }
            }
            if let slug = object["slug"] as? String, Evaluation.isValid(slug: slug) {
                slugs.append(slug)
            }
        }
        return Array(Set(slugs))
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let d as Double: return d
        case let i as Int: return Double(i)
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s)
        default: return nil
        }
    }
}
