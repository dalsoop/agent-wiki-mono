import Foundation

/// WebRenderUIKit 의 타이밍 값. 한 곳에서 정한다.
public enum WebRenderTimingConfig {
    /// 로드 완료까지 기다리는 최대 시간(`URLRequest.timeoutInterval`).
    public static let defaultTimeout: TimeInterval = 30
    /// 로드 뒤 페이지 스크립트가 그리길 기다리는 최대 시간.
    public static let defaultSettleLimit: TimeInterval = 2
    /// 그리기가 끝났는지 재는 간격.
    public static let settleProbeInterval: TimeInterval = 0.25
    /// 끝났다고 보기 전에 최소한 기다리는 시간(로드 직후 다시 이동하는 사이트).
    public static let settleMinimumWait: TimeInterval = 1
    /// 전체 페이지 스냅샷 전 크기 조정이 그려질 시간.
    public static let resizeSettle: TimeInterval = 0.3
}
