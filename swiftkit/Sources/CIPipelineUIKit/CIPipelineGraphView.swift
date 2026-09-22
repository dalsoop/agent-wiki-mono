import SwiftUI
import AppKit
import StatusIndicatorUIKit

/// CI 파이프라인의 스테이지 및 잡 흐름을 시각화하는 뷰.
public struct CIPipelineGraphView: View {
    public let stages: [CIPipelineStage]
    public var onSelectJob: ((CIJobItem) -> Void)?

    public init(stages: [CIPipelineStage], onSelectJob: ((CIJobItem) -> Void)? = nil) {
        self.stages = stages
        self.onSelectJob = onSelectJob
    }

    public var body: some View {
        if stages.isEmpty {
            Text("No CI jobs found")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(8)
        } else {
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(stages.enumerated()), id: \.element.id) { index, stage in
                        stageCard(stage: stage)
                        if index < stages.count - 1 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 14)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
        }
    }

    private func stageCard(stage: CIPipelineStage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Stage Header
            HStack(spacing: 6) {
                Image(systemName: stage.status.symbolName)
                    .foregroundStyle(stage.status.tone.color)
                    .font(.caption)
                Text(stage.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .frame(minWidth: 0)
                Spacer(minLength: 4)
                Text("\(stage.jobs.count)")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))

            // Job Items
            VStack(alignment: .leading, spacing: 4) {
                ForEach(stage.jobs) { job in
                    CIJobRow(job: job) {
                        if let onSelectJob {
                            onSelectJob(job)
                        } else if let urlStr = job.webURL, let url = URL(string: urlStr) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 150, maxWidth: 220, alignment: .topLeading)
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .cornerRadius(8)
    }
}

/// 개별 CI 잡 뱃지/버튼.
public struct CIJobRow: View {
    public let job: CIJobItem
    public let onTap: () -> Void
    @State private var isHovered = false

    public init(job: CIJobItem, onTap: @escaping () -> Void) {
        self.job = job
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                statusIndicator(job.status)

                Text(job.name)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(minWidth: 0)
                    .foregroundStyle(isHovered ? .primary : .secondary)

                Spacer(minLength: 4)

                if let dur = job.formattedDuration {
                    Text(dur)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                if isHovered && job.webURL != nil {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isHovered ? Color.primary.opacity(0.08) : Color.primary.opacity(0.03))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(tooltipText)
    }

    @ViewBuilder
    private func statusIndicator(_ status: CIJobStatus) -> some View {
        if status.isRunning {
            ProgressView()
                .controlSize(.mini)
        } else {
            Image(systemName: status.symbolName)
                .font(.system(size: 11))
                .foregroundStyle(status.tone.color)
        }
    }

    private var tooltipText: String {
        var lines = ["\(job.name) — \(job.status.rawValue)"]
        if let dur = job.formattedDuration {
            lines.append("소요 시간: \(dur)")
        }
        if let runner = job.runner, !runner.isEmpty {
            lines.append("러너: \(runner)")
        }
        if let url = job.webURL {
            lines.append("클릭 시 열기: \(url)")
        }
        return lines.joined(separator: "\n")
    }
}
