import Foundation

final class DisplaySleepController {
    private var activity: NSObjectProtocol?

    func prevent() {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            options: .idleDisplaySleepDisabled,
            reason: "Presence is keeping the display awake"
        )
    }

    func allow() {
        guard let activity else { return }
        ProcessInfo.processInfo.endActivity(activity)
        self.activity = nil
    }
}
