import Foundation
import Observation
import LocalizationKit
import AgentWikiIndexerCore

@MainActor
@Observable
final class AppModel {
    let loc = LocalizationManager(baseBundle: ResourceBundle.localization(preferredName: "GujoAgentWikiIndexer_AgentWikiIndexer"))
    // 자기 번역 묶음을 이름으로 고른다 — 패키지 이름(Gujo…)이 앱 이름과 달라 이름 순위가 화면 모듈 묶음을 먼저 집었다(2026-10-04 실측: 메뉴가 키 그대로).
    private let service = AgentWikiLocalService()

    var status: String = ""

    /// 타입세이프 지역화 헬퍼.
    func L(_ key: L10nKey) -> String { loc.string(key.rawValue) }

    func L(_ key: L10nKey, _ args: CVarArg...) -> String {
        String(format: loc.string(key.rawValue), locale: .current, arguments: args)
    }

    func refresh() async {
        do {
            try service.ensureDurableStore()
            status = try await service.status()
            StateMirrorAdoption.publish(status: status.isEmpty ? "ok" : status)
        } catch {
            status = String(describing: error)
            StateMirrorAdoption.publish(status: "error")
        }
    }
}
