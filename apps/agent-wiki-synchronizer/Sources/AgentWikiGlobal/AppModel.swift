import Foundation
import Observation
import LocalizationKit
import AgentWikiGlobalCore

@MainActor
@Observable
final class AppModel {
    let loc = LocalizationManager(baseBundle: ResourceBundle.localization())
    private let service = AgentWikiGlobalService()

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
