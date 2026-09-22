import SwiftUI
import PreviewEngineKit

/// L1 Viewport: PDF, HWPX, PPTX를 위한 페이지 분할 스크롤 컨테이너
public struct PaginatedScrollContainer<PageContent: View>: View {
    public let pageCount: Int
    @Binding public var currentPageIndex: Int
    public let pageViewBuilder: (Int) -> PageContent

    public init(
        pageCount: Int,
        currentPageIndex: Binding<Int>,
        @ViewBuilder pageViewBuilder: @escaping (Int) -> PageContent
    ) {
        self.pageCount = pageCount
        self._currentPageIndex = currentPageIndex
        self.pageViewBuilder = pageViewBuilder
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 20) {
                    ForEach(0..<pageCount, id: \.self) { index in
                        VStack(spacing: 8) {
                            pageViewBuilder(index)
                                .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)

                            Text("\(index + 1) / \(pageCount)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        .id(index)
                    }
                }
                .padding(.vertical, 24)
            }

            Divider()

            // 하단 페이지 네비게이션 툴바
            HStack {
                Button(action: { if currentPageIndex > 0 { currentPageIndex -= 1 } }) {
                    Image(systemName: "chevron.up")
                }
                .disabled(currentPageIndex <= 0)

                Text("페이지 \(currentPageIndex + 1) / \(pageCount)")
                    .font(.caption.monospaced())

                Button(action: { if currentPageIndex < pageCount - 1 { currentPageIndex += 1 } }) {
                    Image(systemName: "chevron.down")
                }
                .disabled(currentPageIndex >= pageCount - 1)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }
}
