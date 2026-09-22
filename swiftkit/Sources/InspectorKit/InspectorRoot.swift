import SwiftUI

/// Wires a window tree for inspection: installs the shared coordinate space,
/// gathers every `.inspect(...)` element into the controller, and lays the
/// pick-mode overlay on top. Call this once, high in your view tree (e.g. on the
/// window's root view), passing a controller your app owns as `@StateObject`.
struct InspectorRootModifier: ViewModifier {
    @ObservedObject var controller: InspectorController

    func body(content: Content) -> some View {
        content
            .coordinateSpace(.named(InspectorSpace.name))
            .onPreferenceChange(InspectedElementsKey.self) { value in
                // onPreferenceChange's closure is non-isolated under Swift 6
                // strict concurrency; hop to the main actor to touch the
                // MainActor-isolated controller. `value` is Sendable.
                Task { @MainActor in controller.elements = value }
            }
            .overlay { InspectorOverlay(controller: controller) }
            .environmentObject(controller)
    }
}

public extension View {
    /// Enable InspectorKit for this subtree. Own the controller in your app:
    /// ```swift
    /// @StateObject private var inspector = InspectorController()
    /// var body: some View {
    ///     ContentView()
    ///         .inspectorRoot(inspector)
    ///         .toolbar { InspectorToggleButton(inspector) }
    /// }
    /// ```
    /// In release you can simply not call this — the `.inspect` probes stay
    /// inert and nothing intercepts input.
    func inspectorRoot(_ controller: InspectorController) -> some View {
        modifier(InspectorRootModifier(controller: controller))
    }
}

/// Drop-in toolbar/menu button that toggles pick mode and reflects its state.
public struct InspectorToggleButton: View {
    @ObservedObject private var controller: InspectorController

    public init(_ controller: InspectorController) {
        self.controller = controller
    }

    public var body: some View {
        Button {
            controller.toggle()
        } label: {
            Image(systemName: controller.isActive
                ? "viewfinder.circle.fill"
                : "viewfinder.circle")
        }
        // ⌘⇧I toggles pick mode without reaching for the toolbar.
        .keyboardShortcut("i", modifiers: [.command, .shift])
        .help(controller.isActive
            ? "지목 모드 끄기 (⌘⇧I)"
            : "요소를 지목해 AI 컨텍스트를 클립보드로 복사 (⌘⇧I)")
    }
}
