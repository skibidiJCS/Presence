import Testing
@testable import PresenceCore

struct PresencePolicyTests {
    @Test
    func checkingKeepsDisplayAwakeUntilFirstObservation() {
        let policy = PresencePolicy()
        let decision = policy.decision(at: 100, gracePeriod: 30)

        #expect(decision.phase == .checking)
        #expect(decision.shouldKeepDisplayAwake)
    }

    @Test
    func detectedPersonKeepsDisplayAwake() {
        var policy = PresencePolicy()
        policy.observe(personDetected: true, at: 100)
        let decision = policy.decision(at: 200, gracePeriod: 30)

        #expect(decision.phase == .present)
        #expect(decision.shouldKeepDisplayAwake)
    }

    @Test
    func temporaryOcclusionUsesGracePeriod() {
        var policy = PresencePolicy()
        policy.observe(personDetected: true, at: 100)
        policy.observe(personDetected: false, at: 110)
        let decision = policy.decision(at: 125, gracePeriod: 30)

        #expect(decision.phase == .gracePeriod(remaining: 15))
        #expect(decision.shouldKeepDisplayAwake)
    }

    @Test
    func absenceAllowsDisplaySleepAfterGracePeriod() {
        var policy = PresencePolicy()
        policy.observe(personDetected: true, at: 100)
        policy.observe(personDetected: false, at: 110)
        let decision = policy.decision(at: 140, gracePeriod: 30)

        #expect(decision.phase == .absent)
        #expect(!decision.shouldKeepDisplayAwake)
    }

    @Test
    func detectionDuringGracePeriodRestoresPresence() {
        var policy = PresencePolicy()
        policy.observe(personDetected: false, at: 100)
        policy.observe(personDetected: true, at: 120)
        let decision = policy.decision(at: 121, gracePeriod: 30)

        #expect(decision.phase == .present)
        #expect(decision.shouldKeepDisplayAwake)
    }
}

