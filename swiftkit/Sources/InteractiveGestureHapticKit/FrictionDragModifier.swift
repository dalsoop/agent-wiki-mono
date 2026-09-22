import SwiftUI

/// 드래그 제스처 동안의 마찰력 및 속도를 계산하여 물리적 햅틱과 콜백을 연결하는 뷰 모디파이어입니다.
public struct FrictionDragModifier: ViewModifier {
    public var speedThreshold: Double
    public var onFriction: (FrictionDragValue) -> Void

    @State private var startTime: Date?
    @State private var lastLocation: CGPoint?
    @State private var cumulativeDistance: Double = 0.0
    @State private var lastHapticDistance: Double = 0.0

    public init(
        speedThreshold: Double = 100.0,
        onFriction: @escaping (FrictionDragValue) -> Void
    ) {
        self.speedThreshold = speedThreshold
        self.onFriction = onFriction
    }

    public func body(content: Content) -> some View {
        content.gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let now = Date()
                    let currentLoc = value.location

                    guard let start = startTime, let prevLoc = lastLocation else {
                        self.startTime = now
                        self.lastLocation = currentLoc
                        self.cumulativeDistance = 0.0
                        self.lastHapticDistance = 0.0
                        return
                    }

                    let dx = currentLoc.x - prevLoc.x
                    let dy = currentLoc.y - prevLoc.y
                    let stepDistance = sqrt(Double(dx * dx + dy * dy))

                    let dt = max(0.001, now.timeIntervalSince(start))
                    self.cumulativeDistance += stepDistance
                    self.lastLocation = currentLoc

                    let velocity = stepDistance / dt
                    let frictionVal = FrictionDragValue(
                        velocity: velocity,
                        cumulativeDistance: self.cumulativeDistance,
                        duration: dt
                    )

                    // 마찰 햅틱 피드백 트리거 (속도 임계값 초과 또는 24pt 거리 단위 저항)
                    if velocity > self.speedThreshold {
                        HapticFeedbackEngine.trigger(.transientClick)
                    } else if (self.cumulativeDistance - self.lastHapticDistance) >= 24.0 {
                        self.lastHapticDistance = self.cumulativeDistance
                        HapticFeedbackEngine.trigger(.gentleRumble(intensity: 0.3))
                    }

                    self.onFriction(frictionVal)
                }
                .onEnded { _ in
                    self.startTime = nil
                    self.lastLocation = nil
                    self.cumulativeDistance = 0.0
                    self.lastHapticDistance = 0.0
                }
        )
    }
}

extension View {
    /// 마찰 드래그 제스처 및 햅틱 저항 반응을 바인딩합니다.
    public func onFrictionDragGesture(
        speedThreshold: Double = 100.0,
        onFriction: @escaping (_ value: FrictionDragValue) -> Void
    ) -> some View {
        self.modifier(FrictionDragModifier(speedThreshold: speedThreshold, onFriction: onFriction))
    }
}
