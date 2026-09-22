import Foundation

public enum ProductCopy {
    /// 공백만 있는 문자열도 비어 있는 것으로 본다 (missing / 정규화 공통).
    public static func isBlank(_ raw: String) -> Bool {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 저장 전 공백-only 를 빈 문자열로 정규화.
    public static func normalizedText(_ raw: String) -> String {
        isBlank(raw) ? "" : raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// README 등에서 들어온 마크다운 강조를 카드/목록용 plain text로 정리한다.
    public static func plainRole(_ raw: String) -> String {
        var text = raw
        text = text.replacingOccurrences(
            of: #"`([^`]+)`"#,
            with: "$1",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"\*\*([^*]+)\*\*"#,
            with: "$1",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"__([^_]+)__"#,
            with: "$1",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"\*([^*]+)\*"#,
            with: "$1",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"_([^_]+)_"#,
            with: "$1",
            options: .regularExpression
        )
        text = text.replacingOccurrences(of: "**", with: "")
        text = text.replacingOccurrences(of: "__", with: "")
        return text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// role 마크다운만 정리한다. 페르소나·판매각·가격 템플릿은 넣지 않는다.
    public static func cleaningRoleMarkdown(_ product: Product) throws -> (Product, Bool) {
        let cleanedRole = plainRole(product.role)
        guard product.role != cleanedRole else { return (product, false) }
        let next = try product.replacing(Product.Patch(pitch: .init(role: cleanedRole)))
        return (next, true)
    }

    @available(*, deprecated, renamed: "cleaningRoleMarkdown", message: "판매 문구 템플릿 주입은 제거됨")
    public static func enriching(_ product: Product) throws -> (Product, Bool) {
        try cleaningRoleMarkdown(product)
    }
}
