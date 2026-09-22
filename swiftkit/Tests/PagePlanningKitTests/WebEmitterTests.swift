import Testing
import Foundation
@testable import PagePlanningKit

@Suite("WebEmitter Tests")
struct WebEmitterTests {
    private let emitter = WebEmitter()

    private func makeTestSpec() -> PageSpec {
        PageSpec(
            uuid: "11111111-2222-3333-4444-555555555555",
            tenantUuid: "ca8e5a33-a3d3-4ad6-939a-bb898397e37c",
            shellUuid: "ba61f589-20c8-47a3-9135-77ed58266625",
            slugAlias: "A01",
            title: "Gujo Apps 카탈로그 탐색",
            targetEnvironment: "PC-Desktop-1440",
            purpose: "앱 탐색 및 세부 정보 확인",
            archetype: "catalog",
            blocks: [
                BlockSpec(id: "heroCluster", primitive: "HeroBlock", title: "메인 헤더", description: "카탈로그 헤더"),
                BlockSpec(id: "appCatalogGrid", primitive: "FeatureCluster", title: "그리드", description: "앱 목록 그리드")
            ],
            states: [
                "ready": StateSpec(notice: "OK", actions: ["view": "ENABLED"], recovery: nil),
                "error": StateSpec(notice: "FAIL", actions: ["retry": "ENABLED"], recovery: RecoverySpec(label: "재시도", target: "ready", action: "retry"))
            ]
        )
    }

    @Test("TSX generation contains valid React component structure and tokens")
    func testTSXGeneration() {
        let spec = makeTestSpec()
        let tsx = emitter.emitTSX(spec: spec)

        #expect(tsx.contains("export const A01PageView: React.FC<A01PageViewProps>"))
        #expect(tsx.contains("className=\"gujo-canvas\""))
        #expect(tsx.contains("data-target=\"PC-Desktop-1440\""))
        #expect(tsx.contains("Gujo Apps 카탈로그 탐색"))
        #expect(tsx.contains("heroCluster"))
        #expect(tsx.contains("currentState !== 'ready'"))
        #expect(!tsx.contains("style="))
    }

    @Test("HTML generation is semantic, contains no inline style")
    func testHTMLGeneration() {
        let spec = makeTestSpec()
        let html = emitter.emitHTML(spec: spec)

        #expect(html.contains("<!DOCTYPE html>"))
        #expect(html.contains("<title>Gujo Apps 카탈로그 탐색 - Gujo Planning</title>"))
        #expect(html.contains("class=\"gujo-canvas\""))
        #expect(!html.contains("style="))
    }
}
