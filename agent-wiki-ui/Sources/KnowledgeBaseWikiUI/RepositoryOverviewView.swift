import Foundation
import KnowledgeBaseWikiCore
import SwiftUI

struct RepositoryOverviewView: View {
    @Bindable var model: LedgerModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if let summary = model.repositorySummary {
                    repositoryHeader(summary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                        SummaryCard(title: "지식", value: summary.knowledge.total,
                                    detail: "최근 결정 \(summary.knowledge.recentDecisions.count)", icon: "books.vertical", tint: .blue)
                        SummaryCard(title: "작업", value: summary.tasks.open + summary.tasks.delegated,
                                    detail: "완료 \(summary.tasks.completed)", icon: "checklist", tint: .orange)
                        SummaryCard(title: "승격", value: summary.promotion.candidates,
                                    detail: "gujo 게시 \(summary.promotion.promoted)", icon: "arrow.up.forward.square", tint: .purple)
                        SummaryCard(title: "무결성", value: summary.integrity.issues.count,
                                    detail: summary.integrity.status == .healthy ? "정상" : "확인 필요",
                                    icon: "checkmark.shield", tint: summary.integrity.status == .healthy ? .green : .red)
                    }
                    repositoryContext(summary)
                    recentDecisions(summary)
                } else {
                    sharedWorldOverview
                }
            }
            .padding(24)
            .frame(maxWidth: 1100, alignment: .leading)
        }
        .accessibilityIdentifier("repository-overview")
    }

    private func repositoryHeader(_ summary: RepositorySummaryContract) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label("저장소 정본", systemImage: "shippingbox.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(.blue)
                Spacer()
                Label(summary.integrity.status == .healthy ? "검증됨" : "확인 필요",
                      systemImage: summary.integrity.status == .healthy ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(summary.integrity.status == .healthy ? .green : .orange)
            }
            Text(summary.repository.displayName).font(.largeTitle.weight(.bold))
            Text(summary.repository.remote).font(.callout.monospaced()).foregroundStyle(.secondary)
            Text("에이전트와 사람은 이 저장소 지식의 기여자입니다. 소유자는 저장소입니다.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func repositoryContext(_ summary: RepositorySummaryContract) -> some View {
        GroupBox("저장소 identity · 현재 worktree") {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                identityRow("Canonical repoId", summary.repository.id)
                identityRow("Worktree", summary.repository.worktreePath)
                identityRow("Branch", summary.repository.branch.isEmpty ? "detached" : summary.repository.branch)
                identityRow("Commit", String(summary.repository.sourceCommit.prefix(12)))
                identityRow("Default branch", summary.repository.defaultBranch.isEmpty ? "확인 안 됨" : summary.repository.defaultBranch)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
        }
    }

    private func identityRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(value).font(.callout.monospaced()).textSelection(.enabled).lineLimit(2).frame(minWidth: 0)
        }
    }

    private func recentDecisions(_ summary: RepositorySummaryContract) -> some View {
        GroupBox("최근 결정") {
            VStack(alignment: .leading, spacing: 8) {
                if summary.knowledge.recentDecisions.isEmpty {
                    Text("아직 decision 객체가 없습니다.").foregroundStyle(.secondary)
                } else {
                    ForEach(summary.knowledge.recentDecisions) { item in
                        Button {
                            model.jump(toObject: item.objectId)
                        } label: {
                            HStack {
                                Image(systemName: "checkmark.diamond")
                                Text(item.title).lineLimit(1).frame(minWidth: 0)
                                Spacer()
                                Text(item.updatedAt, format: .dateTime.month().day())
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
        }
    }

    /// repo 가 아닌 world(1인칭·원격 공유·주제)의 개요.
    private var recentPublishedBox: some View {
            GroupBox("최근 발행") {
                VStack(alignment: .leading, spacing: 8) {
                    if worldRecentObjects.isEmpty {
                        Text("아직 발행한 객체가 없습니다.").foregroundStyle(.secondary)
                    } else {
                        ForEach(worldRecentObjects, id: \.id) { object in
                            Button {
                                model.jump(toObject: object.id)
                            } label: {
                                HStack {
                                    Image(systemName: "doc.text")
                                    Text(object.title ?? object.id.prefix(8).description).lineLimit(1).frame(minWidth: 0)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
            }
    }

    private var sharedWorldOverview: some View {
        let layer = WikiWorldPresentation.classify(
            name: model.currentWorldName ?? "",
            rootPath: model.rootURL?.path ?? ""
        )
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: layer.systemImage).foregroundStyle(layer == .remoteShared ? .purple : .teal)
                VStack(alignment: .leading, spacing: 2) {
                    Text(WikiWorldPresentation.title(
                        name: model.currentWorldName ?? "",
                        rootPath: model.rootURL?.path ?? ""
                    )).font(.title3.weight(.semibold))
                    Text(layer.groupTitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(overviewCopy(for: layer))
                .font(.callout).foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                SummaryCard(title: "객체", value: model.objects.count,
                            detail: "이 world 전체", icon: "books.vertical", tint: .blue)
                SummaryCard(title: "본문·기록", value: worldSubstantiveCount,
                            detail: "선별·영수증 제외", icon: "doc.text", tint: .teal)
                SummaryCard(title: "승격됨", value: worldPromotedCount,
                            detail: "원격 공유로 올라간 건", icon: "arrow.up.forward.square", tint: .purple)
            }

            recentPublishedBox

            if layer == .localPerson || layer == .tenant, model.gujoWorld != nil {
                Text("확인이 끝난 글만 승격으로 원격 공유 위키에 올립니다. 이 원장 자체는 GitLab에 올라가지 않습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let repository = model.pickerRepositories.first {
                Button("저장소 개요 열기") { model.switchWorld(repository.world) }
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func overviewCopy(for layer: WikiWorldLayer) -> String {
        switch layer {
        case .localPerson:
            return "테넌트 1인칭 원장입니다. 주관·규약은 여기 쌓고, 여러 사람이 볼 사실만 원격 공유 위키로 승격합니다."
        case .tenant:
            return "테넌트 world 입니다. 방에서 쌓인 습관과 테넌트 지식이 여기 모이고, 여러 테넌트가 볼 사실만 공유 위키로 승격합니다."
        case .remoteShared:
            return "공유 위키입니다. 이 Mac의 ~/gujo-wiki 에 있고 피어 Mac 과 pull 로 맞춥니다. 원격 git 저장소(옛 내부 GitLab)는 2026-09-24 퇴역해 지금은 없습니다."
        case .repository:
            return "이 저장소의 .wiki 원장입니다."
        case .other:
            return "주제 원장입니다. 테넌트 1인칭도 원격 공유도 아닙니다."
        }
    }

    /// 선별(screening)·영수증 같은 부속 객체를 뺀 "사람이 쓴 것" 수.
    /// 개인 world 는 본문 하나에 선별이 하나씩 붙어 총계가 실제 글 수의 두 배로 보인다
    /// (실측: 33개 중 21개가 선별).
    private var worldSubstantiveCount: Int {
        model.objects.count { object in
            let type = object.effectiveType ?? ""
            return type != "screening" && type != "promotion-receipt"
        }
    }

    private var worldPromotedCount: Int {
        model.objects.count { ($0.effectiveType ?? "") == "promotion-receipt" }
    }

    private var worldRecentObjects: [LedgerObject] {
        model.objects
            .filter { ($0.effectiveType ?? "") != "screening" }
            .sorted { $0.published > $1.published }
            .prefix(10)
            .map { $0 }
    }
}

private struct SummaryCard: View {
    let title: String
    let value: Int
    let detail: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon).foregroundStyle(tint)
                Text(title).font(.headline)
                Spacer()
            }
            Text(value, format: .number).font(.system(size: 30, weight: .bold, design: .rounded))
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
    }
}
