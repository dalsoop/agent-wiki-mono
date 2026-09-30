import Foundation
import KnowledgeBaseWikiCore
import SwiftUI

struct DestinationSubnavigationBar: View {
    @Bindable var model: LedgerModel

    var body: some View {
        if model.destination == .knowledge {
            HStack(spacing: 5) {
                navButton("페이지", "books.vertical", .wiki)
                navButton("근거·결정", "doc.text.magnifyingglass", .evidence)
                navButton("내 기록", "square.and.pencil", .myNotes)
                navButton("토론", "bubble.left.and.bubble.right", .discuss)
                let allowed = LedgerAreaOwnership.allowedAreas()
                if allowed.contains(.graph) || allowed.contains(.changes) {
                    Menu("그래프·변경") {
                        if allowed.contains(.graph) { Button("관계도") { model.area = .graph } }
                        if allowed.contains(.changes) { Button("최근 변경") { model.area = .changes } }
                    }.menuStyle(.borderlessButton).fixedSize()
                }
                if allowed.contains(.learning) || allowed.contains(.triage)
                    || allowed.contains(.review) || allowed.contains(.trash) {
                    Menu("정제") {
                        if allowed.contains(.learning) { Button("학습") { model.area = .learning } }
                        if allowed.contains(.triage) { Button("수집함") { model.area = .triage } }
                        if allowed.contains(.review) { Button("심사대") { model.area = .review } }
                        if allowed.contains(.trash) { Button("휴지통") { model.area = .trash } }
                    }.menuStyle(.borderlessButton).fixedSize()
                }
                Spacer()
            }.padding(.horizontal, 12).padding(.vertical, 5).background(.bar)
        } else if model.destination == .administration {
            HStack(spacing: 5) {
                // 짝 버튼이 없으면 구조로 들어간 뒤 개요로 돌아올 길이 없다.
                // 관리는 area 를 .structure 일 때만 보므로, 그 밖의 값이면 개요가 뜬다.
                navButton("개요", "square.grid.2x2", .settings)
                navButton("구조", "square.stack.3d.down.right", .structure)
                Spacer()
                Text(model.area == .structure
                    ? "저장 3층과 층 사이 배선 완성도 — 수치는 실측입니다."
                    : "Fleet health · 검증 · 백업 · CLI 상태")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 12).padding(.vertical, 5).background(.bar)
        } else if model.destination == .contributors {
            HStack(spacing: 5) {
                navButton("담당 역할", "person.2.badge.gearshape", .agents)
                navButton("기여 활동", "square.stack.3d.up", .activity)
                navButton("사건", "clock.arrow.circlepath", .events)
                Spacer()
                Text("사람과 에이전트는 attribution 축이며 저장소를 소유하지 않습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 12).padding(.vertical, 5).background(.bar)
        }
    }

    @ViewBuilder
    private func navButton(_ title: String, _ icon: String, _ area: LedgerArea) -> some View {
        // Reader/Studio 표면 분리: AGENT_WIKI_SURFACE=reader|studio|all
        if LedgerAreaOwnership.allowedAreas().contains(area) {
            Button {
                model.area = area
            } label: {
                Label(title, systemImage: icon).font(.caption.weight(model.area == area ? .semibold : .regular))
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(model.area == area ? Color.accentColor.opacity(0.14) : .clear, in: Capsule())
            }.buttonStyle(.plain)
        }
    }
}
