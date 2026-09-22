import Foundation
import CoreGraphics
#if os(macOS)
import AppKit
import QuartzCore

/// 마우스 호버 및 키보드 선택 시 실시간 창 미리보기를 제공하는 플라이아웃 팝오버 컨트롤러.
/// nonactivatingPanel(.screenSaver + 1)을 사용하여 현재 작업 중인 앱의 포커스를 침범하지 않으며,
/// CALayer 듀얼 버퍼 크로스페이드로 무깜빡임(Zero-Flicker)을 보장합니다.
@MainActor
public final class WindowPreviewPopoverController: NSObject {
    public static let shared = WindowPreviewPopoverController()

    private var popoverPanel: NSPanel?
    private var debounceTask: Task<Void, Never>?
    private var currentTargetID: String?
    public var previewSize: CGSize = CGSize(width: 360, height: 225)

    // Double-buffered CALayers for flicker-free crossfades
    private let contentLayer = CALayer()
    private let frontImageLayer = CALayer()
    private let backImageLayer = CALayer()
    private var isFrontActive = true
    private var onCommitHandler: ((String) -> Void)?

    public override init() {
        super.init()
        buildPopoverPanel()
    }

    private func buildPopoverPanel() {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: previewSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        // HUD 본체(.screenSaver) 위에 올리기 위해 .screenSaver + 1 레벨 지정
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = false
        panel.hidesOnDeactivate = false
        panel.alphaValue = 0

        let root = PopoverClickableView(frame: NSRect(origin: .zero, size: previewSize))
        root.clickHandler = { [weak self] in
            guard let self, let targetID = self.currentTargetID else { return }
            self.onCommitHandler?(targetID)
            self.dismiss()
        }
        root.wantsLayer = true

        contentLayer.frame = root.bounds
        contentLayer.cornerRadius = 14
        contentLayer.masksToBounds = true
        contentLayer.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.85).cgColor
        contentLayer.borderWidth = 1.0
        contentLayer.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor

        frontImageLayer.frame = contentLayer.bounds
        frontImageLayer.contentsGravity = .resizeAspect
        backImageLayer.frame = contentLayer.bounds
        backImageLayer.contentsGravity = .resizeAspect
        backImageLayer.opacity = 0

        contentLayer.addSublayer(backImageLayer)
        contentLayer.addSublayer(frontImageLayer)
        root.layer?.addSublayer(contentLayer)

        panel.contentView = root
        self.popoverPanel = panel
    }

    /// 타깃 윈도우에 대한 프리뷰 팝오버를 표시합니다.
    /// - Parameters:
    ///   - targetID: 창 고유 ID
    ///   - anchorScreenRect: 기준이 되는 HUD 카드/독 아이콘의 화면 좌표
    ///   - cachedImage: SWR 캐시에 보관된 직전 이미지 (0ms 즉시 표시)
    ///   - debounceMs: 마우스 커서 스침 방지를 위한 디바운스 밀리초 (기본 50ms)
    ///   - onCommit: 사용자가 팝오버를 클릭했을 때 실행할 콜백
    public func present(
        for targetID: String,
        anchorScreenRect: NSRect,
        cachedImage: CGImage?,
        debounceMs: UInt64 = 50,
        onCommit: @escaping (String) -> Void
    ) {
        debounceTask?.cancel()
        self.onCommitHandler = onCommit

        debounceTask = Task { @MainActor in
            if debounceMs > 0 {
                try? await Task.sleep(nanoseconds: debounceMs * 1_000_000)
            }
            guard !Task.isCancelled else { return }
            self.executePresent(targetID: targetID, anchorScreenRect: anchorScreenRect, cachedImage: cachedImage)
        }
    }

    private func executePresent(targetID: String, anchorScreenRect: NSRect, cachedImage: CGImage?) {
        guard let panel = popoverPanel, let screen = NSScreen.main else { return }
        self.currentTargetID = targetID

        // 앵커 좌표 계산: 카드 상단 중앙 (상단 공간 부족 시 하단으로 반전)
        let screenFrame = screen.visibleFrame
        var originX = anchorScreenRect.midX - previewSize.width / 2
        var originY = anchorScreenRect.maxY + 12

        if originY + previewSize.height > screenFrame.maxY {
            originY = anchorScreenRect.minY - previewSize.height - 12
        }
        originX = max(screenFrame.minX + 16, min(originX, screenFrame.maxX - previewSize.width - 16))

        panel.setFrameOrigin(NSPoint(x: originX, y: originY))
        panel.orderFrontRegardless()

        let effectiveImage = cachedImage ?? WindowThumbnailCache.shared.lookup(id: targetID).value?.image
        if let image = effectiveImage {
            applyCrossfade(image: image)
        }

        // 만약 여전히 이미지가 없으면 온디맨드 즉시 캡처 시도
        if effectiveImage == nil, let windowID = UInt32(targetID) {
            Task { [weak self] in
                let target = WindowCaptureTarget(id: targetID, windowID: windowID, priority: 0)
                let scale = screen.backingScaleFactor
                if let result = await WindowPreviewCapturePipeline.shared.captureWindow(target: target, scale: scale) {
                    WindowThumbnailCache.shared.storeBatch(items: [result], completedTargets: [target])
                    await MainActor.run {
                        self?.updatePreviewImage(result.image, for: targetID)
                    }
                }
            }
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1.0
        }
    }

    /// 비동기적으로 새 캡처 이미지가 도착했을 때 팝오버 내용 갱신
    public func updatePreviewImage(_ image: CGImage, for targetID: String) {
        guard currentTargetID == targetID, let panel = popoverPanel, panel.alphaValue > 0 else { return }
        applyCrossfade(image: image)
    }

    private func applyCrossfade(image: CGImage) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))

        if isFrontActive {
            backImageLayer.contents = image
            backImageLayer.opacity = 1.0
            frontImageLayer.opacity = 0.0
        } else {
            frontImageLayer.contents = image
            frontImageLayer.opacity = 1.0
            backImageLayer.opacity = 0.0
        }
        isFrontActive.toggle()
        CATransaction.commit()
    }

    /// 팝오버 닫기
    public func dismiss() {
        debounceTask?.cancel()
        currentTargetID = nil
        guard let panel = popoverPanel, panel.alphaValue > 0 else { return }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.08
            panel.animator().alphaValue = 0.0
        }, completionHandler: { [weak panel] in
            MainActor.assumeIsolated {
                panel?.orderOut(nil)
            }
        })
    }
}

/// 팝오버 클릭 이벤트를 감지하여 소비하는 내부 뷰
private final class PopoverClickableView: NSView {
    var clickHandler: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        clickHandler?()
    }
}

#endif
