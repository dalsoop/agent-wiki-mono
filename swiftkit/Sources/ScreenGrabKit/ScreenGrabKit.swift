import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@preconcurrency import ScreenCaptureKit

// 이름 주의: 이 모듈은 Apple 프레임워크 `ScreenCaptureKit` 과 이름이 겹치면 안 되므로
// `ScreenGrabKit` 으로 둔다(내부에서 Apple SCK 를 import 해야 하기 때문).

/// 화면 캡처 실패 모드.
public enum ScreenGrabError: Error, Sendable {
    case noDisplay
    case cropFailed
    case encodeFailed
}

/// ScreenCaptureKit(`SCScreenshotManager`) 기반 디스플레이/영역/윈도우 캡처 공용기.
///
/// screenshot·flowlog·lecture-tools·context-characters 등이 각자 손으로 짠 SCK 캡처 루프의 정본.
/// 권한 게이트는 swiftkit `PermissionKit.Permission.screenRecording` 을 쓴다(여기서 재구현 안 함).
public struct ScreenGrabber: Sendable {
    public var showsCursor: Bool

    public init(showsCursor: Bool = false) {
        self.showsCursor = showsCursor
    }

    /// 캡처 가능한 디스플레이 목록.
    public func availableDisplays() async throws -> [SCDisplay] {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true).displays
    }

    /// 캡처 가능한 온스크린 윈도우 목록.
    public func availableWindows() async throws -> [SCWindow] {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true).windows
    }

    /// 디스플레이 전체를 CGImage 로 캡처. `excludingBundleIdentifier` 를 주면 그 앱 윈도우를 제외한다
    /// (예: freeze 배경 캡처에서 자기 창 제외).
    public func captureDisplay(
        _ display: SCDisplay,
        excludingBundleIdentifier bundleIdentifier: String? = nil
    ) async throws -> CGImage {
        let filter: SCContentFilter
        if let bundleIdentifier {
            let content = try await SCShareableContent.current
            let excluded = content.applications.filter { $0.bundleIdentifier == bundleIdentifier }
            filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])
        } else {
            filter = SCContentFilter(display: display, excludingWindows: [])
        }
        let config = SCStreamConfiguration()
        config.width = Int(CGFloat(display.width) * CGFloat(filter.pointPixelScale))
        config.height = Int(CGFloat(display.height) * CGFloat(filter.pointPixelScale))
        config.showsCursor = showsCursor
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// 단일 윈도우를 CGImage 로 캡처(그림자·화면 밖 무시).
    public func captureWindow(_ window: SCWindow) async throws -> CGImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width = Int(CGFloat(window.frame.width) * CGFloat(filter.pointPixelScale))
        config.height = Int(CGFloat(window.frame.height) * CGFloat(filter.pointPixelScale))
        config.showsCursor = showsCursor
        config.scalesToFit = true
        config.ignoreShadowsSingleWindow = true
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// 디스플레이의 부분 영역(포인트 좌표, 좌상단 원점)을 캡처. 내부적으로 전체를 잡아 픽셀 crop.
    public func captureRegion(_ selection: CGRect, on display: SCDisplay) async throws -> CGImage {
        let full = try await captureDisplay(display)
        let scale = CGFloat(full.width) / CGFloat(display.width)
        let pixelRect = CaptureGeometry.pixelRect(
            selection: selection,
            displayHeightPoints: CGFloat(display.height),
            scale: scale
        )
        guard let cropped = full.cropping(to: pixelRect) else { throw ScreenGrabError.cropFailed }
        return cropped
    }
}

/// 좌표/크롭 산술(순수 CoreGraphics). SCK 없이 테스트 가능.
public enum CaptureGeometry {
    /// 포인트 선택(좌상단 원점) → 픽셀 사각형. y flip 없음(SCScreenshotManager 출력은 좌상단 원점).
    public static func pixelRect(selection: CGRect, displayHeightPoints: CGFloat, scale: CGFloat) -> CGRect {
        CGRect(
            x: selection.origin.x * scale,
            y: selection.origin.y * scale,
            width: selection.width * scale,
            height: selection.height * scale
        )
    }
}

/// CGImage → 인코딩된 이미지 데이터.
public enum ScreenGrabEncoder {
    /// PNG 데이터.
    public static func pngData(_ image: CGImage) -> Data? {
        encode(image, as: UTType.png.identifier as CFString, quality: 1.0)
    }

    /// JPEG 데이터(quality 0...1).
    public static func jpegData(_ image: CGImage, quality: Double = 0.8) -> Data? {
        encode(image, as: UTType.jpeg.identifier as CFString, quality: quality)
    }

    private static func encode(_ image: CGImage, as type: CFString, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, type, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}
