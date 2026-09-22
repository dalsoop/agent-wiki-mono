import AppKit

/// 프로세스 공용 이미지 디코드 캐시 — 앱 공용 SSOT.
///
/// 근본 문제: SwiftUI 뷰가 `List`/`ForEach` 셀마다 렌더 때마다 `NSImage(contentsOf:)` 로 파일을
/// 재디코드하면 스크롤·재렌더가 느려진다(실측: social-draft·detailpage·screenshot·evidence 갤러리).
/// 이 로더는 URL 로 디코드 결과를 `NSCache`(스레드세이프·메모리압박 시 자동축출)에 담아
/// 셀이 렌더마다 물어도 첫 1회만 디코드한다.
///
/// 같은 URL = 같은 내용인 파일(스크린샷·증거·썸네일 등)에 적합하다. 같은 경로의 내용이 바뀌는
/// 경우엔 `invalidate(url)` 로 비운다. 콘텐츠가 자주 바뀌면 파일명에 해시/버전을 넣어 URL 자체가
/// 달라지게 하는 편이 낫다.
public enum CachedImage {
    // NSCache 는 내부적으로 스레드세이프하므로 프로세스 공용 static 으로 안전하게 공유한다.
    nonisolated(unsafe) private static let cache: NSCache<NSURL, NSImage> = {
        let c = NSCache<NSURL, NSImage>()
        c.countLimit = 512   // 셀 수백 개 갤러리에서도 상한. 초과 시 LRU 축출.
        return c
    }()

    /// URL 의 이미지를 디코드 캐시로 돌려준다(없으면 nil).
    public static func load(_ url: URL) -> NSImage? {
        let key = url as NSURL
        if let hit = cache.object(forKey: key) { return hit }
        guard let image = NSImage(contentsOf: url) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    public static func invalidate(_ url: URL) { cache.removeObject(forKey: url as NSURL) }
    public static func clear() { cache.removeAllObjects() }
}
