import SwiftUI

enum MonitoringStatus: Equatable {
    case disabled
    case paused
    case waiting(secondsRemaining: TimeInterval)
    case checking
    case present
    case gracePeriod(secondsRemaining: TimeInterval)
    case absent
    case permissionDenied
    case cameraUnavailable(String)

    var title: String {
        switch self {
        case .disabled: "Detection off"
        case .paused: "Monitoring paused"
        case .waiting: "Waiting for inactivity"
        case .checking: "Checking for presence"
        case .present: "You’re present"
        case .gracePeriod: "Presence temporarily lost"
        case .absent: "No one detected"
        case .permissionDenied: "Camera access required"
        case .cameraUnavailable: "Camera unavailable"
        }
    }

    var detail: String {
        switch self {
        case .disabled:
            "macOS controls display sleep normally."
        case .paused:
            "Camera and sleep prevention are off."
        case let .waiting(seconds):
            "Camera starts in \(Self.duration(seconds))."
        case .checking:
            "Camera is active while Presence checks locally."
        case .present:
            "Display sleep is being prevented."
        case let .gracePeriod(seconds):
            "Waiting \(Self.duration(seconds)) before allowing sleep."
        case .absent:
            "Display sleep is allowed until you return."
        case .permissionDenied:
            "Allow Presence in System Settings → Privacy & Security → Camera."
        case let .cameraUnavailable(message):
            message
        }
    }

    var symbol: String {
        switch self {
        case .disabled: "eye.slash"
        case .paused: "pause.circle.fill"
        case .waiting: "clock.fill"
        case .checking: "camera.fill"
        case .present: "person.crop.circle.fill"
        case .gracePeriod: "person.crop.circle.badge.questionmark"
        case .absent: "moon.fill"
        case .permissionDenied, .cameraUnavailable: "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .present: .green
        case .checking, .gracePeriod: .orange
        case .permissionDenied, .cameraUnavailable: .red
        case .disabled, .paused, .waiting, .absent: .secondary
        }
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        let rounded = max(0, Int(ceil(seconds)))
        if rounded < 60 {
            return "\(rounded)s"
        }
        let minutes = rounded / 60
        let remainder = rounded % 60
        return remainder == 0 ? "\(minutes)m" : "\(minutes)m \(remainder)s"
    }
}

