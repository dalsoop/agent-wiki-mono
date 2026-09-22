import Foundation

extension ProcessInfo {
    /// 환경변수가 `"1"` 또는 `"true"`(대소문자 무관)로 설정되어 있는지 검사한다.
    @inlinable
    public func bool(for key: String) -> Bool {
        guard let val = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return false
        }
        return val == "1" || val == "true" || val == "yes" || val == "y"
    }

    /// 환경변수가 존재하며 공백이 아닌 경우 트림된 문자열을 반환한다.
    @inlinable
    public func nonEmptyString(for key: String) -> String? {
        guard let val = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !val.isEmpty else {
            return nil
        }
        return val
    }
}
