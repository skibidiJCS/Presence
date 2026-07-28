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
        let idleTime = InactivityPolicy.effectiveIdleTime(
            systemIdleTime: 300,
            localIdleTime: 0
        )

        #expect(idleTime == 0)
    }

    @Test
    func mostRecentInputSourceControlsIdleTime() {
        let idleTime = InactivityPolicy.effectiveIdleTime(
            systemIdleTime: 4,
            localIdleTime: 120
        )

        #expect(idleTime == 4)
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
