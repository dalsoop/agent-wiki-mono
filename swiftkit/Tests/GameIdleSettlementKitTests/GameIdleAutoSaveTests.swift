import Foundation
import Testing
@testable import GameIdleSettlementKit

@Suite("자동 저장 조율기 — 시계와 스케줄러 주입")
@MainActor
struct GameIdleAutoSaveTests {
    private final class Recorder {
        var triggers: [GameIdleSaveTrigger] = []
        var count: Int { triggers.count }
    }

    private func makeAutoSave(
        debouncer: GameIdleSaveDebouncer = .standardV1
    ) -> (GameIdleAutoSave, ManualGameIdleClock, ManualGameIdleSaveScheduler, Recorder) {
        let clock = ManualGameIdleClock(now: ContinuousClock.Instant.now)
        let scheduler = ManualGameIdleSaveScheduler()
        let recorder = Recorder()
        let autoSave = GameIdleAutoSave(
            debouncer: debouncer,
            clock: clock,
            scheduler: scheduler
        ) { trigger in
            recorder.triggers.append(trigger)
        }
        return (autoSave, clock, scheduler, recorder)
    }

    @Test("요청은 debounce 간격만큼 미뤄지고 그 시각에 저장된다")
    func savesAfterInterval() {
        let (autoSave, clock, scheduler, recorder) = makeAutoSave()
        autoSave.requestSave()
        #expect(autoSave.hasPendingSave)
        #expect(scheduler.lastRequestedDelay == .seconds(5))
        #expect(recorder.count == 0)

        clock.advance(by: .seconds(5))
        #expect(scheduler.fire())
        #expect(recorder.count == 1)
        #expect(recorder.triggers.first?.reason == .deadline)
        #expect(!autoSave.hasPendingSave)
        #expect(autoSave.saveCount == 1)
    }

    @Test("연속 요청은 한 번의 저장으로 병합된다")
    func coalescesConsecutiveRequests() {
        let (autoSave, clock, scheduler, recorder) = makeAutoSave()
        autoSave.requestSave()
        clock.advance(by: .seconds(2))
        autoSave.requestSave()
        clock.advance(by: .seconds(1))
        autoSave.requestSave()
        #expect(autoSave.pendingRequestCount == 3)

        // 첫 예약이 일찍 깨어나도 마감이 밀렸으므로 저장하지 않고 다시 잰다.
        clock.advance(by: .seconds(2))
        #expect(scheduler.fire())
        #expect(recorder.count == 0)
        #expect(scheduler.lastRequestedDelay == .seconds(3))

        clock.advance(by: .seconds(3))
        #expect(scheduler.fire())
        #expect(recorder.count == 1)
        #expect(recorder.triggers.first?.coalescedRequestCount == 3)
    }

    @Test("강제 flush 는 기다리지 않고 저장한다(월 경계·앱 종료)")
    func flushSavesImmediately() {
        let (autoSave, _, scheduler, recorder) = makeAutoSave()
        autoSave.requestSave()
        let trigger = autoSave.flush()
        #expect(trigger?.reason == .flush)
        #expect(recorder.count == 1)
        #expect(scheduler.cancelCount == 1)
        #expect(!scheduler.hasPendingWakeUp)

        // 대기가 없으면 flush 는 아무 일도 하지 않는다.
        #expect(autoSave.flush() == nil)
        #expect(recorder.count == 1)
    }

    @Test("즉시 저장 요청은 대기 없이 만기된다")
    func immediateSave() {
        let (autoSave, _, scheduler, recorder) = makeAutoSave()
        autoSave.requestImmediateSave()
        #expect(scheduler.lastRequestedDelay == .zero)
        #expect(scheduler.fire())
        #expect(recorder.count == 1)
    }

    @Test("틱 루프 폴링 경로로도 저장된다")
    func pollPath() {
        let (autoSave, clock, _, recorder) = makeAutoSave()
        autoSave.requestSave()
        #expect(autoSave.poll() == nil)
        clock.advance(by: .seconds(5))
        #expect(autoSave.poll()?.reason == .deadline)
        #expect(recorder.count == 1)
        #expect(autoSave.poll() == nil)
        #expect(recorder.count == 1)
    }

    @Test("cancel 은 예약된 저장을 버린다")
    func cancelDropsPendingSave() {
        let (autoSave, clock, scheduler, recorder) = makeAutoSave()
        autoSave.requestSave()
        autoSave.cancel()
        #expect(!autoSave.hasPendingSave)
        #expect(scheduler.cancelCount == 1)

        clock.advance(by: .seconds(60))
        #expect(!scheduler.fire())
        #expect(autoSave.poll() == nil)
        #expect(recorder.count == 0)
    }

    @Test("gaya 프리셋은 첫 요청 기준 0.5초 뒤 한 번 저장한다")
    func shortSessionPreset() {
        let (autoSave, clock, scheduler, recorder) = makeAutoSave(debouncer: .shortSessionV1)
        autoSave.requestSave()
        #expect(scheduler.lastRequestedDelay == .milliseconds(500))
        clock.advance(by: .milliseconds(300))
        autoSave.requestSave()
        #expect(scheduler.lastRequestedDelay == .milliseconds(200))

        clock.advance(by: .milliseconds(200))
        #expect(scheduler.fire())
        #expect(recorder.count == 1)
        #expect(recorder.triggers.first?.coalescedRequestCount == 2)
    }

    @Test("실시간 스케줄러는 예약과 취소 상태를 노출한다")
    func realScheduler() async {
        let scheduler = DebouncingGameIdleSaveScheduler()
        #expect(!scheduler.hasPendingWakeUp)
        scheduler.schedule(after: .seconds(60)) {}
        #expect(scheduler.hasPendingWakeUp)
        scheduler.cancel()
        #expect(!scheduler.hasPendingWakeUp)

        let recorder = Recorder()
        scheduler.schedule(after: .zero) {
            recorder.triggers.append(
                GameIdleSaveTrigger(
                    reason: .deadline,
                    coalescedRequestCount: 1,
                    firedAt: ContinuousClock.Instant.now
                )
            )
        }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(recorder.count == 1)
    }
}
