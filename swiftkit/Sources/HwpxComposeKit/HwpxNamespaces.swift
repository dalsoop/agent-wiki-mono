import Foundation

/// HWPX(OWPML) XML 네임스페이스 URI 상수.
enum HwpxNamespaces {
    private static let scheme = "http"
    private static let host = "www.hancom.co.kr"
    private static let prefix = "\(scheme)://\(host)/hwpml/2011"

    static let opf = "\(prefix)/opf"
    static let head = "\(prefix)/head"
    static let paragraph = "\(prefix)/paragraph"
    static let core = "\(prefix)/core"
}
