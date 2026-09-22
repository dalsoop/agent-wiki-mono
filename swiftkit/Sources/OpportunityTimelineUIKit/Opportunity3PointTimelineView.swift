import SwiftUI
import OpportunityIntelKit

/// 3포인트 미니멀 타임라인 컴포넌트
/// 무거운 12개월 간트 대신 [① 접수시작] -> [② D-3 마감방어/알림] -> [③ 마감/갱신] 핵심 3지점만 가시화
public struct Opportunity3PointTimelineView: View {
    public let milestones: [OpportunityMilestone]
    public let headline: String

    public init(milestones: [OpportunityMilestone], headline: String = "핵심 타임라인 (3-Point)") {
        self.milestones = milestones
        self.headline = headline
    }

    /// 기회 항목 모델을 받아 정부사업/딜 맞춤형 3-Point 마일스톤을 자동 생성하는 편리한 생성자
    public init(item: OpportunityIntelItem, today: Date = Date()) {
        self.milestones = OpportunityScheduleAudit.generate3PointMilestones(
            firstSeen: item.firstSeen,
            deadline: item.deadline,
            actualValueText: item.actualValue ?? (item.isGovGrant ? "지원 접수 개시" : "할인 혜택 개시"),
            isGovGrant: item.isGovGrant,
            today: today
        )
        self.headline = item.isGovGrant ? "정부지원사업 일정 (3-Point)" : "프로모션·갱신 일정 (3-Point)"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(headline)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
            }

            if milestones.isEmpty {
                Text("일정 정보가 없습니다.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                milestoneRailView
            }
        }
        .padding(11)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Subviews

    private var milestoneRailView: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(milestones.enumerated()), id: \.element.id) { index, m in
                milestoneColumn(index: index, milestone: m)
            }
        }
    }

    @ViewBuilder
    private func milestoneColumn(index: Int, milestone m: OpportunityMilestone) -> some View {
        VStack(spacing: 5) {
            milestoneTrackNode(index: index, milestone: m)

            Text(m.dateString)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(minWidth: 0)

            Text(m.title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(color(for: m.phase))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .frame(minWidth: 0)

            Text(m.detail)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minWidth: 0)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func milestoneTrackNode(index: Int, milestone m: OpportunityMilestone) -> some View {
        ZStack {
            GeometryReader { geo in
                let w = geo.size.width
                let midY = geo.size.height / 2

                if index > 0 {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: midY))
                        p.addLine(to: CGPoint(x: w / 2, y: midY))
                    }
                    .stroke(m.isReached ? Color.blue : Color.secondary.opacity(0.25), lineWidth: 2)
                }

                if index < milestones.count - 1 {
                    Path { p in
                        p.move(to: CGPoint(x: w / 2, y: midY))
                        p.addLine(to: CGPoint(x: w, y: midY))
                    }
                    .stroke(milestones[index + 1].isReached ? Color.blue : Color.secondary.opacity(0.25), lineWidth: 2)
                }
            }
            .frame(height: 16)

            indicatorView(for: m)
        }
        .frame(height: 16)
    }

    @ViewBuilder
    private func indicatorView(for m: OpportunityMilestone) -> some View {
        ZStack {
            if m.isReached {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 16, height: 16)
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
            } else if m.phase == .warning {
                Circle()
                    .fill(Color.orange.opacity(0.2))
                    .frame(width: 16, height: 16)
                Circle()
                    .stroke(Color.orange, lineWidth: 2)
                    .frame(width: 16, height: 16)
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
            } else {
                Circle()
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .frame(width: 16, height: 16)
                Circle()
                    .stroke(Color.secondary.opacity(0.4), lineWidth: 2)
                    .frame(width: 16, height: 16)
                Circle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 4, height: 4)
            }
        }
    }

    private func color(for phase: OpportunityMilestone.MilestonePhase) -> Color {
        switch phase {
        case .start: return .primary
        case .warning: return .orange
        case .completion: return .primary
        }
    }
}
