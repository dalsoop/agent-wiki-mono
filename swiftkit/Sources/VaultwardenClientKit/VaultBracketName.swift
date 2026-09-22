import Foundation

/// Agent Vault ↔ Vaultwarden Client 공통 이름 표시 SSOT.
///
/// 원본 cipher/카드 이름 형식:
/// ```
/// [대분류][소분류] 서비스명 …
/// ```
/// - AV 리스트: 브래킷을 배지로, 본문만 제목
/// - VW 리스트: 동일 규칙 (원본 name 필드는 그대로 두고 **표시만** 분리)
/// - VW 폴더/태그 push 는 Agent Vault `CredentialNameStyle` 이 소유
public enum VaultBracketName: Sendable {
    /// 선두 `[…]` 들. 예: `"[IdP][계정] 구글 …"` → `["IdP", "계정"]`
    public static func parse(_ name: String) -> [String] {
        var tags: [String] = []
        var s = name.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasPrefix("["), let close = s.firstIndex(of: "]") {
            let inner = String(s[s.index(after: s.startIndex)..<close])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !inner.isEmpty, !tags.contains(inner) { tags.append(inner) }
            s = String(s[s.index(after: close)...]).trimmingCharacters(in: .whitespaces)
        }
        return tags
    }

    /// 리스트 제목용 — 선두 브래킷 프리픽스 제거 후 본문.
    public static func displayBody(from name: String) -> String {
        var s = name.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasPrefix("["), let close = s.firstIndex(of: "]") {
            s = String(s[s.index(after: close)...]).trimmingCharacters(in: .whitespaces)
        }
        let raw = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? raw : s
    }

    /// 목록·상세 제목. 브래킷과 이메일은 빼고 서비스명만.
    public static func listTitle(from name: String) -> String {
        let stripped = displayBody(from: name).replacingOccurrences(
            of: #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#,
            with: " ",
            options: .regularExpression
        )
        return stripped
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// URL 에서 `www.` 없는 호스트. 목록 부제용.
    public static func hostLabel(from uri: String) -> String {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let host = URL(string: withScheme)?.host, !host.isEmpty else { return "" }
        if host.lowercased().hasPrefix("www.") {
            return String(host.dropFirst(4))
        }
        return host
    }

    /// 이니셜 타일용. `[`·숫자는 건너뛰고 본문 글자를 쓴다.
    public static func displayInitial(from name: String, fallback: String = "") -> String {
        func glyph(in text: String) -> String? {
            if let letter = text.first(where: \.isLetter) { return String(letter).uppercased() }
            return text.first(where: \.isNumber).map { String($0) }
        }
        if let g = glyph(in: listTitle(from: name)) { return g }
        if let g = glyph(in: hostLabel(from: fallback)) { return g }
        if let g = glyph(in: fallback) { return g }
        return "?"
    }

    /// 대분류(첫 브래킷). 없으면 nil.
    public static func primary(from name: String) -> String? {
        parse(name).first
    }
}
