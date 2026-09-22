import ApplicationServices
import CoreGraphics
import Foundation

/// macOS 접근성(AXUIElement) 트리 읽기의 공용 primitive.
///
/// ~6개 앱(window-snap·keyboard-typer·menu-fold·flowlog·context-characters·keyboard-coding-typer)이
/// 같은 systemWide→focusedApp→focusedWindow 체인과 copy-attribute 헬퍼를 인라인으로 복붙했다.
/// 이 열거형이 그 정본이다. 앱별 로직(옵저버 생명주기·write-back·역할 판정)은 앱에 남는다.
public enum AXTree {
    /// 접근성 권한 부여 여부(프롬프트 없음).
    public static var isTrusted: Bool { AXIsProcessTrusted() }

    // MARK: - 루트 엘리먼트

    public static func systemWide() -> AXUIElement {
        AXUIElementCreateSystemWide()
    }

    public static func application(pid: pid_t) -> AXUIElement {
        AXUIElementCreateApplication(pid)
    }

    /// system-wide → `kAXFocusedApplication`.
    public static func focusedApplication() -> AXUIElement? {
        element(systemWide(), kAXFocusedApplicationAttribute)
    }

    /// system-wide → `kAXFocusedUIElement`.
    public static func focusedElement() -> AXUIElement? {
        element(systemWide(), kAXFocusedUIElementAttribute)
    }

    /// 앱 엘리먼트 → `kAXFocusedWindow`.
    public static func focusedWindow(pid: pid_t) -> AXUIElement? {
        element(application(pid: pid), kAXFocusedWindowAttribute)
    }

    /// 현재 포커스된 앱의 포커스 윈도우.
    public static func focusedWindow() -> AXUIElement? {
        guard let app = focusedApplication() else { return nil }
        return element(app, kAXFocusedWindowAttribute)
    }

    // MARK: - 속성 읽기

    /// 임의 속성의 raw 값.
    public static func copyAttribute(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return result == .success ? value : nil
    }

    /// 값이 AXUIElement 인 속성(포커스 체인용). 타입 가드 포함.
    public static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copyAttribute(element, attribute) else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    /// 문자열 속성.
    public static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        copyAttribute(element, attribute) as? String
    }

    /// `kAXTitle`.
    public static func title(_ element: AXUIElement) -> String? {
        string(element, kAXTitleAttribute)
    }

    /// `kAXRole`.
    public static func role(_ element: AXUIElement) -> String? {
        string(element, kAXRoleAttribute)
    }

    /// `kAXParent`.
    public static func parent(_ element: AXUIElement) -> AXUIElement? {
        self.element(element, kAXParentAttribute)
    }

    /// `kAXChildren` → `[AXUIElement]`(1단계).
    public static func children(_ element: AXUIElement) -> [AXUIElement] {
        copyAttribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    /// `AXValue`(.cgPoint) 속성.
    public static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let value = copyAttribute(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        let axValue = unsafeDowncast(value, to: AXValue.self)
        return AXValueGetValue(axValue, .cgPoint, &point) ? point : nil
    }

    /// `AXValue`(.cgSize) 속성.
    public static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let value = copyAttribute(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        let axValue = unsafeDowncast(value, to: AXValue.self)
        return AXValueGetValue(axValue, .cgSize, &size) ? size : nil
    }

    /// `kAXPosition` + `kAXSize` → frame.
    public static func frame(_ element: AXUIElement) -> CGRect? {
        guard let origin = point(element, kAXPositionAttribute),
              let dimension = size(element, kAXSizeAttribute) else { return nil }
        return CGRect(origin: origin, size: dimension)
    }
}
