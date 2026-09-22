import SwiftUI

/// 쿼리 히스토리 목록의 **레이아웃과 동작**만 공유한다.
///
/// 세 뷰어의 HistoryView 는 실질적으로 같은 화면인데, 각 앱이 자기 `L10nKey` enum 을
/// 따로 갖고 있어(`noHistoryTitle` vs `noHistory` 등) 파일이 갈라져 있었다. 그 드리프트를
/// 먼저 통일하려 들면 세 앱의 Localizable.strings 를 동시에 건드려야 한다 —
/// 대신 **문자열은 앱이 이미 번역해서 넘기고**, 여기서는 화면만 맡는다.
public protocol QueryHistoryModel: ObservableObject {
    var recentQueries: [String] { get }
    /// 앱쪽 `openQueryTab(sql: String? = nil)` 과 오버로드가 겹치지 않도록 이름을 분리한다.
    func openHistoryQuery(sql: String)
}

public struct QueryHistoryView<Model: QueryHistoryModel>: View {
    @ObservedObject private var model: Model
    private let title: String
    private let emptyTitle: String
    private let emptyDescription: String

    public init(model: Model, title: String, emptyTitle: String, emptyDescription: String) {
        self.model = model
        self.title = title
        self.emptyTitle = emptyTitle
        self.emptyDescription = emptyDescription
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            if model.recentQueries.isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: "clock.arrow.circlepath",
                    description: Text(emptyDescription)
                )
            } else {
                List(model.recentQueries, id: \.self) { query in
                    Button {
                        model.openHistoryQuery(sql: query)
                    } label: {
                        Text(query)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(2)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
    }
}
