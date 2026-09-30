import Foundation
import KnowledgeBaseWikiCore
import SwiftUI

struct AdministrationOverviewView: View {
    @Bindable var model: LedgerModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("저장소 및 원장 관리").font(.title2.bold())
                Text("Fleet health, 검증, 백업과 CLI 상태를 한곳에서 확인합니다.")
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
                    adminCard("등록 world", "\(model.worldPickerItems.count)", "point.3.connected.trianglepath.dotted", .blue)
                    adminCard("확인 필요", "\(model.worldPickerItems.filter { $0.health != .healthy }.count)", "exclamationmark.triangle", .orange)
                    adminCard("무결성 문제", "\(model.repositorySummary?.integrity.issues.count ?? model.integrityProblemCount)", "checkmark.shield", .green)
                    adminCard("CLI", model.cliStaleVersion == nil ? "최신" : "갱신 필요", "terminal", model.cliStaleVersion == nil ? .green : .orange)
                }
                GroupBox("등록된 world") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.worldPickerItems) { item in
                            HStack {
                                Image(systemName: item.health.systemImage)
                                    .foregroundStyle(healthColor(item.health))
                                Text(item.title).fontWeight(.medium)
                                Text(item.world.name).font(.caption.monospaced())
                                Text(item.group.title).font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Text(item.health.label).font(.caption)
                            }
                        }
                    }.padding(.top, 5)
                }
                HStack {
                    Button("설정 열기") { openSettings() }.buttonStyle(.borderedProminent)
                    Text(LedgerModel.cliPathGuidance).font(.caption).foregroundStyle(.secondary)
                    Button("다시 검증") { model.refreshProtectionStatus(); model.refresh() }
                }
            }
            .padding(24).frame(maxWidth: 900, alignment: .leading)
        }
        .accessibilityIdentifier("repository-administration")
    }

    private func adminCard(_ title: String, _ value: String, _ icon: String, _ color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title2).foregroundStyle(color)
            VStack(alignment: .leading) {
                Text(value).font(.title3.bold())
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }.padding(14).background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
    }

    private func healthColor(_ health: WorldHealth) -> Color {
        switch health { case .healthy: .green; case .attention: .orange; case .unavailable: .red }
    }
}
