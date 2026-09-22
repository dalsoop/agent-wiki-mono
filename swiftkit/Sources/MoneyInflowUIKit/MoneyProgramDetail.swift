#if os(macOS)
import AppKit
import SwiftUI
import MoneyInflowKit

public struct ProgramDetailCopy: Sendable, Equatable {
    public var summary: String
    public var targetAudience: String
    public var period: String
    public var provider: String
    public var whyMatched: String
    public var apply: String
    public var sourceLink: String
    public var closed: String
    public var today: String

    public init(
        summary: String,
        targetAudience: String,
        period: String,
        provider: String,
        whyMatched: String,
        apply: String,
        sourceLink: String,
        closed: String,
        today: String
    ) {
        self.summary = summary
        self.targetAudience = targetAudience
        self.period = period
        self.provider = provider
        self.whyMatched = whyMatched
        self.apply = apply
        self.sourceLink = sourceLink
        self.closed = closed
        self.today = today
    }
}

public struct MoneyProgramDetail: View {
    public var source: any MoneySource
    public var score: MatchScore
    public var copy: ProgramDetailCopy
    public var deadline: DeadlineCopy

    public init(
        source: any MoneySource,
        score: MatchScore,
        copy: ProgramDetailCopy,
        deadline: DeadlineCopy = DeadlineCopy()
    ) {
        self.source = source
        self.score = score
        self.copy = copy
        self.deadline = deadline
    }

    public var body: some View {
        ScrollView { column }
    }

    private var column: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            titleRow
            matchReasons
            if !source.summary.isEmpty { block(copy.summary, source.summary) }
            if !source.targetAudienceText.isEmpty { block(copy.targetAudience, source.targetAudienceText) }
            block(copy.period, periodText)
            if !source.providerName.isEmpty { block(copy.provider, source.providerName) }
            actionRow
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var titleRow: some View {
        HStack(alignment: .top, spacing: 16) {
            ScoreCircle(score: score.score)
            LazyVStack(alignment: .leading, spacing: 4) {
                Text(source.title).font(.title2.bold())
                    .lineLimit(3)
                    .frame(minWidth: 0)
                DeadlineBadge(period: source.period, prominent: true, copy: deadline)
            }
        }
    }

    private var matchReasons: some View {
        LazyVStack(alignment: .leading, spacing: 6) {
            Text(copy.whyMatched).font(.subheadline.bold()).foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(minWidth: 0)
            FlowChips(items: score.reasons)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            if let url = source.applyURL ?? source.detailURL {
                Button(copy.apply) { NSWorkspace.shared.open(url) }
                    .buttonStyle(.borderedProminent)
            }
            if let url = source.detailURL, source.applyURL != nil {
                Button(copy.sourceLink) { NSWorkspace.shared.open(url) }
            }
        }
        .padding(.top, 8)
    }

    private var periodText: String {
        var parts = [source.period.rawText]
        if let d = source.daysUntilClose() {
            parts.append(d > 0 ? "D-\(d)" : (d == 0 ? copy.today : copy.closed))
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func block(_ title: String, _ body: String) -> some View {
        LazyVStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.bold()).foregroundStyle(.secondary)
            Text(body).font(.body).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
