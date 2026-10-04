import Foundation
import Observation
import LocalizationKit
import AgentWikiGrapherCore

@MainActor
@Observable
final class AppModel {
    let loc = LocalizationManager(baseBundle: ResourceBundle.localization(preferredName: "GujoAgentWikiGrapher_AgentWikiGrapher"))
    // 자기 번역 묶음을 이름으로 고른다 — 패키지 이름(Gujo…)이 앱 이름과 달라 이름 순위가 화면 모듈 묶음을 먼저 집었다(2026-10-04 실측: 메뉴가 키 그대로).
    private let service = AgentWikiGraphService()

    var status: String = ""
    var summary: AgentWikiGraphService.StatusSummary?

    init() {
        // 창 앱은 뷰 .task 만으로는 실행 확인 게이트에서 미러가 안 나온다 —
        // 앱 시작 시 1회 로드·게시(2026-08-05 실측 교훈).
        Task { await self.refresh() }
    }

    /// 타입세이프 지역화 헬퍼.
    func L(_ key: L10nKey) -> String { loc.string(key.rawValue) }

    func L(_ key: L10nKey, _ args: CVarArg...) -> String {
        String(format: loc.string(key.rawValue), locale: .current, arguments: args)
    }

    func refresh() async {
        let s = service.status()
        summary = s
        status = "nodes=\(s.nodeCount) edges=\(s.edgeCount) orphans=\(s.orphanCount)"
        // 함대 계약(앱 상태 미러): 모델이 바뀌는 지점마다 게시한다.
        StateMirrorAdoption.publish(summary: s)
    }
}
