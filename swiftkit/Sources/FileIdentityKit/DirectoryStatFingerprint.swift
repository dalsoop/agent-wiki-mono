import Foundation

/// `DirectoryFingerprint` 과 같은 출력: `개수:총바이트:최신mtime`.
/// 파일 본문은 읽지 않는다.
public enum DirectoryStatFingerprint {
    public static func fingerprint(root: URL, fileExtension ext: String) -> String {
        var bytes: Int64 = 0
        var latest = Date(timeIntervalSince1970: 0)
        var count = 0
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return "0:0:0" }
        if let it = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in it where url.pathExtension == ext {
                guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { continue }
                if let d = values.contentModificationDate, d > latest { latest = d }
                bytes += Int64(values.fileSize ?? 0)
                count += 1
            }
        }
        return "\(count):\(bytes):\(Int(latest.timeIntervalSince1970))"
    }
}
