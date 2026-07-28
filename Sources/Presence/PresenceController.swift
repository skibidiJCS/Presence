import AppKit
@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import PresenceCore
import ServiceManagement

@MainActor
final class PresenceController: ObservableObject {
    static let shared = PresenceController()

    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.enabled)
            reevaluate()
        }
    }

    @Published var isPaused = false {
        didSet { reevaluate() }
    }

    @Published var selectedCameraID: String {
        didSet {
            defaults.set(selectedCameraID, forKey: Keys.cameraID)
            restartCameraIfNeeded()
        }
    }

    @Published var inactivitySeconds: TimeInterval {
        didSet {
            defaults.set(inactivitySeconds, forKey: Keys.inactivity)
            reevaluate()
        }
    }

    @Published var absenceGraceSeconds: TimeInterval {
        didSet {
            defaults.set(absenceGraceSeconds, forKey: Keys.absenceGrace)
            reevaluate()
        }
    }

    @Published private(set) var status: MonitoringStatus = .waiting(secondsRemaining: 60)
    @Published private(set) var cameras: [CameraChoice] = []
    @Published private(set) var isCameraActive = false
    @Published private(set) var launchesAtLogin = false
    @Published var loginItemMessage: String?

    let inactivityOptions: [TimeInterval] = [30, 60, 120, 300, 600]
    let absenceOptions: [TimeInterval] = [10, 20, 30, 60, 90, 120]

    var menuBarSymbol: String {
        switch status {
        case .present: "person.crop.circle.fill"
        case .checking, .gracePeriod: "eye.fill"
        case .permissionDenied, .cameraUnavailable: "exclamationmark.triangle.fill"
        case .disabled: "eye.slash"
        case .paused: "pause.circle"
        case .waiting, .absent: "eye"
        }
    }

    private enum Keys {
        static let enabled = "presence.enabled"
        static let cameraID = "presence.cameraID"
        static let inactivity = "presence.inactivitySeconds"
        static let absenceGrace = "presence.absenceGraceSeconds"
    }

    private let defaults = UserDefaults.standard
    private let cameraMonitor = CameraMonitor()
    private var policy = PresencePolicy()
    private var timer: Timer?
    private var localEventMonitor: Any?
    private var displaySleepActivity: NSObjectProtocol?
    private var started = false
    private var lastCameraRefresh: TimeInterval = 0
    private var lastLocalInteractionAt = ProcessInfo.processInfo.systemUptime
    private var cameraRetryAfter: TimeInterval = 0
    private var cameraFailureMessage: String?

    private init() {
        if defaults.object(forKey: Keys.enabled) == nil {
            isEnabled = true
        } else {
            isEnabled = defaults.bool(forKey: Keys.enabled)
        }

        selectedCameraID = defaults.string(forKey: Keys.cameraID) ?? ""
        inactivitySeconds = defaults.object(forKey: Keys.inactivity) as? TimeInterval ?? 60
        absenceGraceSeconds = defaults.object(forKey: Keys.absenceGrace) as? TimeInterval ?? 30
    }

    func start() {
        guard !started else { return }
        started = true

        refreshCameras()
        refreshLoginItemStatus()
        requestCameraAccessIfNeeded()

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }

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
                self?.recordInteraction()
            }
            return event
        }

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(screenDidSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(screenDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )

        tick()
    }

    func shutdown() {
        timer?.invalidate()
        timer = nil
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
        stopCamera()
        allowDisplaySleep()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        recordInteraction()
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemMessage = nil
        } catch {
            loginItemMessage = "Could not update the login item. Move Presence to Applications and try again."
        }
        refreshLoginItemStatus()
    }

    func openCameraSettings() {
        recordInteraction()
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func openLoginItemSettings() {
        recordInteraction()
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func formattedTimer(_ seconds: TimeInterval) -> String {
        DurationText.timerLabel(seconds: seconds)
    }

    func recordInteraction() {
        lastLocalInteractionAt = ProcessInfo.processInfo.systemUptime
        stopCamera()
        allowDisplaySleep()
        resetCameraRetry()
        reevaluate()
    }

    @objc private func screenDidSleep() {
        stopCamera()
        allowDisplaySleep()
    }

    @objc private func screenDidWake() {
        tick()
    }

    private func requestCameraAccessIfNeeded() {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined else {
            return
        }

        AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastCameraRefresh >= 10 {
            refreshCameras()
            lastCameraRefresh = now
        }

        guard isEnabled else {
            status = .disabled
            stopCamera()
            allowDisplaySleep()
            resetCameraRetry()
            return
        }

        guard !isPaused else {
            status = .paused
            stopCamera()
            allowDisplaySleep()
            resetCameraRetry()
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted:
            status = .permissionDenied
            stopCamera()
            allowDisplaySleep()
            resetCameraRetry()
            return
        case .notDetermined:
            status = .waiting(secondsRemaining: inactivitySeconds)
            stopCamera()
            allowDisplaySleep()
            resetCameraRetry()
            return
        case .authorized:
            break
        @unknown default:
            status = .cameraUnavailable("Camera permission could not be determined.")
            stopCamera()
            allowDisplaySleep()
            resetCameraRetry()
            return
        }

        let idleTime = InactivityPolicy.effectiveIdleTime(
            systemIdleTime: Self.userIdleTime,
            localIdleTime: now - lastLocalInteractionAt
        )
        guard idleTime >= inactivitySeconds else {
            status = .waiting(secondsRemaining: inactivitySeconds - idleTime)
            stopCamera()
            allowDisplaySleep()
            resetCameraRetry()
            return
        }

        if !isCameraActive {
            if now < cameraRetryAfter {
                status = .cameraUnavailable(
                    cameraFailureMessage
                        ?? "Camera is temporarily unavailable. Display sleep is prevented while Presence retries."
                )
                preventDisplaySleep()
                return
            }
            startCamera()
            guard isCameraActive else { return }
        }
        applyPolicyDecision(at: now)
    }

    private func startCamera() {
        guard !cameras.isEmpty else {
            status = .cameraUnavailable("No camera was found.")
            allowDisplaySleep()
            return
        }

        policy.reset()
        resetCameraRetry()
        isCameraActive = true
        preventDisplaySleep()
        status = .checking

        let deviceID = selectedCameraID.isEmpty ? nil : selectedCameraID
        cameraMonitor.start(
            deviceID: deviceID,
            onObservation: { [weak self] detected in
                Task { @MainActor in
                    guard let self else { return }
                    self.policy.observe(
                        personDetected: detected,
                        at: ProcessInfo.processInfo.systemUptime
                    )
                    self.applyPolicyDecision(at: ProcessInfo.processInfo.systemUptime)
                }
            },
            onError: { [weak self] message in
                Task { @MainActor in
                    guard let self else { return }
                    self.isCameraActive = false
                    self.cameraFailureMessage =
                        "\(message) Display sleep is prevented while Presence retries."
                    self.cameraRetryAfter = ProcessInfo.processInfo.systemUptime + 15
                    self.status = .cameraUnavailable(self.cameraFailureMessage ?? message)
                    self.preventDisplaySleep()
                }
            }
        )
    }

    private func stopCamera() {
        guard isCameraActive else { return }
        cameraMonitor.stop()
        isCameraActive = false
        policy.reset()
    }

    private func restartCameraIfNeeded() {
        guard isCameraActive else { return }
        stopCamera()
        tick()
    }

    private func applyPolicyDecision(at time: TimeInterval) {
        let decision = policy.decision(at: time, gracePeriod: absenceGraceSeconds)
        switch decision.phase {
        case .checking:
            status = .checking
        case .present:
            status = .present
        case let .gracePeriod(remaining):
            status = .gracePeriod(secondsRemaining: remaining)
        case .absent:
            status = .absent
        }

        if decision.shouldKeepDisplayAwake {
            preventDisplaySleep()
        } else {
            allowDisplaySleep()
        }
    }

    private func preventDisplaySleep() {
        guard displaySleepActivity == nil else { return }
        displaySleepActivity = ProcessInfo.processInfo.beginActivity(
            options: .idleDisplaySleepDisabled,
            reason: "A person is present at this Mac"
        )
    }

    private func allowDisplaySleep() {
        guard let activity = displaySleepActivity else { return }
        ProcessInfo.processInfo.endActivity(activity)
        displaySleepActivity = nil
    }

    private func refreshCameras() {
        let refreshed = CameraMonitor.availableCameras()
        if cameras != refreshed {
            cameras = refreshed
        }

        if !selectedCameraID.isEmpty,
           !refreshed.contains(where: { $0.id == selectedCameraID }) {
            selectedCameraID = ""
        }
    }

    private func refreshLoginItemStatus() {
        launchesAtLogin = SMAppService.mainApp.status == .enabled
        if SMAppService.mainApp.status == .requiresApproval {
            loginItemMessage = "Approve Presence in System Settings → Login Items."
        }
    }

    private func resetCameraRetry() {
        cameraRetryAfter = 0
        cameraFailureMessage = nil
    }

    private func reevaluate() {
        guard started else { return }
        tick()
    }

    private static var userIdleTime: TimeInterval {
        guard let anyInputEvent = CGEventType(rawValue: UInt32.max) else {
            return 0
        }
        return CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: anyInputEvent
        )
    }
}
