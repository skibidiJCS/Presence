import Testing
@testable import PresenceCore

struct UtilityPolicyTests {
    @Test
    func timerLabelsRemainDistinct() {
        #expect(DurationText.timerLabel(seconds: 60) == "1 minute")
        #expect(DurationText.timerLabel(seconds: 90) == "1 minute 30 seconds")
        #expect(DurationText.timerLabel(seconds: 120) == "2 minutes")
    }

    @Test
    func localInteractionResetsEffectiveIdleTime() {
        var clock = ActivityClock(startingAt: 0)
        clock.recordActivity(at: 300)
        let idleTime = clock.idleTime(at: 300, systemIdleTime: 300)

        #expect(idleTime == 0)
    }

    @Test
    func mostRecentInputSourceControlsIdleTime() {
        let clock = ActivityClock(startingAt: 0)
        let idleTime = clock.idleTime(at: 120, systemIdleTime: 4)

        #expect(idleTime == 4)
    }

    @Test
    func countdownStartsAfterVideoStops() {
        var clock = ActivityClock(startingAt: 0)
        clock.recordActivity(at: 300)

        #expect(clock.idleTime(at: 300, systemIdleTime: 300) == 0)
        #expect(clock.idleTime(at: 310, systemIdleTime: 310) == 10)
    }

    @Test
    func cameraProbeStopsAtMaximumDuration() {
        var schedule = CameraProbeSchedule()
        schedule.markProbeStarted(at: 100)

        #expect(!schedule.probeTimedOut(at: 105, maximumDuration: 6))
        #expect(schedule.probeTimedOut(at: 106, maximumDuration: 6))
    }

    @Test
    func successfulProbeWaitsBeforeCheckingAgain() {
        var schedule = CameraProbeSchedule()
        schedule.markProbeStarted(at: 100)
        schedule.markPresenceDetected(at: 102, recheckInterval: 30)

        #expect(!schedule.shouldStartProbe(at: 131))
        #expect(schedule.shouldStartProbe(at: 132))
    }
}
