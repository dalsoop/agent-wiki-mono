import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import OpportunityIntelKit

/// 카드 표시 모드
public enum OpportunityCardDisplayMode: Sendable, Equatable {
    case automatic
    case govGrant
    case onlineDeal
}

/// 정부지원사업 전용 부가 메타데이터
public struct OpportunityGovMetadata: Sendable, Equatable {
    public var selfPayRatio: String?
    public var targetAudience: String?
    public var managingAgency: String?
    public var grantScale: String?

    public init(
        selfPayRatio: String? = nil,
        targetAudience: String? = nil,
        managingAgency: String? = nil,
        grantScale: String? = nil
    ) {
        self.selfPayRatio = selfPayRatio
        self.targetAudience = targetAudience
        self.managingAgency = managingAgency
        self.grantScale = grantScale
    }
}

/// 1초 스캔 초고밀도 기회 요약 카드
/// 정부사업 공고, AI 구독 딜 등 어떤 도메인의 OpportunityIntelItem도 균일하고 직관적인 고밀도 카드로 렌더링
public struct Opportunity1SecCard: View {
    public let item: OpportunityIntelItem
    public let displayMode: OpportunityCardDisplayMode
    public let govMetadata: OpportunityGovMetadata?
    public let onSelect: () -> Void
    public let onMuteProvider: (() -> Void)?

    @State private var copiedCode: Bool = false
    @State private var isHovered: Bool = false

    public init(
        item: OpportunityIntelItem,
        displayMode: OpportunityCardDisplayMode = .automatic,
        govMetadata: OpportunityGovMetadata? = nil,
        onSelect: @escaping () -> Void,
        onMuteProvider: (() -> Void)? = nil
    ) {
        self.item = item
        self.displayMode = displayMode
        self.govMetadata = govMetadata
        self.onSelect = onSelect
        self.onMuteProvider = onMuteProvider
    }

    private var resolvedIsGovGrant: Bool {
        switch displayMode {
        case .automatic:
            return item.isGovGrant || govMetadata != nil
        case .govGrant:
            return true
        case .onlineDeal:
            return false
        }
    }

    private var effectiveSelfPayRatio: String? {
        govMetadata?.selfPayRatio ?? item.selfPayRatio
    }

    private var effectiveTargetAudience: String? {
        govMetadata?.targetAudience ?? item.targetAudience
    }

    public var body: some View {
        cardContent
            .padding(11)
            .background(
                Color(nsColor: .controlBackgroundColor)
                    .opacity(isHovered ? 0.95 : 0.75),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isHovered ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.08), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
            .onTapGesture {
                onSelect()
            }
            .contextMenu {
                cardContextMenu
            }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow
            titleRow
            benefitsRow
            if hasMetadataRow {
                metadataFooterView
            }
        }
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 6) {
            domainBadgeView
            providerBadgeView
            if let deadline = item.deadline,
               let days = OpportunityScheduleAudit.daysUntilDeadline(deadline),
               let ddayText = OpportunityScheduleAudit.formatDDay(days) {
                dDayBadgeView(days: days, text: ddayText)
            }
            Spacer(minLength: 4)
            livenessBadgeView
        }
    }

    private var domainBadgeView: some View {
        HStack(spacing: 3) {
            Image(systemName: resolvedIsGovGrant ? "building.columns.fill" : "bolt.fill")
                .font(.system(size: 9, weight: .bold))
            Text(resolvedIsGovGrant ? "정부지원" : "온라인딜")
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(resolvedIsGovGrant ? Color.blue : Color.purple)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background((resolvedIsGovGrant ? Color.blue : Color.purple).opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
    }

    private var providerBadgeView: some View {
        Text(item.provider)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
            .lineLimit(1)
            .frame(minWidth: 0)
    }

    private var titleRow: some View {
        Text(item.title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var benefitsRow: some View {
        HStack(alignment: .center, spacing: 8) {
            if let actual = item.actualValue {
                Text(actual)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(resolvedIsGovGrant ? Color.blue : Color.indigo)
                    .lineLimit(1)
                    .frame(minWidth: 0)
            }
            standardValueView
            rateBadgeView
            selfPayBadgeView
            Spacer(minLength: 4)
            if let code = item.opportunityCode, !code.isEmpty {
                codeTicketButton(code: code)
            }
        }
    }

    @ViewBuilder
    private var standardValueView: some View {
        if let std = item.standardValue {
            if resolvedIsGovGrant {
                Text(std.contains("총") ? std : "총사업비 \(std)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(minWidth: 0)
            } else {
                Text(std.contains("정가") ? std : "정가 \(std)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .strikethrough()
                    .lineLimit(1)
                    .frame(minWidth: 0)
            }
        }
    }

    @ViewBuilder
    private var rateBadgeView: some View {
        if let rate = item.discountOrSupportRate {
            Text(resolvedIsGovGrant ? "지원율 \(rate)%" : "\(rate)% OFF")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(resolvedIsGovGrant ? Color.blue : Color.red)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background((resolvedIsGovGrant ? Color.blue : Color.red).opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
        }
    }

    @ViewBuilder
    private var selfPayBadgeView: some View {
        if resolvedIsGovGrant, let selfPay = effectiveSelfPayRatio, !selfPay.isEmpty {
            Text(selfPay.contains("자부담") ? selfPay : "자부담 \(selfPay)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                .lineLimit(1)
                .frame(minWidth: 0)
        }
    }

    @ViewBuilder
    private var cardContextMenu: some View {
        Button("공식 링크 열기") {
            if let u = URL(string: item.url) {
                #if canImport(AppKit)
                NSWorkspace.shared.open(u)
                #endif
            }
        }
        if let code = item.opportunityCode, !code.isEmpty {
            Button(resolvedIsGovGrant ? "공고/접수번호 복사" : "쿠폰/할인코드 복사") {
                copyToClipboard(code)
            }
        }
        if let onMuteProvider {
            Divider()
            Button("\(item.provider) 알림 관심 없음") {
                onMuteProvider()
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func dDayBadgeView(days: Int, text: String) -> some View {
        let isUrgent = days <= 3 && days >= 0
        let isSoon = days <= 7 && days > 3
        let color: Color = days < 0 ? .secondary : (isUrgent ? .red : (isSoon ? .orange : .blue))

        HStack(spacing: 2) {
            if isUrgent {
                Circle()
                    .fill(Color.red)
                    .frame(width: 5, height: 5)
            }
            Text(text)
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(color.opacity(isUrgent ? 0.15 : 0.08), in: RoundedRectangle(cornerRadius: 4))
    }

    private var livenessBadgeView: some View {
        Text(item.liveness.displayBadge)
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(livenessBackgroundColor, in: Capsule())
    }

    private var hasMetadataRow: Bool {
        if effectiveTargetAudience != nil { return true }
        if let prereq = item.prerequisites, !prereq.isEmpty { return true }
        return false
    }

    @ViewBuilder
    private var metadataFooterView: some View {
        HStack(spacing: 8) {
            // 모집 대상 (정부사업 특화)
            if let audience = effectiveTargetAudience, !audience.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text("대상: \(audience)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(minWidth: 0)
                }
            }

            // 신청 요건 / 전제조건
            if let req = item.prerequisites, !req.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(resolvedIsGovGrant ? .blue.opacity(0.8) : .secondary)
                    Text(resolvedIsGovGrant ? "자격: \(req)" : "조건: \(req)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(minWidth: 0)
                }
            }
        }
        .padding(.top, 1)
    }

    @ViewBuilder
    private func codeTicketButton(code: String) -> some View {
        Button {
            copyToClipboard(code)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: copiedCode ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 9, weight: .bold))
                Text(copiedCode ? "복사됨" : code)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .lineLimit(1)
                    .frame(minWidth: 0)
            }
            .foregroundStyle(copiedCode ? Color.green : Color.primary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(copiedCode ? Color.green.opacity(0.12) : Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(
                        copiedCode ? Color.green : Color.primary.opacity(0.15),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                    )
            )
        }
        .buttonStyle(.plain)
        .help(resolvedIsGovGrant ? "공고/접수번호 복사" : "프로모션/쿠폰코드 복사")
    }

    private func copyToClipboard(_ text: String) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #elseif canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
        withAnimation(.spring(duration: 0.2)) {
            copiedCode = true
        }
        Task {
            do {
                try await Task.sleep(nanoseconds: 1_800_000_000)
                withAnimation(.easeInOut(duration: 0.2)) {
                    copiedCode = false
                }
            } catch {
                withAnimation(.easeInOut(duration: 0.2)) {
                    copiedCode = false
                }
            }
        }
    }

    private var livenessBackgroundColor: Color {
        switch item.liveness {
        case .alive: return Color.green.opacity(0.15)
        case .caution: return Color.orange.opacity(0.18)
        case .expired: return Color.red.opacity(0.15)
        case .dead: return Color.gray.opacity(0.18)
        }
    }
}
