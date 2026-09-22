import Foundation

extension String {
    /// CLI 터미널 출력용 고정 폭 좌측 정렬 패딩을 적용한다.
    @inlinable
    public func padded(_ width: Int) -> String {
        padding(toLength: width, withPad: " ", startingAt: 0)
    }

    /// 지정된 길이를 초과하는 문자열을 줄이고 말줄임표(기본값 "...")를 덧붙인다.
    @inlinable
    public func truncated(to length: Int, trailing: String = "...") -> String {
        guard count > length else { return self }
        let cutIndex = index(startIndex, offsetBy: Swift.max(0, length - trailing.count))
        return String(self[..<cutIndex]) + trailing
    }

    /// 첫 번째 줄만 추출한다 (개행 문자 제외).
    @inlinable
    public var firstLine: String? {
        components(separatedBy: .newlines).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
    }
}
