// `import Crypto` (swift-crypto) 는 Apple 플랫폼에서는 CryptoKit 을 @_exported 로
// 재노출하고, Linux 에서는 동등한 API 를 직접 제공한다 — 이 한 줄로 macOS 앱·Linux
// 컨테이너 서버(business-api) 양쪽에서 SHA256 이 컴파일된다.
import Crypto
import Foundation

/// 거래 중복판정 해시 — 같은 은행 CSV 를 다시 가져와도 원장이 두 배가 되지 않게 하는 계약.
/// 해시 문자열 구성은 **저장 계약**이다: 바꾸면 기존 원장 전체가 새 거래로 재유입되므로
/// 버전 접두사(mf1)를 올리고 마이그레이션을 설계하기 전에는 절대 손대지 않는다.
public enum ContentHash {
    /// 같은 파일 안의 진짜 동일 거래(같은 날 같은 금액 같은 적요 2건)는 occurrence 로 살리고,
    /// 재가져오기는 occurrence 까지 동일하게 재계산되므로 깨끗하게 걸러진다.
    public static func transactionHash(
        date: String,
        time: String?,
        amountMinor: Int64,
        currency: String,
        instrumentID: String,
        description: String,
        balanceAfterMinor: Int64?,
        occurrence: Int = 1
    ) -> String {
        let canonical = [
            "mf1",
            date,
            time ?? "",
            "\(amountMinor)",
            MoneyAmount.normalizedCurrency(currency),
            instrumentID,
            normalizedDescription(description),
            balanceAfterMinor.map { "\($0)" } ?? "",
            "#\(occurrence)",
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// 공백 정리 + NFC — 은행이 내보내는 전각/조합 문자 흔들림을 흡수한다.
    /// 소문자화는 하지 않는다(한글 무관, 영문 적요는 은행이 케이스를 안 바꾼다).
    public static func normalizedDescription(_ raw: String) -> String {
        let collapsed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed.precomposedStringWithCanonicalMapping
    }
}
