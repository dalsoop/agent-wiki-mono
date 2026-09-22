import SwiftUI

/// L1 Viewport: 이미지, Mermaid 다이어그램, 벡터 그래픽을 위한 무한 줌 & 패닝 캔버스 뷰포트
public struct ZoomableCanvasContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                    .ignoresSafeArea()

                content()
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { val in
                                let delta = val / lastScale
                                lastScale = val
                                scale = min(max(scale * delta, 0.1), 10.0)
                            }
                            .onEnded { _ in
                                lastScale = 1.0
                            }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { val in
                                offset = CGSize(
                                    width: lastOffset.width + val.translation.width,
                                    height: lastOffset.height + val.translation.height
                                )
                            }
                            .onEnded { _ in
                                lastOffset = offset
                            }
                    )
            }
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: 8) {
                    Button(action: { zoomIn() }) {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    Button(action: { zoomOut() }) {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    Button("100%") {
                        resetZoom()
                    }
                    .font(.caption.monospaced())
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(16)
            }
        }
    }

    private func zoomIn() {
        withAnimation(.easeInOut(duration: 0.2)) {
            scale = min(scale * 1.25, 10.0)
        }
    }

    private func zoomOut() {
        withAnimation(.easeInOut(duration: 0.2)) {
            scale = max(scale / 1.25, 0.1)
        }
    }

    private func resetZoom() {
        withAnimation(.easeInOut(duration: 0.2)) {
            scale = 1.0
            offset = .zero
            lastOffset = .zero
        }
    }
}
