import Foundation

/// SMB 가 파일명 바이트를 잃으면 `U+FFFD` 가 남는다. 원본 파일은 안 고친다.
public enum DisplayFileName {
    public static func title(name: String, rel: String = "") -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let nfc = trimmed.precomposedStringWithCanonicalMapping
        if isReadable(nfc) { return nfc }
        let ext = (nfc as NSString).pathExtension
        let stem = cameraStem(nfc)
        if let parent = readableParent(rel) {
            return ext.isEmpty ? "\(parent) · \(stem)" : "\(parent) · \(stem).\(ext)"
        }
        return ext.isEmpty ? stem : "\(stem).\(ext)"
    }

    public static func shown(name: String, rel: String, fallbackID: String) -> String {
        let text = Self.title(name: name, rel: rel)
        return text.isEmpty ? fallbackID : text
    }

    public static func matchesSearch(name: String, rel: String, id: String, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        if id.lowercased().hasPrefix(q.lowercased()) { return true }
        if name.localizedStandardContains(q) { return true }
        if rel.localizedStandardContains(q) { return true }
        return title(name: name, rel: rel).localizedStandardContains(q)
    }

    public static func isReadable(_ raw: String) -> Bool {
        !raw.contains("\u{FFFD}")
    }

    private static func readableParent(_ rel: String) -> String? {
        let trimmed = rel.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
        let parts = trimmed.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        let parent = parts[parts.count - 2]
        let nfc = parent.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        guard !nfc.isEmpty, nfc != ".", isReadable(nfc) else { return nil }
        return nfc
    }

    private static func cameraStem(_ name: String) -> String {
        let base = (name as NSString).deletingPathExtension
        let scalars = base.unicodeScalars
        var stem = ""
        for scalar in scalars {
            let ch = Character(scalar)
            if ch == "\u{FFFD}" { break }
            if ch.isLetter || ch.isNumber || ch == "_" || ch == "-" {
                stem.append(ch)
                continue
            }
            if ch == " " && !stem.isEmpty { break }
            if !stem.isEmpty { break }
        }
        return stem.isEmpty ? "file" : stem
    }
}
