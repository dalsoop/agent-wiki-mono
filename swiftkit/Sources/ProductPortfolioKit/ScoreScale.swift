import Foundation

/// 점수 축 SSOT.
///
/// - **신호(signal)**: 설치·공증·readiness 등 관측 단위. 0…`signalMax`(5).
/// - **표시(display)**: PES GUI·저장·리포트 단위. 0…`displayMax`(100).
///
/// 변환은 항상 이 타입을 통한다. 앱 브리지가 `×20` 리터럴을 흩뿌리지 않는다.
public enum ScoreScale {
    /// Kit / readiness / signal-compose 내부 만점.
    public static let signalMax: Double = 5
    /// Product Evaluation Studio 저장·표시 만점.
    public static let displayMax: Double = 100

    public static var bridgeFactor: Double { displayMax / signalMax }

    /// 0…5 신호 → 0…100 표시.
    public static func toDisplay(_ signal: Double) -> Double {
        clamp(signal * bridgeFactor, max: displayMax)
    }

    /// 0…100 표시 → 0…5 신호.
    public static func toSignal(_ display: Double) -> Double {
        clamp(display / bridgeFactor, max: signalMax)
    }

    public static func clampSignal(_ value: Double) -> Double {
        clamp(value, max: signalMax)
    }

    public static func clampDisplay(_ value: Double) -> Double {
        clamp(value, max: displayMax)
    }

    private static func clamp(_ value: Double, max: Double) -> Double {
        let stepped = (value * 10).rounded() / 10
        return min(max, Swift.max(0, stepped))
    }
}
