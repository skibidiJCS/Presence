import Foundation

public enum InactivityPolicy {
    public static func effectiveIdleTime(
        systemIdleTime: TimeInterval,
        localIdleTime: TimeInterval
    ) -> TimeInterval {
        max(0, min(systemIdleTime, localIdleTime))
    }
}

