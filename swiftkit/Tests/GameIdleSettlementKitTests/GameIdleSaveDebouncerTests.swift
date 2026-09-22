import Foundation
import Testing
@testable import GameIdleSettlementKit

@Suite("디바운스 저장 코어 — 주입된 시간으로만 동작")
struct GameIdleSaveDebouncerTests {
    private let start = ContinuousClock.Instant.now

    @Test("음수 간격은 막힌다")
    func negativeInterval() {
        #expect(throws: GameIdleSaveDebouncerError.negativeInterval(.seconds(-1))) {
            try GameIdleSaveDebouncer(interval: .seconds(-1))
        }
    }

    @Test("프리셋은 두 선행 구현의 값과 같다")
    func presets() {
        #expect(GameIdleSaveDebouncer.standardV1.interval == .seconds(5))
        #expect(GameIdleSaveDebouncer.standardV1.coalescing == .restartOnRequest)
        #expect(GameIdleSaveDebouncer.shortSessionV1.interval == .milliseconds(500))
        #expect(GameIdleSaveDebouncer.shortSessionV1.coalescing == .keepFirstDeadline)
    }

    @Test("마감 전에는 저장하지 않고, 마감에 정확히 도달하면 저장한다")
    func firesAtDeadline() {
        var debouncer = GameIdleSaveDebouncer.standardV1
        #expect(!debouncer.hasPendingSave)
        #expect(debouncer.remaining(at: start) == nil)

        debouncer.request(at: start)
        #expect(debouncer.hasPendingSave)
        #expect(debouncer.remaining(at: start) == .seconds(5))
        #expect(debouncer.poll(at: start.advanced(by: .seconds(4))) == nil)
        #expect(debouncer.remaining(at: start.advanced(by: .seconds(4))) == .seconds(1))

        let trigger = debouncer.poll(at: start.advanced(by: .seconds(5)))
        #expect(trigger?.reason == .deadline)
        #expect(trigger?.coalescedRequestCount == 1)
        #expect(!debouncer.hasPendingSave)
        #expect(debouncer.poll(at: start.advanced(by: .seconds(60))) == nil)
    }

    @Test("restartOnRequest 는 요청마다 마감을 뒤로 민다")
    func restartCoalescing() {
        var debouncer = GameIdleSaveDebouncer.standardV1
        debouncer.request(at: start)
        debouncer.request(at: start.advanced(by: .seconds(3)))
        #expect(debouncer.pendingRequestCount == 2)
        #expect(debouncer.poll(at: start.advanced(by: .seconds(5))) == nil)

        let trigger = debouncer.poll(at: start.advanced(by: .seconds(8)))
        #expect(trigger?.coalescedRequestCount == 2)
        #expect(debouncer.pendingRequestCount == 0)
    }

    @Test("keepFirstDeadline 은 첫 요청 마감을 지킨다")
    func keepFirstCoalescing() {
        var debouncer = GameIdleSaveDebouncer.shortSessionV1
        debouncer.request(at: start)
        debouncer.request(at: start.advanced(by: .milliseconds(300)))
        #expect(debouncer.deadline == start.advanced(by: .milliseconds(500)))

        let trigger = debouncer.poll(at: start.advanced(by: .milliseconds(500)))
        #expect(trigger?.coalescedRequestCount == 2)
    }

    @Test("마감이 지난 뒤 남은 시간은 0 으로 접힌다")
    func remainingClampsToZero() {
        var debouncer = GameIdleSaveDebouncer.standardV1
        debouncer.request(at: start)
        #expect(debouncer.remaining(at: start.advanced(by: .seconds(60))) == .zero)
        #expect(debouncer.isDue(at: start.advanced(by: .seconds(60))))
    }

    @Test("즉시 요청은 대기 없이 만기된다")
    func immediateRequest() {
        var debouncer = GameIdleSaveDebouncer.standardV1
        debouncer.requestImmediate(at: start)
        #expect(debouncer.remaining(at: start) == .zero)
        #expect(debouncer.poll(at: start)?.reason == .deadline)
    }

    @Test("강제 flush 는 마감 전에도 저장하고, 대기가 없으면 아무 일도 없다")
    func flush() {
        var debouncer = GameIdleSaveDebouncer.standardV1
        #expect(debouncer.flush(at: start) == nil)

        debouncer.request(at: start)
        debouncer.request(at: start)
        let trigger = debouncer.flush(at: start.advanced(by: .seconds(1)))
        #expect(trigger?.reason == .flush)
        #expect(trigger?.coalescedRequestCount == 2)
        #expect(!debouncer.hasPendingSave)
        #expect(debouncer.flush(at: start.advanced(by: .seconds(1))) == nil)
    }

    @Test("cancel 은 대기 중인 저장을 버린다")
    func cancel() {
        var debouncer = GameIdleSaveDebouncer.standardV1
        debouncer.request(at: start)
        debouncer.cancel()
        #expect(!debouncer.hasPendingSave)
        #expect(debouncer.pendingRequestCount == 0)
        #expect(debouncer.poll(at: start.advanced(by: .seconds(60))) == nil)
        #expect(debouncer.flush(at: start) == nil)
    }

    @Test("간격 0 은 즉시 저장을 뜻한다")
    func zeroInterval() throws {
        var debouncer = try GameIdleSaveDebouncer(interval: .zero)
        debouncer.request(at: start)
        #expect(debouncer.poll(at: start)?.reason == .deadline)
    }

    @Test("수동 단조 시계는 참조 의미로 전진하고 뒤로 가지 않는다")
    func manualClock() {
        let clock = ManualGameIdleClock(now: start)
        #expect(clock.now() == start)
        clock.advance(by: .seconds(3))
        #expect(clock.now() == start.advanced(by: .seconds(3)))
        clock.advance(by: .seconds(-10))
        #expect(clock.now() == start.advanced(by: .seconds(3)))
    }
}
