import SwiftUI
import StatusIndicatorUIKit

/// 파이프라인 항목을 클릭 시 인라인으로 확장하여 스테이지/잡 그래프를 표시하는 아코디언 컨테이너.
public struct CIPipelineAccordionContainer<Header: View>: View {
    public let isExpanded: Bool
    public let onToggle: () -> Void
    public let stages: [CIPipelineStage]?
    public let isLoading: Bool
    public let errorMessage: String?
    public let onRetry: (() -> Void)?
    @ViewBuilder public let header: () -> Header

    public init(
        isExpanded: Bool,
        onToggle: @escaping () -> Void,
        stages: [CIPipelineStage]?,
        isLoading: Bool = false,
        errorMessage: String? = nil,
        onRetry: (() -> Void)? = nil,
        @ViewBuilder header: @escaping () -> Header
    ) {
        self.isExpanded = isExpanded
        self.onToggle = onToggle
        self.stages = stages
        self.isLoading = isLoading
        self.errorMessage = errorMessage
        self.onRetry = onRetry
        self.header = header
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            if isExpanded {
                expandedContent
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            header()
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().padding(.vertical, 4)

            if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(error)
            } else if let stages {
                CIPipelineGraphView(stages: stages)
                    .padding(.top, 2)
            }
        }
        .padding(.leading, 24)
        .padding(.trailing, 8)
        .padding(.bottom, 6)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var loadingView: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("CI 작업 불러오는 중…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }

    private func errorView(_ error: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let onRetry {
                Button("재시도", action: onRetry)
                    .font(.caption2)
                    .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
    }
}
