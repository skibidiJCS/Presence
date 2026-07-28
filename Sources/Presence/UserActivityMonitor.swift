import AppKit
import CoreGraphics
import Foundation
import PresenceCore

@MainActor
final class UserActivityMonitor {
    private var localEventMonitor: Any?
    private var activityClock = ActivityClock(
        startingAt: ProcessInfo.processInfo.systemUptime
    )

    func start(onInteraction: @escaping @MainActor () -> Void) {
        guard localEventMonitor == nil else { return }

        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [
                .keyDown,
                .leftMouseDown,
                .rightMouseDown,
                .otherMouseDown,
                .scrollWheel,
                .leftMouseDragged,
                .rightMouseDragged,
                .otherMouseDragged
            ]
        ) { [weak self] event in
            Task { @MainActor in
                self?.recordActivity()
                onInteraction()
            }
            return event
        }
    }

    func stop() {
        guard let localEventMonitor else { return }
        NSEvent.removeMonitor(localEventMonitor)
        self.localEventMonitor = nil
    }

    func recordActivity(at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        activityClock.recordActivity(at: time)
    }

    func idleTime(at time: TimeInterval) -> TimeInterval {
        activityClock.idleTime(
            at: time,
            systemIdleTime: Self.systemIdleTime
        )
    }

    private static var systemIdleTime: TimeInterval {
        guard let anyInputEvent = CGEventType(rawValue: UInt32.max) else {
            return 0
        }
        return CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: anyInputEvent
        )
    }
}
