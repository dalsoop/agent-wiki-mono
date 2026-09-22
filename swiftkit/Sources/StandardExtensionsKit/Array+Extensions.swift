import Foundation

extension Array where Element: Hashable {
    /// 요소의 등장 순서를 보존하면서 중복을 제거한 새 배열을 반환한다.
    @inlinable
    public func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

extension Array {
    /// 배열을 주어진 크기 단위의 청크 배열로 분할한다.
    @inlinable
    public func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
