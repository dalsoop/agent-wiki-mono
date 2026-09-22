import Foundation

/// codex 이미지 생성 도구는 결과 PNG 를 `~/.codex/generated_images/<uuid>/exec-*.png` 에 쓰고,
/// 지정 경로로의 복사는 **보장하지 않는다**(모델이 복사 지시를 놓치면 타깃에 파일이 안 생김).
///
/// 이 로케이터가 실행 시각 이후 생성된 최신 PNG 를 찾아 타깃으로 직접 복사해 그 틈을 메운다.
/// 즉흥 호출 대비 sprite-forge 가 "탄탄한" 이유의 핵심 — codex 의 복사 여부에 의존하지 않는다.
public struct CodexImageLocator: Sendable {
    public let root: String

    public init(root: String? = nil) {
        self.root = root ?? (NSHomeDirectory() as NSString).appendingPathComponent(".codex/generated_images")
    }

    /// `since`(실행 직전 시각) 이후 mtime 을 가진 가장 최근 PNG 경로. 없으면 nil.
    public func newestImage(since: Date) -> String? {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: URL(fileURLWithPath: root),
                                     includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                                     options: [.skipsHiddenFiles]) else { return nil }
        var best: (path: String, date: Date)?
        for case let url as URL in en {
            guard url.pathExtension.lowercased() == "png" else { continue }
            guard let v = try? url.resourceValues(forKeys: [.contentModificationDateKey]) else { continue }
            guard let m = v.contentModificationDate, m >= since else { continue }
            if best == nil || m > best!.date { best = (url.path, m) }
        }
        return best?.path
    }

    /// 타깃에 파일이 없으면 최신 생성 이미지를 복사한다. 복사 성공 여부 반환.
    @discardableResult
    public func ensureCopied(to target: String, since: Date) -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: target) { return true }
        guard let src = newestImage(since: since) else { return false }
        do { try fm.createDirectory(atPath: (target as NSString).deletingLastPathComponent,
                                withIntermediateDirectories: true) } catch { _ = error }
        try? fm.removeItem(atPath: target)
        do { try fm.copyItem(atPath: src, toPath: target); return true }
        catch { return false }
    }
}
