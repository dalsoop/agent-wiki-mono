import Foundation

/// 인간 행동 시뮬레이션 — CDP Input 이벤트를 사람처럼 생성.
///
/// CDP dispatchMouseEvent 는 순간이동이라 봇 탐지에 걸린다.
/// 이 모듈은 베지어 곡선 마우스 경로 + 로그정규 타이밍으로
/// 사람 같은 입력 이벤트 스트림을 만든다.
public enum BehaviorSimulator {

    /// 마우스 이동 경로의 한 점.
    public struct MousePoint: Sendable {
        public let x: Double
        public let y: Double
        public let delayMs: Int
    }

    /// 시작점에서 끝점까지 베지어 곡선 경로 생성.
    /// 제어점은 시작-끝 직선에서 랜덤 오프셋.
    public static func mousePath(
        from start: (x: Double, y: Double),
        to end: (x: Double, y: Double),
        steps: Int = 20
    ) -> [MousePoint] {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let dist = sqrt(dx * dx + dy * dy)

        let cp1x = start.x + dx * 0.25 + randomOffset(dist * 0.15)
        let cp1y = start.y + dy * 0.25 + randomOffset(dist * 0.15)
        let cp2x = start.x + dx * 0.75 + randomOffset(dist * 0.1)
        let cp2y = start.y + dy * 0.75 + randomOffset(dist * 0.1)

        var points: [MousePoint] = []
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let u = 1.0 - t
            let x = u*u*u*start.x + 3*u*u*t*cp1x + 3*u*t*t*cp2x + t*t*t*end.x
            let y = u*u*u*start.y + 3*u*u*t*cp1y + 3*u*t*t*cp2y + t*t*t*end.y
            let delay = humanDelay(baseMs: 8, variance: 4)
            points.append(MousePoint(x: x, y: y, delayMs: delay))
        }
        return points
    }

    /// 클릭 전 hover dwell 시간 (ms).
    public static func hoverDwellMs() -> Int {
        humanDelay(baseMs: 150, variance: 80)
    }

    /// 클릭 후 release 까지 시간 (ms).
    public static func clickHoldMs() -> Int {
        humanDelay(baseMs: 80, variance: 30)
    }

    /// 타이핑 한 글자 간격 (ms).
    public static func typeIntervalMs() -> Int {
        humanDelay(baseMs: 90, variance: 40)
    }

    /// 페이지 이동 후 읽기 대기 (ms).
    public static func readingDelayMs() -> Int {
        humanDelay(baseMs: 1500, variance: 800)
    }

    /// CDP mouseMoved 이벤트 스트림을 생성하는 JS.
    /// 경로를 따라 mousemove 를 발생시키고 마지막에 클릭한다.
    public static func humanClickScript(path: [MousePoint], targetX: Int, targetY: Int,
                                         hoverMs: Int, holdMs: Int) -> String {
        let moves = path.map { "[\(Int($0.x)),\(Int($0.y)),\($0.delayMs)]" }.joined(separator: ",")
        return """
        (async () => {
            const path = [\(moves)];
            for (const [x, y, ms] of path) {
                window.dispatchEvent(new MouseEvent('mousemove', {clientX: x, clientY: y, bubbles: true}));
                await new Promise(r => setTimeout(r, ms));
            }
            await new Promise(r => setTimeout(r, \(hoverMs)));
            const el = document.elementFromPoint(\(targetX), \(targetY));
            if (el) {
                el.dispatchEvent(new MouseEvent('mousedown', {clientX: \(targetX), clientY: \(targetY), bubbles: true}));
                await new Promise(r => setTimeout(r, \(holdMs)));
                el.dispatchEvent(new MouseEvent('mouseup', {clientX: \(targetX), clientY: \(targetY), bubbles: true}));
                el.dispatchEvent(new MouseEvent('click', {clientX: \(targetX), clientY: \(targetY), bubbles: true}));
            }
            return el ? el.tagName : null;
        })()
        """
    }

    // MARK: - Scroll

    /// 자연스러운 스크롤 이벤트 시퀀스 (관성 시뮬).
    /// 빠르게 시작 → 느리게 끝. CDP Input.dispatchMouseEvent(mouseWheel) 용.
    public struct ScrollStep: Sendable {
        public let deltaY: Int
        public let deltaX: Int
        public let delayMs: Int
    }

    public static func humanScroll(pixels: Int, steps: Int = 8) -> [ScrollStep] {
        var result: [ScrollStep] = []
        var remaining = abs(pixels)
        let direction = pixels > 0 ? 1 : -1
        for i in 0..<steps {
            let fraction = Double(steps - i) / Double(steps)
            let chunk = max(1, Int(Double(remaining) * fraction * 0.4))
            let actual = min(chunk, remaining)
            remaining -= actual
            let jitterX = Int.random(in: -2...2)
            let delay = humanDelay(baseMs: 30 + i * 10, variance: 15)
            result.append(ScrollStep(deltaY: actual * direction, deltaX: jitterX, delayMs: delay))
            if remaining <= 0 { break }
        }
        if remaining > 0 {
            result.append(ScrollStep(deltaY: remaining * direction, deltaX: 0, delayMs: humanDelay(baseMs: 50, variance: 20)))
        }
        return result
    }

    // MARK: - Typing

    /// 타이핑 이벤트 시퀀스 — 로그정규 간격 + 선택적 오타.
    public struct TypeStep: Sendable {
        public let char: Character
        public let delayMs: Int
        public let isBackspace: Bool
    }

    public static func humanType(text: String, typoRate: Double = 0.0) -> [TypeStep] {
        var result: [TypeStep] = []
        for ch in text {
            if typoRate > 0 && Double.random(in: 0...1) < typoRate {
                let typo = Character(UnicodeScalar(Int.random(in: 97...122))!)
                result.append(TypeStep(char: typo, delayMs: typeIntervalMs(), isBackspace: false))
                result.append(TypeStep(char: "\u{08}", delayMs: humanDelay(baseMs: 120, variance: 50), isBackspace: true))
            }
            result.append(TypeStep(char: ch, delayMs: typeIntervalMs(), isBackspace: false))
        }
        return result
    }

    // MARK: - Idle Jitter

    /// 유휴 상태 마우스 미세 움직임 — 사람은 완전히 멈추지 않음.
    public struct JitterPoint: Sendable {
        public let dx: Int
        public let dy: Int
        public let delayMs: Int
    }

    public static func idleMouseJitter(count: Int = 5) -> [JitterPoint] {
        (0..<count).map { _ in
            JitterPoint(
                dx: Int.random(in: -3...3),
                dy: Int.random(in: -3...3),
                delayMs: humanDelay(baseMs: 1000, variance: 500)
            )
        }
    }

    // MARK: - Private

    /// 로그정규 분포 근사 — 평균보다 약간 짧은 값이 많고 가끔 긴 값.
    private static func humanDelay(baseMs: Int, variance: Int) -> Int {
        let u1 = Double.random(in: 0.001...1.0)
        let u2 = Double.random(in: 0.0...1.0)
        let normal = sqrt(-2.0 * log(u1)) * cos(2.0 * .pi * u2)
        let value = Double(baseMs) + normal * Double(variance)
        return max(1, Int(value))
    }

    private static func randomOffset(_ magnitude: Double) -> Double {
        Double.random(in: -magnitude...magnitude)
    }
}
