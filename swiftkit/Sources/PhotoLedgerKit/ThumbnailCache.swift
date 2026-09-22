#if canImport(AppKit)
import AppKit
import Foundation
import ImageIO

/// blob id 별 작은 썸네일. 동시 디코드 한도 + 용량 제한.
public actor ThumbnailCache {
    public static let shared = ThumbnailCache()

    private let memory = NSCache<NSString, NSImage>()
    private var negative: Set<String> = []
    private let maxPixel: CGFloat = 96
    private let maxConcurrent = 6
    private var inflight = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init() {
        memory.countLimit = 400
    }

    public func image(for blob: LedgerBlobRef, shareRoot: String?) async -> NSImage? {
        let key = blob.id as NSString
        if let hit = memory.object(forKey: key) {
            return hit
        }
        if negative.contains(blob.id) {
            return nil
        }

        await acquire()
        defer { release() }

        if let hit = memory.object(forKey: key) {
            return hit
        }
        if negative.contains(blob.id) {
            return nil
        }

        let root = shareRoot
        let rel = blob.rel
        let maxPixel = self.maxPixel
        let loaded: NSImage? = await Task.detached(priority: .utility) {
            guard let root else { return nil }
            let url = LedgerShareRoot.fileURL(shareRoot: root, rel: rel)
            return Self.loadThumbnail(at: url, maxPixel: maxPixel)
        }.value

        if let loaded {
            memory.setObject(loaded, forKey: key)
        } else {
            negative.insert(blob.id)
            if negative.count > 2_000 {
                negative.removeAll(keepingCapacity: true)
            }
        }
        return loaded
    }

    public func clear() {
        memory.removeAllObjects()
        negative.removeAll()
    }

    private func acquire() async {
        while inflight >= maxConcurrent {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                waiters.append(cont)
            }
        }
        inflight += 1
    }

    private func release() {
        inflight = max(0, inflight - 1)
        guard !waiters.isEmpty else { return }
        let next = waiters.removeFirst()
        next.resume()
    }

    private static func loadThumbnail(at url: URL, maxPixel: CGFloat) -> NSImage? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixel),
        ]
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }
        guard let image = NSImage(contentsOf: url) else { return nil }
        return scaled(image, maxPixel: maxPixel)
    }

    private static func scaled(_ image: NSImage, maxPixel: CGFloat) -> NSImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxPixel, longest > 0 else { return image }
        let scale = maxPixel / longest
        let target = NSSize(width: size.width * scale, height: size.height * scale)
        let out = NSImage(size: target)
        out.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: target),
            from: NSRect(origin: .zero, size: size),
            operation: .copy,
            fraction: 1
        )
        out.unlockFocus()
        return out
    }
}
#endif
