import CryptoKit
import Foundation

/// 원본층(bedrock) — 날것 산출물(run stdout·트랜스크립트·diff·스크린샷)을 content-addressed 로 봉인.
/// git object 처럼 sha256 이 곧 이름·불변 보증이다. 사건(events)·해석(md)은 이 blob 을 sha 로만 가리킨다.
/// 저장: <root>/blobs/<앞2자>/<sha256>. 정본이지만 대용량이라 실물은 syncthing .stignore 로 제외하고
/// 포인터(sha)만 사건 로그로 전파한다(git-annex/LFS 식). 지워도 sha 는 사건에 남아 위조가 드러난다.
public struct BlobStore: Sendable {
    public let root: URL
    private var blobsDir: URL { root.appendingPathComponent("blobs") }

    public init(root: URL) { self.root = root }

    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// blob 파일 경로 — 앞 2자로 팬아웃해 디렉터리 하나에 몰리지 않게(git 방식).
    public func url(for sha: String) -> URL {
        blobsDir.appendingPathComponent(String(sha.prefix(2))).appendingPathComponent(sha)
    }

    public func exists(_ sha: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: sha).path)
    }

    /// data 를 저장하고 sha256 반환. 이미 있으면 그대로(write-once·멱등).
    @discardableResult
    public func put(_ data: Data) throws -> String {
        let sha = Self.sha256(data)
        let dest = url(for: sha)
        guard !FileManager.default.fileExists(atPath: dest.path) else { return sha }
        try FileManager.default.createDirectory(
            at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: dest, options: [.withoutOverwriting])
        return sha
    }

    @discardableResult
    public func put(contentsOf file: URL) throws -> String {
        try put(Data(contentsOf: file))
    }

    public func get(_ sha: String) -> Data? {
        try? Data(contentsOf: url(for: sha))
    }

    /// 저장된 모든 blob sha (sha256 hex = 64자 파일만).
    public func allSHAs() -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: blobsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        var out: [String] = []
        for case let url as URL in enumerator where url.lastPathComponent.count == 64 {
            out.append(url.lastPathComponent)
        }
        return out.sorted()
    }

    /// reachable 집합에 없는 blob 제거(git gc 식 보존정책). 반환: 제거 수.
    /// 정본 참조는 사건 로그의 포인터이므로 reachable 은 호출측(사건 스캔)이 넘긴다.
    @discardableResult
    public func prune(keeping reachable: Set<String>) -> Int {
        var removed = 0
        for sha in allSHAs() where !reachable.contains(sha) {
            if (try? FileManager.default.removeItem(at: url(for: sha))) != nil { removed += 1 }
        }
        return removed
    }

    /// 무결성 — 저장된 내용의 sha 가 파일명과 일치하는지(변조 감지). 없으면 false.
    public func verify(_ sha: String) -> Bool {
        guard let data = get(sha) else { return false }
        return Self.sha256(data) == sha
    }

    /// blob 바이트 크기(없으면 nil).
    public func size(_ sha: String) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url(for: sha).path))?[.size] as? Int
    }

    /// 원본 종류 — 매직 바이트로 판별. PDF·MP3·이미지 등 바이너리도 알아본다.
    /// blob 자체는 순수 바이트라 확장자를 안 가지므로, 열람·미리보기용으로 여기서 유추한다.
    public struct Kind: Sendable, Equatable {
        public let label: String   // "PDF" · "MP3" · "PNG" · "텍스트" · "바이너리" …
        public let ext: String     // 임시 파일로 열 때 붙일 확장자
        public let isText: Bool
        public let previewable: Bool  // 이미지·PDF 처럼 앱에서 인라인/QuickLook 가능
    }

    public static func sniff(_ data: Data) -> Kind {
        func has(_ bytes: [UInt8], at offset: Int = 0) -> Bool {
            guard data.count >= offset + bytes.count else { return false }
            for (i, b) in bytes.enumerated() where data[data.startIndex + offset + i] != b { return false }
            return true
        }
        if has([0x25, 0x50, 0x44, 0x46]) { return Kind(label: "PDF", ext: "pdf", isText: false, previewable: true) }
        if has([0x89, 0x50, 0x4E, 0x47]) { return Kind(label: "PNG", ext: "png", isText: false, previewable: true) }
        if has([0xFF, 0xD8, 0xFF]) { return Kind(label: "JPEG", ext: "jpg", isText: false, previewable: true) }
        if has([0x47, 0x49, 0x46, 0x38]) { return Kind(label: "GIF", ext: "gif", isText: false, previewable: true) }
        if has([0x49, 0x44, 0x33]) || has([0xFF, 0xFB]) || has([0xFF, 0xF3]) || has([0xFF, 0xF2]) {
            return Kind(label: "MP3", ext: "mp3", isText: false, previewable: true)
        }
        if has([0x52, 0x49, 0x46, 0x46]) { return Kind(label: "WAV", ext: "wav", isText: false, previewable: true) }
        if has([0x66, 0x74, 0x79, 0x70], at: 4) { return Kind(label: "MP4/M4A", ext: "mp4", isText: false, previewable: true) }
        if has([0x50, 0x4B, 0x03, 0x04]) { return Kind(label: "ZIP", ext: "zip", isText: false, previewable: false) }
        // 바이너리 아니면 UTF-8 텍스트로 본다
        if String(data: data, encoding: .utf8) != nil {
            return Kind(label: "텍스트", ext: "txt", isText: true, previewable: false)
        }
        return Kind(label: "바이너리", ext: "bin", isText: false, previewable: false)
    }

    /// 저장된 blob 의 종류(없으면 nil).
    public func kind(_ sha: String) -> Kind? { get(sha).map(Self.sniff) }
}
