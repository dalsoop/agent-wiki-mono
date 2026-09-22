import SwiftUI
import PreviewEngineKit

/// L1 Viewport: XLSX, CSV, SQLite 결과를 위한 2D 가상화 그리드 뷰
public struct VirtualGridTableView: View {
    public let provider: any TabularGridProvider

    public init(provider: any TabularGridProvider) {
        self.provider = provider
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 헤더 영역
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 1) {
                    Text("#")
                        .font(.caption.monospaced().bold())
                        .frame(width: 48, height: 28)
                        .background(Color(nsColor: .controlBackgroundColor))

                    ForEach(0..<min(provider.columnCount, 50), id: \.self) { col in
                        Text(provider.headerTitle(column: col))
                            .font(.caption.bold())
                            .frame(width: 120, height: 28)
                            .background(Color(nsColor: .controlBackgroundColor))
                    }
                }
                .padding(.horizontal, 1)
            }
            .background(Color(nsColor: .separatorColor))

            Divider()

            // 행 데이터 영역 (LazyVStack으로 가상화 렌더링)
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(spacing: 1) {
                    ForEach(0..<min(provider.rowCount, 1000), id: \.self) { row in
                        HStack(spacing: 1) {
                            Text("\(row + 1)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .frame(width: 48, height: 24)
                                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))

                            ForEach(0..<min(provider.columnCount, 50), id: \.self) { col in
                                Text(provider.cellValue(row: row, column: col))
                                    .font(.caption)
                                    .lineLimit(1)
                                    .frame(minWidth: 20)
                                    .frame(width: 120, height: 24, alignment: .leading)
                                    .padding(.horizontal, 4)
                                    .background(Color(nsColor: .windowBackgroundColor))
                            }
                        }
                    }
                }
                .padding(1)
            }
            .background(Color(nsColor: .separatorColor))
        }
    }
}
