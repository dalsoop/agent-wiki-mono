import AppKit
import SwiftUI
import DBViewerKit

/// 쿼리 결과 표. **databaseviewer-{sqlite,postgresql,swift} 세 앱에 바이트 단위로 같은
/// 파일이 복제돼 있던 것**을 여기로 올렸다 — 드라이버와 무관하고 앱의 AppModel 도 안 본다.
///
/// 세 뷰어의 나머지 UI 는 갈라져 있어(AppModel 만 1091줄 차이) 한 번에 못 합친다.
/// 이 모듈은 "차이가 없다고 실측된 것부터" 올리는 자리다.
public struct ResultGridView: View {
    let result: QueryResult
    let visibleColumnCount: Int

    public init(result: QueryResult, visibleColumnCount: Int) {
        self.result = result
        self.visibleColumnCount = visibleColumnCount
    }

    @State private var columnWidths: [CGFloat] = []
    @State private var dragStartWidth: (index: Int, width: CGFloat)?

    private let defaultWidth: CGFloat = 150
    private let minColumnWidth: CGFloat = 56

    public var body: some View {
        GeometryReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    headerRow
                    ForEach(result.rows.indices, id: \.self) { rowIndex in
                        dataRow(rowIndex)
                    }
                }
                .padding(8)
                // Pin to the top-left; only the empty area (not the columns) fills
                // the viewport, so the table never stretches to 100% width.
                .frame(minWidth: proxy.size.width, minHeight: proxy.size.height, alignment: .topLeading)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .onAppear(perform: syncWidths)
        .onChange(of: result.columns.count) { _, _ in syncWidths() }
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            ForEach(visibleColumnIndices, id: \.self) { index in
                headerCell(index)
            }
        }
    }

    private func dataRow(_ rowIndex: Int) -> some View {
        let row = result.rows[rowIndex]
        return HStack(spacing: 0) {
            ForEach(visibleColumnIndices, id: \.self) { columnIndex in
                cell(columnIndex < row.count ? row[columnIndex] : "", columnIndex: columnIndex, isHeader: false)
            }
        }
    }

    private func headerCell(_ index: Int) -> some View {
        cell(result.columns[index], columnIndex: index, isHeader: true)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside {
                            NSCursor.resizeLeftRight.set()
                        } else {
                            NSCursor.arrow.set()
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if dragStartWidth?.index != index {
                                    dragStartWidth = (index, width(index))
                                }
                                let start = dragStartWidth?.width ?? width(index)
                                setWidth(index, max(minColumnWidth, start + value.translation.width))
                            }
                            .onEnded { _ in dragStartWidth = nil }
                    )
            }
    }

    private func cell(_ value: String, columnIndex: Int, isHeader: Bool) -> some View {
        // Spreadsheet convention: header + text left-aligned, numbers right-aligned.
        let alignment: Alignment = isHeader
            ? .leading
            : (Self.isNumeric(value) ? .trailing : .leading)

        return Text(value.isEmpty ? " " : value)
            .font(.system(.caption, design: .monospaced))
            .fontWeight(isHeader ? .semibold : .regular)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .frame(width: width(columnIndex), alignment: alignment)
            .background(isHeader ? Color(nsColor: .controlBackgroundColor) : Color(nsColor: .textBackgroundColor))
            .border(Color(nsColor: .separatorColor), width: 0.5)
    }

    private var visibleColumnIndices: [Int] {
        let count = min(max(visibleColumnCount, 1), result.columns.count)
        return Array(result.columns.indices.prefix(count))
    }

    private func width(_ index: Int) -> CGFloat {
        index < columnWidths.count ? columnWidths[index] : defaultWidth
    }

    private func setWidth(_ index: Int, _ value: CGFloat) {
        if columnWidths.count != result.columns.count {
            syncWidths()
        }
        guard index < columnWidths.count else { return }
        columnWidths[index] = value
    }

    private func syncWidths() {
        if columnWidths.count != result.columns.count {
            columnWidths = Array(repeating: defaultWidth, count: result.columns.count)
        }
    }

    private static func isNumeric(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        if Int(value) != nil { return true }
        if Double(value) != nil { return true }
        return false
    }
}
