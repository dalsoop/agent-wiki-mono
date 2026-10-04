import AppKit
import KnowledgeBaseWikiCore
import SwiftUI

/// 에이전트 정의 패널 — 파일 경로·본문·인앱 수정. 저장은 파일 갱신 + 원장
/// `역할정의:` 개정판 발행(supersedes 사슬)이라 버전관리가 원장 방식으로 남는다.
private func revisionReason(_ object: LedgerObject) -> String {
    let first = object.body.split(separator: "\n").first.map(String.init) ?? ""
    return first.hasPrefix("개정 사유:") ? String(first.dropFirst(6)).trimmingCharacters(in: .whitespaces) : "초판"
}

struct AgentDefinitionView: View {
    @Bindable var model: LedgerModel
    let name: String
    @State private var isEditing = false
    @State private var draft = ""
    @State private var reason = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let path = model.roleDefinitionPath(name) {
                pathHeader(path)
                definitionBody
            } else {
                ContentUnavailableView(L(.AgentDefinitionViewEmptyTitle), systemImage: "exclamationmark.triangle",
                    description: Text(L(.AgentDefinitionViewEmptyDescription, name)))
                    .frame(maxHeight: 160)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private func pathHeader(_ path: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
            Text(path).font(.caption.monospaced()).foregroundStyle(.secondary)
                .lineLimit(1).frame(minWidth: 0).truncationMode(.head)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            } label: {
                Image(systemName: "arrow.up.forward.square")
            }
            .buttonStyle(.plain).help("Finder 에서 보기")
            Spacer()
            let history = model.roleDefinitionHistory(name)
            if !history.isEmpty {
                Text("원장 판 \(history.count)개").font(.caption2).foregroundStyle(.tertiary)
            }
            if !model.isReadOnlyWorld {  // 보관된 원장(전신)은 역할 정의를 고치지 않는다
                Button(isEditing ? "취소" : "정의 수정") { toggleEditing() }
                .controlSize(.small)
            }
        }
    }

    private func toggleEditing() {
        guard isEditing else {
            draft = model.roleDefinitionText(name) ?? ""
            reason = ""
            isEditing = true
            return
        }
        isEditing = false
    }

    @ViewBuilder
    private var definitionBody: some View {
        if isEditing, !model.isReadOnlyWorld {
            TextEditor(text: $draft)
                .font(.system(.callout, design: .monospaced))
                .frame(minHeight: 220)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            HStack {
                TextField("개정 사유 (필수 — 원장에 남습니다)", text: $reason)
                    .textFieldStyle(.roundedBorder)
                Button("저장 — 개정판 발행") {
                    model.saveRoleDefinition(name, text: draft, reason: reason)
                    isEditing = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(reason.trimmingCharacters(in: .whitespaces).isEmpty
                          || draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } else if let text = model.roleDefinitionText(name) {
            ScrollView {
                MarkdownBody(text: text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 240)
            .padding(8)
            .background(.quaternary.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            revisionHistory
        }
    }

    @ViewBuilder
    private var revisionHistory: some View {
        let history = model.roleDefinitionHistory(name)
        if history.count > 1 {
            Text("변경 이력 \(history.count)판").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(history) { revision in
                Button { model.jump(toObject: revision.id) } label: {
                    HStack(spacing: 6) {
                        Text(revision.published, format: .dateTime.month(.twoDigits).day(.twoDigits).hour().minute())
                            .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                        Text(revisionReason(revision)).font(.caption).lineLimit(1).frame(minWidth: 0)
                        Spacer()
                        Text(revision.author).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
