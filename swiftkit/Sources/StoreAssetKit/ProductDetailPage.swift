import Foundation

/// 상품 스펙 항목 (키-값 쌍)
public struct ProductSpecItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var key: String
    public var value: String

    public init(id: String = UUID().uuidString, key: String, value: String) {
        self.id = id
        self.key = key
        self.value = value
    }
}

/// 상품 상세페이지 구성 모델
public struct ProductDetailPage: Codable, Sendable, Equatable {
    /// 상세페이지 상단 헤드라인
    public var headline: String
    /// 상품 소개 부제
    public var subheadline: String
    /// 핵심 특장점 리스트
    public var highlights: [String]
    /// 상세 설명 본문 (마크다운 또는 단락 텍스트)
    public var descriptionBody: String
    /// 상품 상세 스펙 표
    public var specifications: [ProductSpecItem]
    /// 배송 및 반품 안내
    public var shippingAndReturnNotice: String

    public init(
        headline: String = "",
        subheadline: String = "",
        highlights: [String] = [],
        descriptionBody: String = "",
        specifications: [ProductSpecItem] = [],
        shippingAndReturnNotice: String = ""
    ) {
        self.headline = headline
        self.subheadline = subheadline
        self.highlights = highlights
        self.descriptionBody = descriptionBody
        self.specifications = specifications
        self.shippingAndReturnNotice = shippingAndReturnNotice
    }

    /// 기본 한국형 이커머스 표준 스펙 초기값 생성
    public static func standardDefaults(
        productName: String,
        manufacturer: String = "구조 ai",
        origin: String = "국산"
    ) -> ProductDetailPage {
        ProductDetailPage(
            headline: "\(productName) - 프리미엄 셀렉션",
            subheadline: "구조 ai가 엄선한 고품질 라이프스타일 상품입니다.",
            highlights: [
                "엄격한 품질 검수를 거친 정품",
                "국내 당일/익일 빠른 배송 보장",
                "사용자 편의성을 고려한 모던 디자인"
            ],
            descriptionBody: "\(productName)의 디테일과 마감은 실사용자의 만족도를 최우선으로 제작되었습니다. 일상에서 편리하게 활용해 보세요.",
            specifications: [
                ProductSpecItem(key: "제품명", value: productName),
                ProductSpecItem(key: "제조사 / 브랜드", value: manufacturer),
                ProductSpecItem(key: "원산지", value: origin),
                ProductSpecItem(key: "취급시 주의사항", value: "직사광선 및 고온 다습한 환경을 피하여 보관하십시오."),
                ProductSpecItem(key: "A/S 책임자 및 연락처", value: "구조 ai 고객센터 (02-1234-5678)")
            ],
            shippingAndReturnNotice: "오후 2시 이전 결제 완료 건은 당일 출고됩니다. 단순 변심 반품은 수령 후 7일 이내 왕복 배송비 부담 시 가능합니다."
        )
    }

    /// 네이버 스마트스토어 표준 호환 인라인 스타일 HTML 렌더링
    public func renderHTML(imageUrls: [String] = []) -> String {
        let containerStyle = "max-width: 860px; margin: 0 auto; " +
            "font-family: -apple-system, BlinkMacSystemFont, 'Apple SD Gothic Neo', sans-serif; " +
            "color: #222222; line-height: 1.6; word-break: keep-all; padding: 20px;"
        var html = "<div style=\"\(containerStyle)\">"
        html += renderIntro()
        html += renderHighlights()
        html += renderGallery(imageUrls: imageUrls)
        html += renderDescription()
        html += renderSpecifications()
        html += renderShippingNotice()
        html += "</div>"
        return html
    }

    private func renderIntro() -> String {
        guard !headline.isEmpty else { return "" }
        let sub = subheadline.isEmpty ? "" : "<p style=\"font-size: 16px; color: #4b5563; margin: 0;\">\(escapeHtml(subheadline))</p>"
        return """
        <div style="text-align: center; margin-bottom: 30px; padding: 20px 10px; border-bottom: 2px solid #111827;">
            <h1 style="font-size: 26px; font-weight: 800; color: #111827; margin: 0 0 10px 0;">\(escapeHtml(headline))</h1>
            \(sub)
        </div>
        """
    }

    private func renderHighlights() -> String {
        guard !highlights.isEmpty else { return "" }
        var result = """
        <div style="background-color: #f8fafc; border: 1px solid #e2e8f0; border-radius: 12px; padding: 20px 24px; margin-bottom: 35px;">
            <h3 style="font-size: 17px; font-weight: 700; color: #0f172a; margin: 0 0 14px 0;">✨ Point Check</h3>
            <ul style="margin: 0; padding-left: 20px; color: #334155; font-size: 15px; line-height: 1.8;">
        """
        for point in highlights where !point.trimmingCharacters(in: .whitespaces).isEmpty {
            result += "<li>\(escapeHtml(point))</li>"
        }
        result += """
            </ul>
        </div>
        """
        return result
    }

    private func renderGallery(imageUrls: [String]) -> String {
        guard !imageUrls.isEmpty else { return "" }
        var result = "<div style=\"display: flex; flex-direction: column; gap: 20px; margin-bottom: 40px; align-items: center;\">"
        for url in imageUrls where !url.trimmingCharacters(in: .whitespaces).isEmpty {
            result += """
            <div style="width: 100%; text-align: center;">
                <img src="\(escapeHtml(url))" style="max-width: 100%; height: auto; border-radius: 8px;" alt="상세 이미지" />
            </div>
            """
        }
        result += "</div>"
        return result
    }

    private func renderDescription() -> String {
        guard !descriptionBody.isEmpty else { return "" }
        var result = "<div style=\"font-size: 16px; line-height: 1.8; color: #374151; margin-bottom: 40px; padding: 0 8px;\">"
        let paragraphs = descriptionBody.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        for p in paragraphs {
            result += "<p style=\"margin: 0 0 14px 0;\">\(escapeHtml(p))</p>"
        }
        result += "</div>"
        return result
    }

    private func renderSpecifications() -> String {
        guard !specifications.isEmpty else { return "" }
        let headingStyle = "font-size: 18px; font-weight: 700; color: #111827; margin-bottom: 12px; " +
            "border-left: 4px solid #059669; padding-left: 8px;"
        var result = """
        <div style="margin-bottom: 40px;">
            <h3 style="\(headingStyle)">상품 정보 제공 고시</h3>
            <table style="width: 100%; border-collapse: collapse; font-size: 14px; text-align: left;">
                <tbody>
        """
        for (idx, spec) in specifications.enumerated() {
            let bgColor = idx % 2 == 0 ? "#ffffff" : "#f9fafb"
            result += """
            <tr style="background-color: \(bgColor); border-top: 1px solid #e5e7eb; border-bottom: 1px solid #e5e7eb;">
                <th style="width: 30%; padding: 12px 16px; font-weight: 600; color: #4b5563; background-color: #f3f4f6;">\(escapeHtml(spec.key))</th>
                <td style="width: 70%; padding: 12px 16px; color: #1f2937;">\(escapeHtml(spec.value))</td>
            </tr>
            """
        }
        result += """
                </tbody>
            </table>
        </div>
        """
        return result
    }

    private func renderShippingNotice() -> String {
        guard !shippingAndReturnNotice.isEmpty else { return "" }
        let boxStyle = "background-color: #fef2f2; border: 1px solid #fee2e2; border-radius: 8px; " +
            "padding: 16px 20px; font-size: 14px; color: #991b1b; line-height: 1.6;"
        return """
        <div style="\(boxStyle)">
            <h4 style="margin: 0 0 8px 0; font-size: 15px; font-weight: 700;">📦 배송 및 교환/반품 안내</h4>
            <p style="margin: 0;">\(escapeHtml(shippingAndReturnNotice))</p>
        </div>
        """
    }

    private func escapeHtml(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
