import Foundation

public enum PresencePhase: Equatable, Sendable {
    case checking
    case present
    case gracePeriod(remaining: TimeInterval)
    case absent
}

public struct PresenceDecision: Equatable, Sendable {
    public let phase: PresencePhase
    public let shouldKeepDisplayAwake: Bool
}

public struct PresencePolicy: Sendable {
    private var hasObservation = false
    private var missingSince: TimeInterval?

    public init() {}

    public mutating func reset() {
        hasObservation = false
        missingSince = nil
    }

    public mutating func observe(personDetected: Bool, at time: TimeInterval) {
        hasObservation = true

        if personDetected {
            missingSince = nil
        } else if missingSince == nil {
            missingSince = time
        }
    }

    public func decision(at time: TimeInterval, gracePeriod: TimeInterval) -> PresenceDecision {
        guard hasObservation else {
            return PresenceDecision(phase: .checking, shouldKeepDisplayAwake: true)
        }

        guard let missingSince else {
            return PresenceDecision(phase: .present, shouldKeepDisplayAwake: true)
        }

        let remaining = max(0, gracePeriod - (time - missingSince))
        if remaining > 0 {
            return PresenceDecision(
                phase: .gracePeriod(remaining: remaining),
                shouldKeepDisplayAwake: true
            )
        }

        return PresenceDecision(phase: .absent, shouldKeepDisplayAwake: false)
    }
}
