import CoreGraphics
import Foundation

/// One inspectable element that a view registered via `.inspect(...)`. Everything
/// here is captured at the *call site* of `.inspect` (so `file`/`line` point at
/// your own SwiftUI source, not at InspectorKit) plus the live on-screen `frame`
/// measured in the inspector's coordinate space.
///
/// The whole point of this type is `promptContext`: a compact, deterministic
/// Markdown block you paste straight into an AI coding assistant so it knows
/// *exactly* which element you meant — no more "the blue button near the top".
public struct InspectedElement: Identifiable, Equatable, Sendable {
    /// Stable identity = source location. Two `.inspect` calls on the same line
    /// are indistinguishable by design (they're the same line of code).
    public var id: String { "\(file):\(line)" }

    /// Human label you passed to `.inspect("...")`. Empty is allowed.
    public let name: String
    /// Source file, as `#fileID` gives it: `"MyApp/SettingsView.swift"`.
    public let file: String
    /// 1-based source line of the `.inspect` call.
    public let line: Int
    /// Free-form kind hint you passed (e.g. `"Button"`, `"TextField"`). Optional.
    public let kind: String
    /// The view-hierarchy path you optionally supplied, e.g. `"Root > Settings"`.
    /// InspectorKit can't read SwiftUI's private tree, so this is what you label.
    public let selector: String
    /// Live frame in the root inspector coordinate space (origin = root's origin).
    public let frame: CGRect
    /// Runtime values you attached (e.g. `["text": name, "valid": "\(isValid)"]`).
    /// SwiftUI's private tree isn't readable, so you supply what matters — these
    /// refresh with the view and travel into the AI context on capture.
    public let values: [String: String]
    /// Where this element came from: a `.inspect(...)` tag (full source location)
    /// or an Accessibility fallback (no source, but role/label/value from the AX
    /// tree — how we cover views you didn't tag).
    public let origin: Origin

    public enum Origin: String, Sendable, Equatable { case tagged, accessibility }

    public init(name: String, file: String, line: Int,
                kind: String = "", selector: String = "", frame: CGRect = .zero,
                values: [String: String] = [:], origin: Origin = .tagged) {
        self.name = name
        self.file = file
        self.line = line
        self.kind = kind
        self.selector = selector
        self.frame = frame
        self.values = values
        self.origin = origin
    }

    /// Just the file's basename, dropping the module prefix `#fileID` carries.
    public var fileBasename: String {
        (file as NSString).lastPathComponent
    }

    /// `SettingsView.swift:42` — the clickable form editors/AI understand.
    public var sourceRef: String {
        "\(fileBasename):\(line)"
    }
}

public extension InspectedElement {
    /// The Markdown block copied to the clipboard. Designed to be pasted into an
    /// AI assistant as unambiguous "this is the element I'm pointing at" context.
    /// `screenshotPath` is included only when a marked screenshot was written;
    /// `logs` (most recent last) are appended as a second block when non-empty.
    func promptContext(screenshotPath: String? = nil, logs: [String] = []) -> String {
        let f = frame
        var lines: [String] = [
            "```",
            "element:  \(name.isEmpty ? "(unnamed)" : name)\(kind.isEmpty ? "" : " (\(kind))")",
        ]
        if !selector.isEmpty {
            lines.append("selector: \(selector)")
        }
        if origin == .accessibility {
            lines.append("source:   (untagged — accessibility only, no file:line)")
        } else {
            lines.append("source:   \(sourceRef)")
        }
        lines.append(String(
            format: "frame:    x=%.0f y=%.0f w=%.0f h=%.0f",
            f.origin.x, f.origin.y, f.size.width, f.size.height))
        if !values.isEmpty {
            lines.append("values:")
            for key in values.keys.sorted() {
                lines.append("  \(key) = \(values[key] ?? "")")
            }
        }
        if let screenshotPath {
            lines.append("shot:     \(screenshotPath)")
        }
        lines.append("```")
        if !logs.isEmpty {
            lines.append("")
            lines.append("recent logs:")
            lines.append("```")
            lines.append(contentsOf: logs)
            lines.append("```")
        }
        return lines.joined(separator: "\n")
    }
}
