import SwiftUI

/// The pick-mode overlay. Only present (and only intercepting the mouse) while
/// `controller.isActive`. It highlights the most specific `.inspect` element
/// under the cursor and, on click, hands the point to the controller to capture.
struct InspectorOverlay: View {
    @ObservedObject var controller: InspectorController

    var body: some View {
        if controller.isActive {
            ZStack(alignment: .topLeading) {
                // A near-invisible fill that still receives hits, so clicks in
                // pick mode go to us instead of the real controls underneath.
                Color.white.opacity(0.001)
                    .contentShape(Rectangle())

                if let el = controller.hovered {
                    highlight(el)
                }
            }
            .onContinuousHover(coordinateSpace: .named(InspectorSpace.name)) { phase in
                switch phase {
                case .active(let point): controller.hover(at: point)
                case .ended:             controller.hover(at: nil)
                }
            }
            .gesture(
                SpatialTapGesture(coordinateSpace: .named(InspectorSpace.name))
                    .onEnded { controller.pick(at: $0.location) }
            )
        }
    }

    /// A bold red box + caption tag on the hovered element, positioned in the
    /// shared inspector coordinate space via `.offset`. Red + thick so it reads
    /// clearly in the screenshot, in light or dark mode.
    @ViewBuilder
    private func highlight(_ el: InspectedElement) -> some View {
        let f = el.frame
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.red.opacity(0.18))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.red, lineWidth: 3)
            )
            .frame(width: f.width, height: f.height)
            .offset(x: f.minX, y: f.minY)
            .allowsHitTesting(false)

        Text(el.name.isEmpty ? el.sourceRef : "\(el.name) · \(el.sourceRef)")
            .font(.caption.weight(.semibold).monospaced())
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.red, in: Capsule())
            .foregroundStyle(.white)
            .fixedSize()
            .offset(x: f.minX, y: max(0, f.minY - 24))
            .allowsHitTesting(false)
    }
}
