import AppKit
import CoreGraphics
import InspectorState
import SwiftUI

private func waitWithTimeout(_ process: Process, seconds: TimeInterval = 30) {
    let item = DispatchWorkItem { process.terminate() }
    DispatchQueue.global().asyncAfter(deadline: .now() + seconds, execute: item)
    process.waitUntilExit()
    item.cancel()
}

/// Owns the inspector's live state and does the actual capture work. One
/// instance is installed per window tree by `.inspectorRoot()`; a toolbar/menu
/// toggle flips `isActive`, the overlay feeds it hover/click points, and it
/// turns a pick into (a crisp marked screenshot + a Markdown context block on
/// the clipboard).
@MainActor
public final class InspectorController: ObservableObject {
    /// When true the overlay intercepts the mouse to highlight + pick elements.
    @Published public var isActive = false
    /// Live registry of every `.inspect(...)` element, replaced whenever a frame
    /// changes. Read it to build a "jump to element" list or capture by name;
    /// only InspectorKit writes it.
    @Published public internal(set) var elements: [InspectedElement] = []
    /// Element currently under the cursor while active (for highlight). Also set
    /// briefly during capture so the highlight lands in the screenshot.
    @Published var hovered: InspectedElement?
    /// Last element the user picked — handy for a "copied ✓ SettingsView.swift:42"
    /// confirmation in a status bar.
    @Published public private(set) var lastCaptured: InspectedElement?

    /// Set true when a capture skipped its screenshot because Screen Recording
    /// wasn't granted (the text context is still copied). Observe this to prompt
    /// the user — e.g. `PermissionKit.Permission.screenRecording.gate(...)`.
    @Published public private(set) var needsScreenRecordingPermission = false

    /// Set true when a pick fell on an untagged view but the Accessibility
    /// permission isn't granted, so the fallback couldn't run. Observe this to
    /// prompt — e.g. `PermissionKit.Permission.accessibility.gate(...)`.
    @Published public private(set) var needsAccessibilityPermission = false

    /// Optional log tail. When set, each pick appends the most recent log lines
    /// to the copied context so the AI sees "this element + what was logged".
    public weak var log: InspectorLog?
    /// How many recent log lines to attach on capture.
    public var attachedLogLines = 12

    public init() {}

    /// Flip pick mode on/off. Wire this to a keyboard shortcut or menu item.
    public func toggle() {
        isActive.toggle()
        if !isActive { hovered = nil }
    }

    // MARK: Hit-testing

    /// The most specific element under `point`: of all registered frames that
    /// contain it, the smallest by area (a child sits inside its parent).
    func element(at point: CGPoint) -> InspectedElement? {
        elements
            .filter { $0.frame.width > 0 && $0.frame.height > 0 && $0.frame.contains(point) }
            .min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }

    func hover(at point: CGPoint?) {
        guard isActive else { hovered = nil; return }
        hovered = point.flatMap(element(at:))
    }

    /// Click at `point` while active → capture whatever is under it. A tagged
    /// `.inspect` element wins (full source); otherwise fall back to the
    /// Accessibility tree at the cursor so untagged views are still pickable.
    func pick(at point: CGPoint) {
        guard isActive else { return }
        if let el = element(at: point) {
            Task { await capture(el) }
            return
        }
        // Untagged area → Accessibility fallback at the cursor's screen point.
        guard AccessibilityProbe.isTrusted else {
            needsAccessibilityPermission = true
            return
        }
        needsAccessibilityPermission = false
        let mouse = NSEvent.mouseLocation                      // screen, bottom-left
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        let axPoint = CGPoint(x: mouse.x, y: screenHeight - mouse.y)  // top-left for AX
        if let el = AccessibilityProbe.element(atScreenPoint: axPoint) {
            Task { await capture(el) }
        }
    }

    // MARK: Capture

    /// Copy this element's AI context block to the clipboard, alongside a crisp
    /// screenshot of the window with the element highlighted, then leave pick
    /// mode. Public so a menu action can capture a known element directly.
    ///
    /// The trick: we keep the SwiftUI highlight (blue box + label) drawn while
    /// the shot is taken, so the "marking" is done by SwiftUI at the exact,
    /// already-correct on-screen position — no manual coordinate math, and the
    /// capture is the real rendered window (unlike `cacheDisplay`, which washes
    /// out prominent buttons and text).
    public func capture(_ el: InspectedElement) async {
        isActive = true
        // Only tagged elements get the SwiftUI highlight — their frame is in our
        // coordinate space. Accessibility frames are screen coords, so we skip the
        // highlight and just capture the window.
        if el.origin == .tagged {
            hovered = el
            do {
                try await Task.sleep(nanoseconds: 300_000_000) // lint:allow-sleep
            } catch {
                lastCaptured = nil
            }
        }

        let shot = captureHighlightedWindow(for: el)
        log?.refresh()
        let logs = log?.recentLines(limit: attachedLogLines) ?? []
        let context = el.promptContext(screenshotPath: shot, logs: logs)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(context, forType: .string)

        // Persist the pick so the headless MCP server can serve it to the AI
        // without a clipboard round-trip.
        let snapshot = InspectorSnapshot(
            element: .init(
                name: el.name, kind: el.kind, selector: el.selector,
                source: el.origin == .tagged ? el.sourceRef : "(untagged — accessibility)",
                frame: [el.frame.origin.x, el.frame.origin.y, el.frame.width, el.frame.height],
                values: el.values),
            screenshotPath: shot,
            logs: logs,
            promptContext: context,
            timestamp: Date().timeIntervalSince1970)
        try? InspectorStateStore.save(snapshot)

        lastCaptured = el
        isActive = false
        hovered = nil
    }

    /// Capture just our window (with the highlight showing) to a PNG via
    /// `screencapture -l<windowID>`, which grabs exactly what's on screen — crisp
    /// buttons, text, materials. Needs Screen Recording permission; returns the
    /// file path, or nil if capture failed (e.g. permission not granted).
    private func captureHighlightedWindow(for el: InspectedElement) -> String? {
        // Preflight Screen Recording (never prompts). Without it screencapture
        // yields a blank/denied image, so skip the shot and flag it instead.
        guard CGPreflightScreenCaptureAccess() else {
            needsScreenRecordingPermission = true
            return nil
        }
        needsScreenRecordingPermission = false

        let window = NSApp.keyWindow
            ?? NSApp.mainWindow
            ?? NSApp.windows.first { $0.isVisible && $0.contentView != nil }
        guard let window else { return nil }

        let safe = el.name.isEmpty
            ? "element"
            : String(el.name.filter { $0.isLetter || $0.isNumber })
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("inspector-\(safe.isEmpty ? "element" : safe)-\(el.line).png")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -x: silent, -o: no window shadow, -l<id>: just this window.
        task.arguments = ["-x", "-o", "-l\(window.windowNumber)", url.path]
        do {
            try task.run()
        } catch {
            return nil
        }
        waitWithTimeout(task, seconds: 10)

        guard task.terminationStatus == 0,
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url.path
    }
}
