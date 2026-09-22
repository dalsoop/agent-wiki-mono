import ApplicationServices
import CoreGraphics

/// Fallback discovery for views you did NOT tag with `.inspect`. Walks THIS
/// process's own Accessibility tree and finds the deepest element containing a
/// screen point, reading role/label/value/frame — so any on-screen element is
/// pickable, just without a source location (the AX tree has no `file:line`).
///
/// It traverses only our own app (`AXUIElementCreateApplication(getpid())`), never
/// the system-wide element at a point. That's deliberate: a system-wide hit-test
/// returns whatever is frontmost — including *other apps' windows and content* —
/// which would both mis-target and leak another app's private UI. Staying inside
/// our process makes that impossible and also survives our window being partly
/// occluded.
public enum AccessibilityProbe {
    /// Reading the AX tree may require the Accessibility permission; check first.
    public static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Deepest element of *our* app containing `point` (screen coords, top-left
    /// origin, points), as an `.accessibility` element. Nil if untrusted or none.
    public static func element(atScreenPoint point: CGPoint) -> InspectedElement? {
        guard isTrusted else { return nil }
        let app = AXUIElementCreateApplication(getpid())
        guard let hit = deepest(app, containing: point) else { return nil }

        let role = string(hit, kAXRoleAttribute) ?? "AXUnknown"
        let label = string(hit, kAXTitleAttribute)
            ?? string(hit, kAXDescriptionAttribute)
            ?? ""
        var values: [String: String] = [:]
        if let value = string(hit, kAXValueAttribute), !value.isEmpty {
            values["value"] = value
        }
        return InspectedElement(
            name: label.isEmpty ? role : label,
            file: "", line: 0,
            kind: role,
            selector: "(accessibility)",
            frame: frame(of: hit),
            values: values,
            origin: .accessibility)
    }

    /// Smallest (most specific) descendant whose frame contains `point`.
    private static func deepest(_ element: AXUIElement, containing point: CGPoint,
                                depth: Int = 0) -> AXUIElement? {
        if depth > 25 { return nil }  // guard against pathological trees
        let f = frame(of: element)
        let hitsSelf = f.width > 0 && f.height > 0 && f.contains(point)
        var best: AXUIElement? = hitsSelf ? element : nil
        var bestArea = hitsSelf ? Double(f.width * f.height) : .infinity

        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children {
                guard let deep = deepest(child, containing: point, depth: depth + 1) else { continue }
                let df = frame(of: deep)
                let area = Double(df.width * df.height)
                if area <= bestArea { best = deep; bestArea = area }
            }
        }
        return best
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    /// The element's screen frame (top-left origin). Best-effort — zero if absent.
    private static func frame(of element: AXUIElement) -> CGRect {
        var origin = CGPoint.zero
        var size = CGSize.zero
        var positionRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
           let positionRef, CFGetTypeID(positionRef) == AXValueGetTypeID() {
            let val = unsafeDowncast(positionRef, to: AXValue.self)
            AXValueGetValue(val, .cgPoint, &origin)
        }
        var sizeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
           let sizeRef, CFGetTypeID(sizeRef) == AXValueGetTypeID() {
            let val = unsafeDowncast(sizeRef, to: AXValue.self)
            AXValueGetValue(val, .cgSize, &size)
        }
        return CGRect(origin: origin, size: size)
    }
}
