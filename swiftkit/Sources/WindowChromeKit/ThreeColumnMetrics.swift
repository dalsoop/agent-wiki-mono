import CoreGraphics

/// 카탈로그 창 세 칸의 최소·이상 폭. 뷰와 테스트가 같은 숫자를 쓴다.
public struct ThreeColumnMetrics: Sendable, Equatable {
    public var sidebarMin: CGFloat
    public var sidebarIdeal: CGFloat
    public var sidebarMax: CGFloat
    public var contentMin: CGFloat
    public var inspectorMin: CGFloat
    public var inspectorIdeal: CGFloat
    public var inspectorMax: CGFloat

    public init(
        sidebarMin: CGFloat = 220,
        sidebarIdeal: CGFloat = 250,
        sidebarMax: CGFloat = 360,
        contentMin: CGFloat = 360,
        inspectorMin: CGFloat = 280,
        inspectorIdeal: CGFloat = 340,
        inspectorMax: CGFloat = 520
    ) {
        self.sidebarMin = sidebarMin
        self.sidebarIdeal = sidebarIdeal
        self.sidebarMax = sidebarMax
        self.contentMin = contentMin
        self.inspectorMin = inspectorMin
        self.inspectorIdeal = inspectorIdeal
        self.inspectorMax = inspectorMax
    }

    /// 함대 카탈로그 앱(목록 + 검사)의 기본값.
    public static let catalog = ThreeColumnMetrics()
}
