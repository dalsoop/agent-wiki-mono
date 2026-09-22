import Foundation

/// 파일 한 개의 stat. 본문은 읽지 않는다.
public struct FileStat: Sendable, Equatable, Hashable {
    public var relativePath: String
    public var byteCount: Int64
    public var modifiedAt: Date

    public init(relativePath: String, byteCount: Int64, modifiedAt: Date) {
        self.relativePath = FileIdentity.nfc(relativePath)
        self.byteCount = byteCount
        self.modifiedAt = modifiedAt
    }
}

public enum FileStatError: Error, Sendable, Equatable {
    case missing
    case notAFile
}

public enum FileStatReader: Sendable {
    /// `resourceValues` 만 본다. 파일 본문을 열지 않는다.
    public static func stat(url: URL, relativeTo root: URL? = nil) throws -> FileStat {
        let values = try url.resourceValues(forKeys: [
            .isDirectoryKey, .isRegularFileKey, .fileSizeKey, .contentModificationDateKey,
        ])
        if values.isDirectory == true { throw FileStatError.notAFile }
        guard values.isRegularFile == true || FileManager.default.fileExists(atPath: url.path) else {
            throw FileStatError.missing
        }
        let bytes = Int64(values.fileSize ?? 0)
        let modified = values.contentModificationDate ?? Date(timeIntervalSince1970: 0)
        let rel: String
        if let root {
            rel = FileIdentity.relative(url, to: root)
        } else {
            rel = FileIdentity.nfc(url.standardizedFileURL.path)
        }
        return FileStat(relativePath: rel, byteCount: bytes, modifiedAt: modified)
    }
}
