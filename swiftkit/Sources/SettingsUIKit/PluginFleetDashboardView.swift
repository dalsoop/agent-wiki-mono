import SwiftUI
import PluginKit

/// 앱 설정 창 또는 관리자 화면에서 등록된 Interop 어댑터 목록과 상태를 조회하는 공용 SwiftUI 뷰
public struct PluginFleetDashboardView: View {
    public let context: PluginExecutionContext
    public let registry: PluginRegistry
    public let onExecuteAction: ((String, String, [String]) -> Void)?
    
    @State private var hubSummary: PluginFleetHub.TenantHubSummary?
    @State private var isLoading = false
    @State private var selectedPlugin: PluginFleetHub.PluginStatusCard?
    @State private var executionLogs: [String] = []
    
    public init(
        context: PluginExecutionContext = .current,
        registry: PluginRegistry = .shared,
        onExecuteAction: ((String, String, [String]) -> Void)? = nil
    ) {
        self.context = context
        self.registry = registry
        self.onExecuteAction = onExecuteAction
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // 상단 헤더
            headerBar
            
            Divider()
            
            // 중앙 어댑터 카드 목록
            if isLoading && hubSummary == nil {
                ProgressView("어댑터 상태 수집 중...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let summary = hubSummary {
                pluginList(summary: summary)
            } else {
                ContentUnavailableView("등록된 어댑터 없음", systemImage: "puzzlepiece.extension")
            }
            
            // 하단 실행 로그/콘솔
            if !executionLogs.isEmpty {
                Divider()
                logConsole
            }
        }
        .task {
            refreshSummary()
        }
    }
    
    // MARK: - Header Bar
    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .foregroundColor(.accentColor)
                    Text("Interop 어댑터")
                        .font(.headline)
                    Text("[\(context.tenantId)]")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(4)
                }
                
                if let summary = hubSummary {
                    Text("총 \(summary.totalPlugins)개 어댑터 중 \(summary.healthyCount)개 정상 가동")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Button {
                refreshSummary()
            } label: {
                Label("새로고침", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Plugin List
    private func pluginList(summary: PluginFleetHub.TenantHubSummary) -> some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(summary.cards) { card in
                    pluginCard(card: card)
                }
            }
            .padding()
        }
    }
    
    private func pluginCard(card: PluginFleetHub.PluginStatusCard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(card.isHealthy ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                
                Text(card.name)
                    .font(.headline)
                
                Text("v\(card.version)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(card.pluginId)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            // 명령 목록 (actions)
            if !card.actions.isEmpty {
                HStack(alignment: .top, spacing: 4) {
                    Text("명령:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    FlowLayout(spacing: 4) {
                        ForEach(card.actions, id: \.self) { act in
                            Button {
                                onExecuteAction?(card.pluginId, act, [])
                            } label: {
                                Text(act)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.1))
                                    .foregroundColor(.accentColor)
                                    .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            
            // Fast State (StateMirror 실시간 상태)
            if !card.fastState.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("StateMirror:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ForEach(Array(card.fastState.keys.sorted()), id: \.self) { k in
                        HStack {
                            Text(k)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.primary)
                            Spacer()
                            Text(card.fastState[k] ?? "")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(8)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(6)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
    
    // MARK: - Log Console
    private var logConsole: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("실행 콘솔")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Button("지우기") {
                    executionLogs.removeAll()
                }
                .buttonStyle(.borderless)
                .controlSize(.mini)
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(executionLogs, id: \.self) { log in
                        Text(log)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 80)
        }
        .padding()
        .background(Color.black.opacity(0.05))
    }
    
    private func refreshSummary() {
        isLoading = true
        let summary = PluginFleetHub().collectSummary(for: context, registry: registry)
        self.hubSummary = summary
        self.isLoading = false
    }
}

// 래핑 플로우 레이아웃
fileprivate struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var height: CGFloat = 0
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0
        
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                height += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        height += rowHeight
        return CGSize(width: width, height: height)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
