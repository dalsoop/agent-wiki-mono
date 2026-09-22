import Foundation

public enum ProductExporter {
    public static func markdown(_ product: Product) -> String {
        let title = product.nameKo.isEmpty ? product.slug : product.nameKo
        let categories = product.categories.isEmpty ? "미정" : product.categories.joined(separator: ", ")
        let screenshots = product.screenshotPaths.isEmpty
            ? "- 등록된 스크린샷 없음"
            : product.screenshotPaths.map { "- \($0)" }.joined(separator: "\n")
        let visuals: String = {
            if product.visuals.isEmpty {
                return "- 비주얼 슬롯 없음 (visual draft 로 planned 생성)"
            }
            return product.visuals.map { slot in
                let path = slot.path ?? "-"
                return "- [\(slot.status.rawValue)] \(slot.id) (\(slot.aspect)) path=\(path)\n  prompt: \(slot.prompt)"
            }.joined(separator: "\n")
        }()
        return """
        # \(title)

        - slug: `\(product.slug)`
        - 영문명: \(product.nameEn)
        - 분류: \(product.classification.rawValue)
        - 준비도: \(product.readiness)/5
        - 카테고리: \(categories)

        ## 하는 일

        \(product.role)

        ## 구매자

        \(product.buyerPersona)

        ## 구매 이유

        \(product.salesAngle)

        ## 가격 아이디어

        \(product.priceIdea)

        ## 스크린샷

        \(screenshots)

        ## 비주얼 슬롯

        \(visuals)
        """
    }

    public static func json(_ product: Product) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(product), as: UTF8.self) + "\n"
    }
}
