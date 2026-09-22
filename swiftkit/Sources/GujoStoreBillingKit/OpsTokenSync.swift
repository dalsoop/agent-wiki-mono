import Foundation

/// 평문 파일 동기화는 퇴역. Staff 토큰은 Keychain `net.ranode.gujo` / `staff`.
public enum OpsTokenSync {
    public struct Result: Sendable {
        public var ok: Bool
        public var detail: String
        public init(ok: Bool, detail: String) {
            self.ok = ok
            self.detail = detail
        }
    }

    public static func applyFromEnvironment() -> Result {
        Result(ok: false, detail: "env token is forbidden; use Keychain net.ranode.gujo / staff")
    }

    public static func syncFromVault() async -> Result {
        Result(ok: false, detail: "file token sync retired; use Keychain net.ranode.gujo / staff")
    }
}
