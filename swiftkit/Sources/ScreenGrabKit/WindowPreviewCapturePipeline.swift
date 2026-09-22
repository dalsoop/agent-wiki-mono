import Foundation
import CoreGraphics
import os
#if os(macOS)
import AppKit
@preconcurrency import ScreenCaptureKit

/// 동시 WindowServer IPC 요청 수를 제한하여 마우스 랙 및 WindowServer 스파이크를 방지하는 비동기 세마포어
public actor CaptureThrottleLimiter {
    public static let shared = CaptureThrottleLimiter(maxConcurrent: 2)

    private let maxConcurrent: Int
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(maxConcurrent: Int = 2) {
        self.maxConcurrent = maxConcurrent
    }

    public func withPermit<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        await acquire()
        defer { release() }
        return try await operation()
    }

    public func withPermitNonThrowing<T: Sendable>(_ operation: @Sendable () async -> T) async -> T {
        await acquire()
        defer { release() }
        return await operation()
    }

    private func acquire() async {
        if running < maxConcurrent {
            running += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if !waiters.isEmpty {
            let next = waiters.removeFirst()
            next.resume()
        } else {
            running -= 1
        }
    }
}

/// `SCShareableContent` 메타데이터 2.0초 TTL 캐싱 및 SCK 기반 단일 윈도우 스크린샷 캡처 전용 Actor
public actor SCContentCacheActor {
    public static let shared = SCContentCacheActor()

    private var cachedContent: SCShareableContent?
    private var fetchedAt: Date?
    private let ttl: TimeInterval = 2.0

    public init() {
        setupSleepObservers()
    }

    private nonisolated func setupSleepObservers() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { await self?.flush() }
        }
        center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { await self?.flush() }
        }
    }

    /// ⌥ (Option) 키다운 등 사전 사용자 제스처 시점에 백그라운드 선제 워밍업 (0ms 첫 프레임 보장)
    public func preload() async {
        _ = await getContent()
    }

    public func flush() {
        cachedContent = nil
        fetchedAt = nil
    }

    public func getContent() async -> (SCShareableContent?, Double) {
        let now = Date()
        if let cached = cachedContent, let at = fetchedAt, now.timeIntervalSince(at) < ttl {
            return (cached, 0.0)
        }
        let start = Date()
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            let elapsed = Date().timeIntervalSince(start) * 1000.0
            self.cachedContent = content
            self.fetchedAt = now
            return (content, elapsed)
        } catch {
            return (nil, 0.0)
        }
    }

    /// ScreenCaptureKit 기반 윈도우 썸네일 캡처 (버퍼 Clamp: 최대 360x240 @2x, GPU 스케일러 활용)
    public func captureSingleSCK(
        target: WindowCaptureTarget,
        scale: Double
    ) async -> WindowCaptureResultItem? {
        let (content, _) = await getContent()
        guard let scWindows = content?.windows else { return nil }

        // 정확한 WindowID 매칭 우선, 없을 시 PID + Title 2차 매칭
        guard let matchedWindow = scWindows.first(where: { $0.windowID == target.windowID })
            ?? scWindows.first(where: { $0.owningApplication?.processID == target.pid && $0.title == target.title }) else {
            return nil
        }

        let frame = matchedWindow.frame
        let aspect = frame.height > 0 ? (frame.width / frame.height) : 1.5
        let baseW = 360.0
        let baseH = baseW / aspect
        let clampedH = min(baseH, 240.0)
        let clampedW = min(clampedH * aspect, 360.0)

        let pixelW = max(Int(clampedW * scale), 16)
        let pixelH = max(Int(clampedH * scale), 16)

        let filter = SCContentFilter(desktopIndependentWindow: matchedWindow)
        let config = SCStreamConfiguration()
        config.width = pixelW
        config.height = pixelH
        config.scalesToFit = true
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        config.pixelFormat = kCVPixelFormatType_32BGRA

        let start = Date()
        do {
            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let duration = Date().timeIntervalSince(start) * 1000.0
            return WindowCaptureResultItem(id: target.id, image: cgImage, durationMs: duration)
        } catch {
            return nil
        }
    }
}

/// ScreenCaptureKit + CGWindowList 2단계 하이브리드 실시간 캡처 파이프라인
public final class WindowPreviewCapturePipeline: @unchecked Sendable {
    public static let shared = WindowPreviewCapturePipeline()

    private let scActor = SCContentCacheActor.shared
    private let limiter = CaptureThrottleLimiter.shared

    public init() {}

    public func preload() async {
        await scActor.preload()
    }

    public func flush() async {
        await scActor.flush()
    }

    /// 단일 윈도우 캡처 (쓰로틀링 적용 + SCK 시도 ➔ CGWindowList 폴백)
    public func captureWindow(target: WindowCaptureTarget, scale: Double) async -> WindowCaptureResultItem? {
        await limiter.withPermitNonThrowing {
            // Tier 1: ScreenCaptureKit
            if let sckResult = await self.scActor.captureSingleSCK(target: target, scale: scale) {
                return sckResult
            }

            // Tier 2: CGWindowListCreateImage 폴백
            return self.captureFallbackCG(target: target, scale: scale)
        }
    }

    /// 우선순위 정렬 및 비동기 스트리밍 배치 캡처
    public func captureBatchStream(
        targets: [WindowCaptureTarget],
        scale: Double
    ) -> AsyncStream<WindowCaptureResultItem> {
        AsyncStream { continuation in
            Task {
                // Priority 기준 정렬 (0: 선택/호버 ➔ 1: 인접 ➔ 2: 나머지)
                let sortedTargets = targets.sorted { $0.priority < $1.priority }

                await withTaskGroup(of: WindowCaptureResultItem?.self) { group in
                    for target in sortedTargets {
                        group.addTask {
                            await self.captureWindow(target: target, scale: scale)
                        }
                    }

                    for await result in group {
                        if let result {
                            continuation.yield(result)
                        }
                    }
                    continuation.finish()
                }
            }
        }
    }

    private func captureFallbackCG(target: WindowCaptureTarget, scale: Double) -> WindowCaptureResultItem? {
        let start = Date()
        typealias CGWindowListCreateImageFunc = @convention(c) (CGRect, CGWindowListOption, CGWindowID, CGWindowImageOption) -> CGImage?
        guard let handle = dlopen(nil, RTLD_LAZY),
              let sym = dlsym(handle, "CGWindowListCreateImage") else {
            return nil
        }
        let fn = unsafeBitCast(sym, to: CGWindowListCreateImageFunc.self)
        guard let cgImage = fn(
            .null,
            .optionIncludingWindow,
            target.windowID,
            [.boundsIgnoreFraming, .bestResolution]
        ) else {
            return nil
        }

        // 360x240 이내로 다운샘플링하여 VRAM 절약
        let targetSize = CGSize(width: 360 * scale, height: 240 * scale)
        guard let colorSpace = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: nil,
                width: Int(targetSize.width),
                height: Int(targetSize.height),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return WindowCaptureResultItem(id: target.id, image: cgImage, durationMs: Date().timeIntervalSince(start) * 1000.0)
        }

        ctx.interpolationQuality = .medium
        ctx.draw(cgImage, in: CGRect(origin: .zero, size: targetSize))
        guard let downscaled = ctx.makeImage() else {
            return WindowCaptureResultItem(id: target.id, image: cgImage, durationMs: Date().timeIntervalSince(start) * 1000.0)
        }

        let duration = Date().timeIntervalSince(start) * 1000.0
        return WindowCaptureResultItem(id: target.id, image: downscaled, durationMs: duration)
    }
}

#endif
