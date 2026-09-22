#if canImport(SwiftUI)
import SwiftUI
import LocalizationKit

/// 사이드바 · 목록 · 세 번째 칸. `NavigationSplitView` 안에 `HSplitView` 를 넣지 않는다.
///
/// 겹치면 바깥 칸이 0폭으로 접힌다(실측: Agent Lint Catalog 사이드바 슬iver,
/// 검사 칸 소실).
///
/// 세 번째 칸 라벨이 의도다.
/// - `inspector:` 검사 칸(`.inspector` API, 접을 수 있음)
/// - `detail:` 목록이 이어지는 3열(`NavigationSplitView` sidebar/content/detail)
public struct ThreeColumnCatalog<Sidebar: View, Content: View, Trailing: View>: View {
    /// 세 번째 칸의 성격. `inspector:` 와 `detail:` 을 바꿔 쓰면 칸이 통째로 사라진다.
    enum Chrome: Equatable {
        case inspector
        case cascade
    }

    let chrome: Chrome
    private let metrics: ThreeColumnMetrics
    let surfaces: ThreeColumnSurfaces
    private let columnVisibility: Binding<NavigationSplitViewVisibility>?
    @Binding private var inspectorPresented: Bool
    @State private var defaultVisibility: NavigationSplitViewVisibility = .all
    @AppStorage(WindowChromeStrings.languageDefaultsKey) private var languageRaw = AppLanguage.system.rawValue
    private let sidebar: Sidebar
    private let content: Content
    private let trailing: Trailing

    private var chromeLanguage: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .system
    }

    public init(
        metrics: ThreeColumnMetrics = .catalog,
        surfaces: ThreeColumnSurfaces,
        inspectorPresented: Binding<Bool> = .constant(true),
        columnVisibility: Binding<NavigationSplitViewVisibility>? = nil,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder content: () -> Content,
        @ViewBuilder inspector: () -> Trailing
    ) {
        self.chrome = .inspector
        self.metrics = metrics
        self.surfaces = surfaces
        self.columnVisibility = columnVisibility
        self._inspectorPresented = inspectorPresented
        self.sidebar = sidebar()
        self.content = content()
        self.trailing = inspector()
    }

    /// 앱이 `surfaces` 를 직접 안 짜도 되게 `#fileID` 로 칸 id 를 찍는다.
    public init(
        metrics: ThreeColumnMetrics = .catalog,
        file: String = #fileID,
        inspectorPresented: Binding<Bool> = .constant(true),
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder content: () -> Content,
        @ViewBuilder inspector: () -> Trailing
    ) {
        self.init(
            metrics: metrics,
            surfaces: Self.surfaces(file: file),
            inspectorPresented: inspectorPresented,
            sidebar: sidebar,
            content: content,
            inspector: inspector
        )
    }

    public init(
        columnVisibility: Binding<NavigationSplitViewVisibility>,
        metrics: ThreeColumnMetrics = .catalog,
        file: String = #fileID,
        inspectorPresented: Binding<Bool> = .constant(true),
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder content: () -> Content,
        @ViewBuilder inspector: () -> Trailing
    ) {
        self.init(
            metrics: metrics,
            surfaces: Self.surfaces(file: file),
            inspectorPresented: inspectorPresented,
            columnVisibility: columnVisibility,
            sidebar: sidebar,
            content: content,
            inspector: inspector
        )
    }

    /// 메일·덱처럼 목록이 칸마다 이어지는 3열. 세 번째 클로저 라벨이 `detail:`.
    public init(
        metrics: ThreeColumnMetrics = .catalog,
        surfaces: ThreeColumnSurfaces,
        columnVisibility: Binding<NavigationSplitViewVisibility>? = nil,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder content: () -> Content,
        @ViewBuilder detail: () -> Trailing
    ) {
        self.chrome = .cascade
        self.metrics = metrics
        self.surfaces = surfaces
        self.columnVisibility = columnVisibility
        self._inspectorPresented = .constant(true)
        self.sidebar = sidebar()
        self.content = content()
        self.trailing = detail()
    }

    public init(
        metrics: ThreeColumnMetrics = .catalog,
        file: String = #fileID,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder content: () -> Content,
        @ViewBuilder detail: () -> Trailing
    ) {
        self.init(
            metrics: metrics,
            surfaces: Self.surfaces(file: file),
            sidebar: sidebar,
            content: content,
            detail: detail
        )
    }

    public init(
        columnVisibility: Binding<NavigationSplitViewVisibility>,
        metrics: ThreeColumnMetrics = .catalog,
        file: String = #fileID,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder content: () -> Content,
        @ViewBuilder detail: () -> Trailing
    ) {
        self.init(
            metrics: metrics,
            surfaces: Self.surfaces(file: file),
            columnVisibility: columnVisibility,
            sidebar: sidebar,
            content: content,
            detail: detail
        )
    }

    public var body: some View {
        let visibility = columnVisibility ?? $defaultVisibility
        switch chrome {
        case .inspector:
            NavigationSplitView(columnVisibility: visibility) {
                sidebarColumn
            } detail: {
                contentColumn
            }
            .navigationSplitViewStyle(.balanced)
            .inspector(isPresented: $inspectorPresented) {
                trailing
                    .accessibilityIdentifier(surfaces.inspector.id)
                    .accessibilityLabel(WindowChromeStrings.title(.inspector, language: chromeLanguage))
                    .inspectorColumnWidth(
                        min: metrics.inspectorMin,
                        ideal: metrics.inspectorIdeal,
                        max: metrics.inspectorMax
                    )
            }
        case .cascade:
            NavigationSplitView(columnVisibility: visibility) {
                sidebarColumn
            } content: {
                contentColumn
            } detail: {
                trailing
                    .accessibilityIdentifier(surfaces.inspector.id)
                    .accessibilityLabel(WindowChromeStrings.title(.detail, language: chromeLanguage))
                    .navigationSplitViewColumnWidth(
                        min: metrics.inspectorMin,
                        ideal: metrics.inspectorIdeal,
                        max: metrics.inspectorMax
                    )
            }
            .navigationSplitViewStyle(.balanced)
        }
    }

    private var sidebarColumn: some View {
        sidebar
            .accessibilityIdentifier(surfaces.sidebar.id)
            .accessibilityLabel(WindowChromeStrings.title(.sidebar, language: chromeLanguage))
            .navigationSplitViewColumnWidth(
                min: metrics.sidebarMin,
                ideal: metrics.sidebarIdeal,
                max: metrics.sidebarMax
            )
    }

    private var contentColumn: some View {
        content
            .accessibilityIdentifier(surfaces.content.id)
            .accessibilityLabel(WindowChromeStrings.title(.content, language: chromeLanguage))
            .navigationSplitViewColumnWidth(min: metrics.contentMin, ideal: max(metrics.contentMin, 480))
    }

    private static func surfaces(file: String) -> ThreeColumnSurfaces {
        ThreeColumnSurfaces.derived(file: file)
    }
}

/// 사이드바 + 상세. `NavigationSplitView` 를 앱이 직접 쓰지 않게 하는 2칸 셸.
/// 두 번째 클로저 라벨이 `detail:` 이라 기존 `NavigationSplitView { } detail: { }` 과 같다.
public struct TwoColumnCatalog<Sidebar: View, Detail: View>: View {
    private let metrics: ThreeColumnMetrics
    let surfaces: ThreeColumnSurfaces
    private let columnVisibility: Binding<NavigationSplitViewVisibility>?
    @State private var defaultVisibility: NavigationSplitViewVisibility = .all
    @AppStorage(WindowChromeStrings.languageDefaultsKey) private var languageRaw = AppLanguage.system.rawValue
    private let sidebar: Sidebar
    private let detail: Detail

    private var chromeLanguage: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .system
    }

    public init(
        metrics: ThreeColumnMetrics = .catalog,
        file: String = #fileID,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder detail: () -> Detail
    ) {
        self.metrics = metrics
        self.surfaces = ThreeColumnSurfaces.derived(file: file)
        self.columnVisibility = nil
        self.sidebar = sidebar()
        self.detail = detail()
    }

    public init(
        columnVisibility: Binding<NavigationSplitViewVisibility>,
        metrics: ThreeColumnMetrics = .catalog,
        file: String = #fileID,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder detail: () -> Detail
    ) {
        self.metrics = metrics
        self.surfaces = ThreeColumnSurfaces.derived(file: file)
        self.columnVisibility = columnVisibility
        self.sidebar = sidebar()
        self.detail = detail()
    }

    public var body: some View {
        let visibility = columnVisibility ?? $defaultVisibility
        NavigationSplitView(columnVisibility: visibility) {
            sidebar
                .accessibilityIdentifier(surfaces.sidebar.id)
                .accessibilityLabel(WindowChromeStrings.title(.sidebar, language: chromeLanguage))
                .navigationSplitViewColumnWidth(
                    min: metrics.sidebarMin,
                    ideal: metrics.sidebarIdeal,
                    max: metrics.sidebarMax
                )
        } detail: {
            detail
                .accessibilityIdentifier(surfaces.content.id)
                .accessibilityLabel(WindowChromeStrings.title(.detail, language: chromeLanguage))
                .navigationSplitViewColumnWidth(min: metrics.contentMin, ideal: max(metrics.contentMin, 480))
        }
        .navigationSplitViewStyle(.balanced)
    }
}
#endif
