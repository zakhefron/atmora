import Foundation
import Testing
@testable import AtmoraCore

@MainActor
@Suite("Focus timer")
struct FocusTimerTests {
    private final class Clock {
        var now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        func advance(_ seconds: TimeInterval) {
            now = now.addingTimeInterval(seconds)
        }
    }

    private func makeTimer(_ clock: Clock) -> FocusTimer {
        FocusTimer(now: { clock.now })
    }

    @Test("Starting exposes a full duration and running phase")
    func start() {
        let clock = Clock()
        let timer = makeTimer(clock)
        timer.start(minutes: 25)

        #expect(timer.phase == .running)
        #expect(timer.duration == 1500)
        #expect(timer.remaining == 1500)
        #expect(timer.remainingSeconds == 1500)
        #expect(timer.progress == 0)
        #expect(timer.isActive)
    }

    @Test("The countdown derives from the wall clock, not tick count")
    func wallClockCountdown() {
        let clock = Clock()
        let timer = makeTimer(clock)
        timer.start(minutes: 25)

        clock.advance(9 * 60)
        timer.refresh()
        #expect(abs(timer.remaining - 16 * 60) < 0.001)
        #expect(abs(timer.progress - 0.36) < 0.0001)

        clock.advance(10 * 60)
        timer.refresh()
        #expect(abs(timer.remaining - 6 * 60) < 0.001)
    }

    @Test("Pause freezes remaining time and resume continues it")
    func pauseAndResume() {
        let clock = Clock()
        let timer = makeTimer(clock)
        timer.start(minutes: 50)

        clock.advance(10 * 60)
        timer.refresh()
        timer.pause()

        #expect(timer.phase == .paused)
        #expect(abs(timer.remaining - 40 * 60) < 0.001)

        clock.advance(30 * 60)
        timer.refresh()
        #expect(abs(timer.remaining - 40 * 60) < 0.001)

        timer.resume()
        #expect(timer.phase == .running)

        clock.advance(60)
        timer.refresh()
        #expect(abs(timer.remaining - 39 * 60) < 0.001)
    }

    @Test("Cancel returns to idle")
    func cancel() {
        let clock = Clock()
        let timer = makeTimer(clock)
        timer.start(minutes: 25)
        timer.cancel()

        #expect(timer.phase == .idle)
        #expect(timer.remaining == 0)
        #expect(!timer.isActive)
    }

    @Test("Finishing notifies exactly once")
    func finish() {
        let clock = Clock()
        let timer = makeTimer(clock)
        var finishCount = 0
        timer.onFinished = { finishCount += 1 }

        timer.start(minutes: 1)
        clock.advance(61)
        timer.refresh()

        #expect(timer.phase == .finished)
        #expect(timer.remaining == 0)
        #expect(abs(timer.progress - 1) < 0.0001)

        timer.refresh()
        #expect(finishCount == 1)
    }

    @Test("Refresh without finishing permission does not complete")
    func deferredFinish() {
        let clock = Clock()
        let timer = makeTimer(clock)
        var finishCount = 0
        timer.onFinished = { finishCount += 1 }

        timer.start(minutes: 5)
        clock.advance(301)
        timer.refresh(allowFinishing: false)

        #expect(timer.phase == .running)
        #expect(timer.remaining == 0)
        #expect(finishCount == 0)
    }

    @Test("A running snapshot restores with the correct remainder")
    func runningSnapshot() throws {
        let clock = Clock()
        let timer = makeTimer(clock)
        timer.start(minutes: 90)
        clock.advance(600)
        timer.refresh()

        let snapshot = try #require(timer.snapshot)
        #expect(snapshot.phase == .running)
        #expect(snapshot.endDate != nil)

        let restored = makeTimer(clock)
        #expect(restored.restore(snapshot))
        #expect(restored.phase == .running)
        #expect(abs(restored.remaining - 80 * 60) < 0.001)
        #expect(abs(restored.duration - 90 * 60) < 0.001)
    }

    @Test("A paused snapshot restores paused")
    func pausedSnapshot() throws {
        let clock = Clock()
        let timer = makeTimer(clock)
        timer.start(minutes: 25)
        clock.advance(120)
        timer.refresh()
        timer.pause()

        let snapshot = try #require(timer.snapshot)
        #expect(snapshot.phase == .paused)

        let restored = makeTimer(clock)
        #expect(restored.restore(snapshot))
        #expect(restored.phase == .paused)
        #expect(abs(restored.remaining - 23 * 60) < 0.001)
    }

    @Test("An expired snapshot shows finished without changing audio")
    func expiredSnapshot() {
        let clock = Clock()
        let snapshot = FocusTimerSnapshot(
            phase: .running,
            endDate: clock.now.addingTimeInterval(-120),
            remaining: 0,
            duration: 25 * 60
        )

        let timer = makeTimer(clock)
        var finishCount = 0
        timer.onFinished = { finishCount += 1 }

        #expect(!timer.restore(snapshot))
        #expect(timer.phase == .finished)
        #expect(finishCount == 0)
    }

    @Test("Idle and finished timers do not produce snapshots")
    func noSnapshotWhenInactive() {
        let clock = Clock()
        let timer = makeTimer(clock)
        #expect(timer.snapshot == nil)

        timer.start(minutes: 1)
        clock.advance(61)
        timer.refresh()
        #expect(timer.phase == .finished)
        #expect(timer.snapshot == nil)

        timer.dismissFinished()
        #expect(timer.phase == .idle)
    }

    @Test("Preview configuration is deterministic")
    func preview() {
        let clock = Clock()
        let timer = makeTimer(clock)
        timer.configureForPreview(duration: 600, remaining: 300, phase: .paused)

        #expect(timer.phase == .paused)
        #expect(timer.remainingSeconds == 300)
        #expect(abs(timer.progress - 0.5) < 0.0001)
    }
}
