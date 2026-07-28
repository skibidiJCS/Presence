import Foundation

public struct CameraProbeSchedule: Sendable {
    private var probeStartedAt: TimeInterval?
    private var nextProbeAt: TimeInterval = 0

    public init() {}

    public var isProbeActive: Bool {
        probeStartedAt != nil
    }

    public mutating func reset() {
        probeStartedAt = nil
        nextProbeAt = 0
    }

    public func shouldStartProbe(at time: TimeInterval) -> Bool {
        probeStartedAt == nil && time >= nextProbeAt
    }

    public mutating func markProbeStarted(at time: TimeInterval) {
        probeStartedAt = time
    }

    public func probeTimedOut(at time: TimeInterval, maximumDuration: TimeInterval) -> Bool {
        guard let probeStartedAt else { return false }
        return time - probeStartedAt >= maximumDuration
    }

    public mutating func markPresenceDetected(
        at time: TimeInterval,
        recheckInterval: TimeInterval
    ) {
        probeStartedAt = nil
        nextProbeAt = time + recheckInterval
    }

    public mutating func markProbeMissed(
        at time: TimeInterval,
        recheckInterval: TimeInterval
    ) {
        probeStartedAt = nil
        nextProbeAt = time + recheckInterval
    }
}

