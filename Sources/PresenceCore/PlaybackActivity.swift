public enum PlaybackActivity: Equatable, Sendable {
    case none
    case audio
    case display
}

public struct PlaybackSignal: Equatable, Sendable {
    public let ownerProcessID: Int32
    public let isActive: Bool
    public let preventsDisplaySleep: Bool
    public let preventsIdleSystemSleep: Bool
    public let resources: Set<String>

    public init(
        ownerProcessID: Int32,
        isActive: Bool,
        preventsDisplaySleep: Bool,
        preventsIdleSystemSleep: Bool,
        resources: Set<String>
    ) {
        self.ownerProcessID = ownerProcessID
        self.isActive = isActive
        self.preventsDisplaySleep = preventsDisplaySleep
        self.preventsIdleSystemSleep = preventsIdleSystemSleep
        self.resources = resources
    }
}

public struct PlaybackActivityClassifier: Sendable {
    public init() {}

    public func activity(
        from signals: [PlaybackSignal],
        excluding processID: Int32
    ) -> PlaybackActivity {
        var audioIsPlaying = false

        for signal in signals
        where signal.ownerProcessID != processID && signal.isActive {
            if signal.preventsDisplaySleep {
                return .display
            }

            if signal.preventsIdleSystemSleep,
               signal.resources.contains("audio-out") {
                audioIsPlaying = true
            }
        }

        return audioIsPlaying ? .audio : .none
    }
}
