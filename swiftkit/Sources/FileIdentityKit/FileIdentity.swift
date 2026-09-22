import CryptoKit
import Foundation

/// git-annex WORM / DirectoryFingerprint 와 같다. 본문 해시가 아니다.
public enum FileIdentity: Sendable {
    /// `rel + bytes + mtime(ms)` 의 짧은 토큰. 파일은 읽지 않는다.
    public static func worm(_ stat: FileStat) -> String {
        let ms = Int64((stat.modifiedAt.timeIntervalSince1970 * 1000).rounded())
        return token(parts: ["worm", stat.relativePath, String(stat.byteCount), String(ms)])
    }

    /// 경로만으로 세션 같은 묶음의 id. 역시 파일 본문은 안 읽는다.
    public static func pathToken(_ relativePath: String) -> String {
        token(parts: ["path", nfc(relativePath)])
    }

    public static func nfc(_ raw: String) -> String {
        raw.precomposedStringWithCanonicalMapping
    }

    public static func relative(_ url: URL, to root: URL) -> String {
        let rootPath = nfc(root.standardizedFileURL.path)
        let path = nfc(url.standardizedFileURL.path)
        if path == rootPath { return "" }
        if path.hasPrefix(rootPath + "/") {
            return String(path.dropFirst(rootPath.count + 1))
        }
        return path
    }

    public static func token(parts: [String]) -> String {
        let payload = parts.joined(separator: "\u{1e}")
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}
