#if os(macOS)
import SwiftUI
import MoneyInflowKit

public struct MoneyMatchCopy: Sendable, Equatable {
    public var emptyTitle: String
    public var loadingHint: String
    public var emptyHint: String

    public init(emptyTitle: String, loadingHint: String, emptyHint: String) {
        self.emptyTitle = emptyTitle
        self.loadingHint = loadingHint
        self.emptyHint = emptyHint
    }
}

public struct MoneyProgramCard: View {
    public var source: any MoneySource
    public var score: MatchScore
    public var deadline: DeadlineCopy

    public init(source: any MoneySource, score: MatchScore, deadline: DeadlineCopy = DeadlineCopy()) {
        self.source = source
        self.score = score
        self.deadline = deadline
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ScoreCircle(score: score.score)
            VStack(alignment: .leading, spacing: 5) {
                Text(source.title).font(.body.bold())
                    .lineLimit(2)
                    .frame(minWidth: 0)
                HStack(spacing: 6) {
                    DeadlineBadge(period: source.period, copy: deadline)
                    ForEach(score.reasons.prefix(2), id: \.self) { r in
                        Text(r).font(.caption2)
                            .lineLimit(1)
                            .frame(minWidth: 0)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
                if !source.providerName.isEmpty {
                    Text(source.providerName).font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(minWidth: 0)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

public struct MoneyMatchList: View {
    public var items: [MatchedItem]
    @Binding public var selectedID: String?
    public var loading: Bool
    public var copy: MoneyMatchCopy
    public var deadline: DeadlineCopy

    public init(
        items: [MatchedItem],
        selectedID: Binding<String?>,
        loading: Bool,
        copy: MoneyMatchCopy,
        deadline: DeadlineCopy = DeadlineCopy()
    ) {
        self.items = items
        self._selectedID = selectedID
        self.loading = loading
        self.copy = copy
        self.deadline = deadline
    }

    public var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedID) {
                ForEach(items) { item in
                    MoneyProgramCard(source: item.source, score: item.score, deadline: deadline)
                        .tag(item.id)
                }
            }
            .overlay {
                if items.isEmpty {
                    ContentUnavailableView(
                        copy.emptyTitle,
                        systemImage: "tray",
                        description: Text(loading ? copy.loadingHint : copy.emptyHint)
                    )
                }
            }
        }
    }
}
#endif
