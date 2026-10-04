import KnowledgeBaseWikiCore
import SwiftUI

// 시트·스트립 — 근거 붙이기 / 워크벤치 / 이력 (LedgerView 에서 분리)

/// 근거 붙이기 — 근거 검색 → 관계 선택 → 인용 발행.
struct AttachCitationSheet: View {
    @Bindable var model: LedgerModel
    let document: LedgerDocument
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var rel = "references"

    private var candidates: [LedgerDocument] {
        let already = Set(document.head.cites.map(\.id))
        let all = model.evidenceDocuments.map(\.document).filter { !already.contains($0.head.id) }
        let needle = query.lowercased()
        return needle.isEmpty ? all : all.filter {
            $0.title.lowercased().contains(needle) || $0.head.body.lowercased().contains(needle)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("근거 붙이기").font(.headline)
            TextField("근거 검색", text: $query).textFieldStyle(.roundedBorder)
            Picker("관계", selection: $rel) {
                Text("참고함").tag("references")
                Text("요약함").tag("summarizes")
                Text("반박함").tag("contradicts")
            }
            .pickerStyle(.segmented)
            List(candidates.prefix(20)) { candidate in
                Button {
                    model.attachCitation(to: document, evidenceID: candidate.head.id, rel: rel)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(candidate.title.replacingOccurrences(of: "근거: ", with: ""))
                            .fontWeight(.medium)
                        Text(candidate.snippet).font(.caption).foregroundStyle(.secondary).lineLimit(1).frame(minWidth: 0)
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(width: 420, height: 240)
            HStack {
                Text("붙이면 기록의 새 판이 발행되며 인용이 계보에 남습니다.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("닫기") { dismiss() }
            }
        }
        .padding(20)
    }
}

/// 워크벤치 스트립 — 건강 핍 + 지표 + "다음 할 일" 바로가기 (SwarmVault 워크벤치 이식).
func engineDisplayName(_ engine: String) -> String {
    switch engine {
    case "claude": return "Claude Code"
    case "codex": return "Codex"
    case "grok": return "Grok"
    case "opencode": return "OpenCode"
    default: return engine
    }
}

func engineColor(_ engine: String) -> Color {
    switch engine {
    case "codex": return .teal
    case "grok": return .purple
    case "opencode": return .orange
    default: return .indigo
    }
}

struct WorkbenchStrip: View {
    @Bindable var model: LedgerModel

    var body: some View {
        HStack(spacing: 14) {
            // 항해 — 뒤로/앞으로 + 현재 위치 (점프해도 길을 잃지 않게)
            HStack(spacing: 4) {
                Button {
                    model.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!model.canGoBack)
                .keyboardShortcut("[", modifiers: .command)
                .help("뒤로 (⌘[)")
                Button {
                    model.goForward()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!model.canGoForward)
                .keyboardShortcut("]", modifiers: .command)
                .help("앞으로 (⌘])")
                Text(model.breadcrumb)
                    .font(.caption.weight(.medium))
                    .lineLimit(1).frame(minWidth: 0)
                    .frame(maxWidth: 320, alignment: .leading)
            }
            Divider().frame(height: 14)
            if let item = model.currentWorldPickerItem {
                Label(item.layer.badge, systemImage: item.layer.systemImage)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(item.layer == .remoteShared ? Color.purple.opacity(0.14) : Color.teal.opacity(0.14),
                                in: Capsule())
                    .help(item.subtitle)
            }
            Divider().frame(height: 14)
            HStack(spacing: 5) {
                Circle()
                    .fill(model.integrityProblemCount > 0 ? Color.red : Color.green)
                    .frame(width: 8, height: 8)
                Text(model.integrityProblemCount > 0
                     ? "무결성 문제 \(model.integrityProblemCount)" : "무결성 OK")
                    .font(.caption)
            }
            Divider().frame(height: 14)
            // 주의 지표 — 대기 중인 일만. 없으면 조용히 "대기 없음".
            if model.attentionItems.isEmpty {
                if model.runnerStatus == nil {
                    Text("대기 중인 일 없음").font(.caption).foregroundStyle(.tertiary)
                }
                // 러너가 돌고 있으면 우측 실행 배너가 상태를 말한다 — 모순 문구 숨김
            } else {
                ForEach(model.attentionItems) { item in
                    Button {
                        model.recordNavigation()
                        model.area = item.area
                    } label: {
                        HStack(spacing: 4) {
                            Text(item.label).font(.caption)
                            Text("\(item.count)").font(.caption.weight(.bold))
                        }
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(.orange.opacity(0.14), in: Capsule())
                        .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                    .help("클릭해 해당 영역으로 이동")
                }
            }
            Spacer()
            if let status = model.runnerStatus {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(status.label).font(.caption.weight(.medium))
                        Text(status.detail).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }
            if let progress = model.classificationProgress {
                HStack(spacing: 6) {
                    ProgressView(value: Double(progress.done), total: Double(progress.total))
                        .frame(width: 90)
                    Text("분류 \(progress.done)/\(progress.total)")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            // 다음 할 일 — 있을 때만 나타나는 액션 버튼
            if !model.triageQueue.isEmpty {
                Button {
                    model.area = .triage
                } label: {
                    Label("선별 대기 \(model.triageQueue.count)", systemImage: "tray.full")
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
            }
            if model.reviewNeededCount > 0 {
                Button {
                    model.area = .evidence
                    model.evidenceReviewOnly = true
                } label: {
                    Label("확인 필요 \(model.reviewNeededCount)", systemImage: "clock.badge.exclamationmark")
                }
                .buttonStyle(.borderedProminent).tint(.orange).controlSize(.small)
            }
            if model.contradictedCount > 0 {
                Button {
                    model.area = .evidence
                    model.sortByStrength = true
                } label: {
                    Label("반박 있음 \(model.contradictedCount)", systemImage: "bolt")
                }
                .buttonStyle(.bordered).tint(.red).controlSize(.small)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(.bar)
    }

}

/// 기록(버전) 패널 — 노션 페이지 히스토리 감각: 시점 고르고, 미리보고, 복원.
struct HistorySheet: View {
    @Bindable var model: LedgerModel
    let document: LedgerDocument
    @Environment(\.dismiss) private var dismiss
    @State private var selectedVersionID: String?

    private var selectedVersion: LedgerObject? {
        document.versions.first { $0.id == selectedVersionID } ?? document.versions.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("기록 — \(document.title)").font(.headline)
                Spacer()
                Button("닫기") { dismiss() }
            }
            HSplitView {
                List(document.versions, selection: $selectedVersionID) { version in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(version.published, format: .dateTime.month(.twoDigits).day(.twoDigits).hour().minute())
                            .font(.callout.monospacedDigit())
                        Text(version.id == document.head.id ? "현재" : byWho(version))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(version.id)
                }
                .frame(minWidth: 160, maxWidth: 210)
                VStack(alignment: .leading, spacing: 8) {
                    if let version = selectedVersion {
                        ScrollView {
                            Text(version.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        if version.id != document.head.id, !model.isReadOnlyWorld {
                            Button("이 시점으로 복원") {
                                model.restore(version: version, in: document)
                                dismiss()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .padding(.leading, 10)
                .frame(minWidth: 300)
            }
            // HSplitView 는 스스로 안 늘어난다
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16)
        .frame(minWidth: 620, minHeight: 400)
    }

    private func byWho(_ version: LedgerObject) -> String {
        version.author == "human" ? "내가 수정" : "\(version.author) 수정"
    }
}
