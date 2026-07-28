import Foundation

public struct ActivityClock: Sendable {
    private var lastActivityAt: TimeInterval

    public init(startingAt time: TimeInterval) {
        lastActivityAt = time
    }

    public mutating func recordActivity(at time: TimeInterval) {
        lastActivityAt = time
    }

    public func idleTime(
        at time: TimeInterval,
        systemIdleTime: TimeInterval
    ) -> TimeInterval {
        max(0, min(systemIdleTime, time - lastActivityAt))
    }
}

