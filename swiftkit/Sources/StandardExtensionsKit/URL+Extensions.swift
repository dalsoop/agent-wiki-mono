import Foundation

extension URL {
    /// 홈 디렉터리(`~`)로 축약된 경로 문자열을 반환한다.
    @inlinable
    public var abbreviatingWithTildeInPath: String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    /// URL이 가리키는 대상이 심볼릭 링크인지 여부를 검사한다.
    @inlinable
    public var isSymbolicLink: Bool {
        (try? resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false
    }
}
