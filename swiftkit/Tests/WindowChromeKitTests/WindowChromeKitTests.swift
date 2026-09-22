import XCTest
#if canImport(SwiftUI)
import SwiftUI
#endif
import LocalizationKit
@testable import WindowChromeKit

final class WindowChromeKitTests: XCTestCase {
    func testCatalogMetricsKeepSidebarReadable() {
        let m = ThreeColumnMetrics.catalog
        XCTAssertGreaterThanOrEqual(m.sidebarMin, 220)
        XCTAssertGreaterThanOrEqual(m.contentMin, 360)
        XCTAssertGreaterThanOrEqual(m.inspectorMin, 280)
        XCTAssertLessThan(m.sidebarMin, m.sidebarIdeal)
        XCTAssertLessThan(m.inspectorMin, m.inspectorIdeal)
    }

    func testSurfaceRoundTripAndUniqueIds() throws {
        let surfaces = ThreeColumnSurfaces(
            sidebar: ScreenSurface(
                id: "demo.sidebar", title: "folders",
                source: "Demo/MainView.swift:sidebar",
                readCommand: "demo list --json"
            ),
            content: ScreenSurface(
                id: "demo.content", title: "list",
                source: "Demo/MainView.swift:list",
                readCommand: "demo list --json"
            ),
            inspector: ScreenSurface(
                id: "demo.inspector", title: "detail",
                source: "Demo/MainView.swift:inspector",
                readCommand: "demo show --json"
            )
        )
        XCTAssertEqual(Set(surfaces.all.map(\.id)).count, 3)
        let data = try JSONEncoder().encode(surfaces.all)
        let decoded = try JSONDecoder().decode([ScreenSurface].self, from: data)
        XCTAssertEqual(decoded, surfaces.all)
    }

    func testAppFactoryStampsThreeUniqueIds() {
        let surfaces = ThreeColumnSurfaces(
            app: "demo",
            readCommand: "demo list --json",
            sidebarSource: "Demo/Sidebar.swift",
            contentSource: "Demo/List.swift",
            inspectorSource: "Demo/Inspector.swift"
        )
        XCTAssertEqual(surfaces.sidebar.id, "demo.sidebar")
        XCTAssertEqual(surfaces.content.id, "demo.content")
        XCTAssertEqual(surfaces.inspector.id, "demo.inspector")
        XCTAssertEqual(Set(surfaces.all.map(\.id)).count, 3)
        XCTAssertGreaterThanOrEqual(ThreeColumnMetrics.catalog.contentMin, 360)
    }

    func testPaneTitlesFollowAppLanguage() {
        XCTAssertEqual(WindowChromeStrings.title(.sidebar, language: .korean), "사이드바")
        XCTAssertEqual(WindowChromeStrings.title(.content, language: .korean), "목록")
        XCTAssertEqual(WindowChromeStrings.title(.inspector, language: .korean), "검사")
        XCTAssertEqual(WindowChromeStrings.title(.detail, language: .korean), "상세")
        XCTAssertEqual(WindowChromeStrings.title(.sidebar, language: .english), "Sidebar")
        XCTAssertEqual(WindowChromeStrings.title(.content, language: .english), "List")
        XCTAssertEqual(WindowChromeStrings.title(.inspector, language: .english), "Inspector")
        XCTAssertEqual(WindowChromeStrings.title(.detail, language: .english), "Detail")
    }

    func testSystemLanguageUsesPreferredLanguages() {
        XCTAssertEqual(
            WindowChromeStrings.title(.sidebar, language: .system, preferredLanguages: ["ko-KR"]),
            "사이드바"
        )
        XCTAssertEqual(
            WindowChromeStrings.title(.sidebar, language: .system, preferredLanguages: ["en-US"]),
            "Sidebar"
        )
    }

    func testResolvedLanguageReadsAppLanguageDefaults() throws {
        let suite = "window-chrome-strings-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(AppLanguage.korean.rawValue, forKey: WindowChromeStrings.languageDefaultsKey)
        XCTAssertEqual(WindowChromeStrings.resolvedLanguage(defaults: defaults), .korean)
        defaults.set(AppLanguage.english.rawValue, forKey: WindowChromeStrings.languageDefaultsKey)
        XCTAssertEqual(WindowChromeStrings.resolvedLanguage(defaults: defaults), .english)
    }

    /// 칸 id 는 `agent-surface-reach` 가 읽는 기계 신원이다. `#fileID` 파생이 바뀌면
    /// 함대 행렬에서 앱이 통째로 사라진다.
    func testSurfaceIDsAreDerivedFromTheModuleNameInFileID() {
        let surfaces = ThreeColumnSurfaces.derived(file: "MyApp/CatalogView.swift")

        XCTAssertEqual(surfaces.sidebar.id, "MyApp.sidebar")
        XCTAssertEqual(surfaces.content.id, "MyApp.content")
        XCTAssertEqual(surfaces.inspector.id, "MyApp.inspector")
        XCTAssertEqual(surfaces.all.map(\.source), Array(repeating: "MyApp/CatalogView.swift", count: 3))
        XCTAssertEqual(Set(surfaces.all.map(\.id)).count, 3, "칸 id 가 겹치면 접근성 식별자가 서로를 가린다")
    }

    func testSurfaceDerivationFallsBackWhenFileIDHasNoModule() {
        XCTAssertEqual(ThreeColumnSurfaces.derived(file: "CatalogView.swift").sidebar.id, "CatalogView.swift.sidebar")
        XCTAssertEqual(ThreeColumnSurfaces.derived(file: "").sidebar.id, "app.sidebar", "빈 파생이 \".sidebar\" 로 새면 안 된다")
        XCTAssertEqual(ThreeColumnSurfaces.derived(file: "/Leading.swift").sidebar.id, "Leading.swift.sidebar")
    }

    #if canImport(SwiftUI)
    @MainActor
    func testTwoColumnCatalogStampsItsOwnModuleSurfaces() {
        let view = TwoColumnCatalog(file: "SampleApp/Screen.swift") { Text("s") } detail: { Text("d") }

        XCTAssertEqual(view.surfaces, ThreeColumnSurfaces.derived(file: "SampleApp/Screen.swift"))
        XCTAssertEqual(view.surfaces.content.id, "SampleApp.content", "2칸 셸의 상세는 content 칸이다")
    }

    @MainActor
    func testInspectorInitProducesTheCollapsibleInspectorChrome() {
        let view = ThreeColumnCatalog(file: "SampleApp/Screen.swift") {
            Text("s")
        } content: {
            Text("c")
        } inspector: {
            Text("i")
        }

        XCTAssertEqual(view.chrome, .inspector, "inspector: 라벨이 cascade 로 가면 검사 칸이 사라진다")
        XCTAssertEqual(view.surfaces, ThreeColumnSurfaces.derived(file: "SampleApp/Screen.swift"))
    }

    @MainActor
    func testDetailInitProducesTheCascadeChrome() {
        let view = ThreeColumnCatalog(file: "SampleApp/Screen.swift") {
            Text("s")
        } content: {
            Text("c")
        } detail: {
            Text("d")
        }

        XCTAssertEqual(view.chrome, .cascade, "detail: 라벨이 inspector 로 가면 3열이 2열로 접힌다")
        XCTAssertEqual(view.surfaces.inspector.id, "SampleApp.inspector")
    }
    #endif
}
