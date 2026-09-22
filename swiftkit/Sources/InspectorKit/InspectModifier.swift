import SwiftUI

/// The named coordinate space the whole inspector works in. The root
/// (`.inspectorRoot()`) installs it; every `.inspect(...)` measures its frame
/// relative to it, so the overlay's hit-testing and the registered frames share
/// one origin.
enum InspectorSpace {
    static let name = "InspectorKit.root"
}

/// Collects every `.inspect(...)` element up the view tree into a single array.
/// SwiftUI merges child preferences into the ancestor that reads them, which is
/// how the root gets the full list without any global mutable state.
struct InspectedElementsKey: PreferenceKey {
    static let defaultValue: [InspectedElement] = []
    static func reduce(value: inout [InspectedElement], nextValue: () -> [InspectedElement]) {
        value.append(contentsOf: nextValue())
    }
}

/// Attaches a transparent measuring probe behind a view and publishes that
/// view's live frame + its *source location*. The source location is the trick:
/// because `file`/`line` are captured as default arguments of `View.inspect`,
/// they resolve at the call site — i.e. your SwiftUI file, not this file.
struct InspectModifier: ViewModifier {
    let name: String
    let kind: String
    let selector: String
    let file: String
    let line: Int
    let values: [String: String]

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: InspectedElementsKey.self,
                    value: [InspectedElement(
                        name: name,
                        file: file,
                        line: line,
                        kind: kind,
                        selector: selector,
                        frame: geo.frame(in: .named(InspectorSpace.name)),
                        values: values)]
                )
            }
        )
    }
}

public extension View {
    /// Mark this view as a pickable element for InspectorKit.
    ///
    /// Add one line per element you want to be able to point at:
    /// ```swift
    /// Button("Save") { ... }
    ///     .inspect("SaveButton", kind: "Button")
    /// ```
    /// When the inspector overlay is active, clicking this view copies an
    /// unambiguous context block (name + `\(file):\(line)` + frame + optional
    /// screenshot) to the clipboard, ready to paste into an AI assistant.
    ///
    /// `file`/`line` are captured automatically from *this call site* — leave
    /// them at their defaults. In release builds where you don't call
    /// `.inspectorRoot()`, this modifier still compiles but its overhead is a
    /// single empty background probe.
    /// Attach runtime `values` to travel into the AI context, e.g.
    /// `.inspect("NameField", values: ["text": name, "valid": "\(isValid)"])`.
    func inspect(_ name: String = "",
                 kind: String = "",
                 selector: String = "",
                 values: [String: String] = [:],
                 file: String = #fileID,
                 line: Int = #line) -> some View {
        modifier(InspectModifier(
            name: name, kind: kind, selector: selector, file: file, line: line,
            values: values))
    }
}
