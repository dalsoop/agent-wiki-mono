import Foundation

/// SKILL.md frontmatter 에서 name/version 만 읽는다.
public enum SkillMarkdownParser: Sendable {
    public static func parse(skillDir: URL) -> (name: String, version: String, body: String)? {
        let file = skillDir.appendingPathComponent("SKILL.md")
        let content: String
        do {
            content = try String(contentsOf: file, encoding: .utf8)
        } catch {
            return nil
        }
        guard content.hasPrefix("---") else { return nil }
        let parts = content.components(separatedBy: "---")
        guard parts.count >= 3 else { return nil }
        var name: String?
        var version: String?
        for line in parts[1].components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("name:") {
                name = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
            }
            if trimmed.hasPrefix("version:") {
                version = trimmed.dropFirst(8).trimmingCharacters(in: .whitespaces)
            }
        }
        guard let name, !name.isEmpty else { return nil }
        return (name, version ?? "0.0.0", content)
    }
}
