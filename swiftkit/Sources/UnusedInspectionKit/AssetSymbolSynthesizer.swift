import Foundation

/// Xcode 15+ Asset Catalog Symbol 합성기 (ImageResource 대응)
public enum AssetSymbolSynthesizer {
    /// 에셋 파일명/논리명을 Swift 식별자(camelCase)로 변환한다.
    /// 예: "cloud-arrow-down" -> "cloudArrowDown", "user_profile_banner" -> "userProfileBanner"
    public static func synthesizeIdentifier(from assetName: String) -> String {
        let base = assetName.components(separatedBy: ".").first ?? assetName
        let parts = base.split { $0 == "-" || $0 == "_" || $0 == " " }
        guard let first = parts.first else { return assetName }

        var result = first.prefix(1).lowercased() + first.dropFirst()
        for part in parts.dropFirst() {
            result += part.prefix(1).uppercased() + part.dropFirst()
        }
        return result
    }

    /// 소스코드 텍스트 내에서 에셋 심볼(Image(.symbolName) 등)이 참조되는지 검사한다.
    public static func containsSymbolReference(symbolName: String, in sourceCode: String) -> Bool {
        // 1. `.<symbolName>` 형태의 멤버 접근 (Image(.cloudArrowDown), Color(.primary))
        let dotPattern = "." + symbolName
        if sourceCode.contains(dotPattern) {
            return true
        }

        // 2. Asset.<symbolName> 형태 (SwiftGen / R.swift 패턴)
        let assetPattern = "Asset." + symbolName
        if sourceCode.contains(assetPattern) {
            return true
        }

        return false
    }
}
