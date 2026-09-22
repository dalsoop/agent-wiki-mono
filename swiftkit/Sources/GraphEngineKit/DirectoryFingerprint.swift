import FastDiskIOKit
import FileIdentityKit
import Foundation

/// 디렉터리 신선도 지문 — 파일 시스템 mtime+size 합으로 변경을 감지.
///
/// 도메인 무관: 위키 원장, 함대 레지스트리, 세션 로그 모두 같은 패턴으로 쓴다.
/// 내용 해시가 아니라 mtime+size — 수천 파일을 매번 다시 안 읽으려고(InteropKit
/// CapabilitySearcher 한 줄 캐시와 같은 철학).
/// 한 장 id 는 `FileIdentityKit` (`FileIdentity.worm`).
public enum DirectoryFingerprint {

    /// `root` 아래 확장자 `ext` 파일들의 (개수:총바이트:최신mtime) 지문.
    public static func fingerprint(root: URL, fileExtension ext: String) -> String {
        DirectoryStatFingerprint.fingerprint(root: root, fileExtension: ext)
    }

    /// `root` 아래 확장자 `ext` 파일 전체(재귀).
    public static func files(root: URL, fileExtension ext: String) -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let entries = FastDirectoryScanner.scanEntries(in: root.path, skipping: [])
        return entries.compactMap { entry in
            guard !entry.isDirectory else { return nil }
            let url = URL(fileURLWithPath: entry.path)
            return url.pathExtension == ext ? url : nil
        }
    }
}
