import KnowledgeBaseWikiCore
import SwiftUI

/// Studio·Reader 헤더용 world 전환. 로컬 1인칭과 원격 공유를 섹션으로 나눈다.
public struct WikiWorldChooser: View {
    public var items: [WikiWorldListItem]
    @Binding public var selection: String
    public var onChange: () -> Void

    public init(
        items: [WikiWorldListItem],
        selection: Binding<String>,
        onChange: @escaping () -> Void = {}
    ) {
        self.items = items
        self._selection = selection
        self.onChange = onChange
    }

    private var current: WikiWorldListItem? {
        items.first { $0.name == selection } ?? items.first
    }

    public var body: some View {
        Menu {
            ForEach(WikiWorldLayer.allCases) { layer in
                let rows = items.filter { $0.layer == layer }
                if !rows.isEmpty {
                    Section(layer.groupTitle) {
                        ForEach(rows) { row in
                            Button {
                                selection = row.name
                                onChange()
                            } label: {
                                Label {
                                    VStack(alignment: .leading) {
                                        Text(row.title)
                                        Text(row.subtitle).font(.caption)
                                    }
                                } icon: {
                                    Image(systemName: layer.systemImage)
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: current?.layer.systemImage ?? "globe")
                VStack(alignment: .leading, spacing: 0) {
                    Text(current?.title ?? selection)
                        .font(.callout.weight(.semibold))
                    Text(current?.layer.badge ?? "")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 280, alignment: .leading)
        }
        .menuStyle(.borderlessButton)
        .accessibilityIdentifier("wiki-world-chooser")
        .help(current?.subtitle ?? "원장 고르기")
    }
}
