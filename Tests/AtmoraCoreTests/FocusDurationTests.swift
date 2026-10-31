import Testing
@testable import AtmoraCore

@Suite("Focus duration")
struct FocusDurationTests {
    @Test("The shared range is five to two hundred and forty minutes")
    func range() {
        #expect(FocusDuration.minimumMinutes == 5)
        #expect(FocusDuration.maximumMinutes == 240)
        #expect(FocusDuration.stepMinutes == 5)
        #expect(FocusDuration.defaultMinutes == 25)
    }

    @Test("Values below the range clamp up to the first step")
    func clampsLow() {
        #expect(FocusDuration.clamp(-30) == 5)
        #expect(FocusDuration.clamp(0) == 5)
        #expect(FocusDuration.clamp(2) == 5)
        #expect(FocusDuration.clamp(4) == 5)
        #expect(FocusDuration.clamp(5) == 5)
    }

    @Test("Values above the range clamp down to the last step")
    func clampsHigh() {
        #expect(FocusDuration.clamp(241) == 240)
        #expect(FocusDuration.clamp(300) == 240)
        #expect(FocusDuration.clamp(10_000) == 240)
        #expect(FocusDuration.clamp(240) == 240)
    }

    @Test("Values snap to the nearest five-minute step")
    func snapsToStep() {
        #expect(FocusDuration.clamp(25) == 25)
        #expect(FocusDuration.clamp(26) == 25)
        #expect(FocusDuration.clamp(27) == 25)
        #expect(FocusDuration.clamp(28) == 30)
        #expect(FocusDuration.clamp(52) == 50)
        #expect(FocusDuration.clamp(53) == 55)
        #expect(FocusDuration.clamp(238) == 240)
    }

    @Test("Clamping is idempotent")
    func idempotent() {
        for minutes in stride(from: -50, through: 400, by: 3) {
            let once = FocusDuration.clamp(minutes)
            #expect(FocusDuration.clamp(once) == once)
            #expect((FocusDuration.minimumMinutes...FocusDuration.maximumMinutes).contains(once))
            #expect(once.isMultiple(of: FocusDuration.stepMinutes))
        }
    }

    @Test("Summaries read naturally")
    func summaries() {
        #expect(FocusDuration.summary(for: 5) == "5 min")
        #expect(FocusDuration.summary(for: 25) == "25 min")
        #expect(FocusDuration.summary(for: 60) == "1 hour")
        #expect(FocusDuration.summary(for: 75) == "1 hr 15 min")
        #expect(FocusDuration.summary(for: 120) == "2 hours")
        #expect(FocusDuration.summary(for: 180) == "3 hours")
        #expect(FocusDuration.summary(for: 240) == "4 hours")
    }

    @Test("Summaries tolerate out-of-range input without crashing")
    func summaryBounds() {
        #expect(FocusDuration.summary(for: -20) == "0 min")
        #expect(FocusDuration.summary(for: 10_000) == "4 hours")
    }
}
