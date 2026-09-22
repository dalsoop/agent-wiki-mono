import Foundation
import StateRootKit

/// 자율 마이닝된 동적 린트 규칙을 로드하여 작동시키는 어댑터 및 로더.
///
/// 재컴파일 없이 선언적 JSON 규칙을 런타임에 즉시 로드한다.
public final class MinedRuleAdapter: @unchecked Sendable {
    public static var id: String { "mined-rule-adapter" }

    public let spec: DeclarativeMinedRule
    private let regex: NSRegularExpression?

    public init(spec: DeclarativeMinedRule) {
        self.spec = spec
        do {
            self.regex = try NSRegularExpression(pattern: spec.pattern, options: [.anchorsMatchLines])
        } catch {
            self.regex = nil
        }
    }

    public var ruleID: String { spec.id }
    public var ruleGrade: String { spec.grade }

    public func applies(to path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        if !spec.targetFileExtensions.isEmpty && !spec.targetFileExtensions.contains(ext) {
            return false
        }
        if !spec.pathNeedles.isEmpty && !spec.pathNeedles.contains(where: { path.contains($0) }) {
            return false
        }
        if spec.excludePathPatterns.contains(where: { path.contains($0) }) {
            return false
        }
        return true
    }
}

public enum MinedRuleRegistry: Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cachedRules: [MinedRuleAdapter]?

    public static var userMinedRulesDir: URL {
        StateRootKit.url(".agent-lint/mined-rules")
    }

    public static func loadRules(repoRoot: String?) -> [MinedRuleAdapter] {
        lock.lock()
        defer { lock.unlock() }

        if let cached = cachedRules { return cached }

        var directories: [URL] = [userMinedRulesDir]
        if let root = repoRoot {
            let minedRulesSubpath = ".agent-lint/mined-rules"
            let repoDir = URL(fileURLWithPath: root).appendingPathComponent(minedRulesSubpath)
            directories.append(repoDir)
        }

        var loadedAdapters: [MinedRuleAdapter] = []
        let decoder = JSONDecoder()

        for dir in directories {
            guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
                continue
            }
            for file in files where file.pathExtension == "json" {
                guard let data = try? Data(contentsOf: file),
                      let spec = try? decoder.decode(DeclarativeMinedRule.self, from: data) else {
                    continue
                }
                loadedAdapters.append(MinedRuleAdapter(spec: spec))
            }
        }

        cachedRules = loadedAdapters
        return loadedAdapters
    }

    public static func resetCache() {
        lock.lock()
        defer { lock.unlock() }
        cachedRules = nil
    }

    /// 인시던트 diff 또는 패턴으로부터 규칙을 합성하여 영구 저장소에 적층
    @discardableResult
    public static func saveMinedRule(_ rule: DeclarativeMinedRule, targetDir: URL = userMinedRulesDir) throws -> URL {
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        let fileURL = targetDir.appendingPathComponent("\(rule.id).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(rule)
        try data.write(to: fileURL, options: .atomic)
        resetCache()
        return fileURL
    }
}
