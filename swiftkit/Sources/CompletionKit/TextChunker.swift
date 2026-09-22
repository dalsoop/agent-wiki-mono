import Foundation

// MARK: - 합성 타이핑용 UTF-16 청크 분할 (순수 함수 — 테스트 대상)

/// CGEventKeyboardSetUnicodeString 한 번에 싣는 유닛 수를 제한하기 위한 분할기.
/// 유니코드 스칼라 경계로만 자르므로 서로게이트 페어(BMP 밖 문자, 2유닛)가
/// 중간에서 쪼개지지 않는다.
public enum TextChunker {
    /// 청크당 최대 UTF-16 유닛 수.
    public static let maxUTF16UnitsPerChunk = 20

    /// text 를 UTF-16 기준 maxUTF16Units 이하 청크로 분할.
    /// maxUTF16Units < 2 가 들어와도 페어(2유닛)를 담을 수 있게 내부에서 2로 올린다.
    /// 빈 문자열은 빈 배열.
    public static func split(
        _ text: String,
        maxUTF16Units: Int = maxUTF16UnitsPerChunk
    ) -> [String] {
        let cap = Swift.max(2, maxUTF16Units)
        var chunks: [String] = []
        var current = String.UnicodeScalarView()
        var currentUnits = 0
        for scalar in text.unicodeScalars {
            let width = UTF16.width(scalar) // 1 또는 2(서로게이트 페어)
            if currentUnits + width > cap, currentUnits > 0 {
                chunks.append(String(current))
                current = String.UnicodeScalarView()
                currentUnits = 0
            }
            current.append(scalar)
            currentUnits += width
        }
        if currentUnits > 0 {
            chunks.append(String(current))
        }
        return chunks
    }
}
