import Foundation

public enum DurationText {
    public static func timerLabel(seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60

        if minutes == 0 {
            return unit(remainingSeconds, singular: "second", plural: "seconds")
        }
        if remainingSeconds == 0 {
            return unit(minutes, singular: "minute", plural: "minutes")
        }

        return [
            unit(minutes, singular: "minute", plural: "minutes"),
            unit(remainingSeconds, singular: "second", plural: "seconds")
        ].joined(separator: " ")
    }

    private static func unit(_ value: Int, singular: String, plural: String) -> String {
        "\(value) \(value == 1 ? singular : plural)"
    }
}

