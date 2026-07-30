import AppKit
@preconcurrency import AVFoundation
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
        case .displayAlreadyAwake: "play.rectangle.fill"
        case .audioPlaying: "speaker.wave.2.fill"
        case .permissionDenied, .cameraUnavailable: "exclamationmark.triangle.fill"
        case .disabled: "eye.slash"
        case .paused: "pause.circle"
        case .displayAsleep: "moon.fill"
        case .waiting, .absent: "eye"
        }
    }

    private enum Keys {
        static let enabled = "presence.enabled"
        static let cameraID = "presence.cameraID"
        static let inactivity = "presence.inactivitySeconds"
        static let absenceGrace = "presence.absenceGraceSeconds"
    }

    private enum Timing {
        static let tick: TimeInterval = 1
        static let maximumProbe: TimeInterval = 5
        static let presenceRecheck: TimeInterval = 45
        static let playbackCheck: TimeInterval = 2
        static let cameraRetry: TimeInterval = 15
    }

    private let defaults = UserDefaults.standard
    private let cameraMonitor = CameraMonitor()
    private let systemPlaybackMonitor = SystemPlaybackMonitor()
    private let userActivityMonitor = UserActivityMonitor()
    private let displaySleepController = DisplaySleepController()
    private var policy = PresencePolicy()
    private var probeSchedule = CameraProbeSchedule()
    private var timer: Timer?
    private var cameraDeviceObservers: [NSObjectProtocol] = []
    private var started = false
    private var displayIsAsleep = false
    private var nextPlaybackCheckAt: TimeInterval = 0
    private var playbackActivity: PlaybackActivity = .none
    private var cameraRetryAfter: TimeInterval = 0
    private var cameraFailureMessage: String?
    private var cameraGeneration = 0

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
        startCameraDeviceMonitoring()
        refreshLoginItemStatus()
        requestCameraAccessIfNeeded()

        startTimer()

        userActivityMonitor.start { [weak self] in
            self?.handleInteraction()
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
        stopTimer()
        userActivityMonitor.stop()
        cameraDeviceObservers.forEach(NotificationCenter.default.removeObserver)
        cameraDeviceObservers.removeAll()
        resetMonitoringCycle()
        displaySleepController.allow()
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
        userActivityMonitor.recordActivity()
        handleInteraction()
    }

    private func handleInteraction() {
        resetMonitoringCycle()
        displaySleepController.allow()
        resetCameraRetry()
        reevaluate()
    }

    @objc private func screenDidSleep() {
        displayIsAsleep = true
        stopTimer()
        suspendMonitoring(with: .displayAsleep)
    }

    @objc private func screenDidWake() {
        displayIsAsleep = false
        startTimer()
        recordInteraction()
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

        guard isEnabled else {
            suspendMonitoring(with: .disabled)
            return
        }

        guard !isPaused else {
            suspendMonitoring(with: .paused)
            return
        }

        guard !displayIsAsleep else {
            suspendMonitoring(with: .displayAsleep)
            return
        }

        refreshPlaybackActivityIfNeeded(at: now)
        switch playbackActivity {
        case .audio:
            userActivityMonitor.recordActivity(at: now)
            suspendMonitoring(with: .audioPlaying, keepDisplayAwake: true)
            return
        case .display:
            userActivityMonitor.recordActivity(at: now)
            suspendMonitoring(with: .displayAlreadyAwake)
            return
        case .none:
            break
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted:
            suspendMonitoring(with: .permissionDenied)
            return
        case .notDetermined:
            suspendMonitoring(with: .waiting(secondsRemaining: inactivitySeconds))
            return
        case .authorized:
            break
        @unknown default:
            suspendMonitoring(
                with: .cameraUnavailable("Camera permission could not be determined.")
            )
            return
        }

        let idleTime = userActivityMonitor.idleTime(at: now)
        guard idleTime >= inactivitySeconds else {
            suspendMonitoring(
                with: .waiting(secondsRemaining: inactivitySeconds - idleTime)
            )
            return
        }

        if isCameraActive,
           probeSchedule.probeTimedOut(
               at: now,
               maximumDuration: Timing.maximumProbe
           ) {
            policy.observe(personDetected: false, at: now)
            stopCamera()
            probeSchedule.markProbeMissed(
                at: now,
                recheckInterval: max(5, absenceGraceSeconds - Timing.maximumProbe)
            )
        }

        applyPolicyDecision(at: now)

        guard !isCameraActive else { return }
        if now < cameraRetryAfter {
            status = .cameraUnavailable(
                cameraFailureMessage
                    ?? "Camera is temporarily unavailable. Display sleep is prevented while Presence retries."
            )
            displaySleepController.prevent()
            return
        }

        if probeSchedule.shouldStartProbe(at: now) {
            startCamera(at: now)
        }
    }

    private func startCamera(at time: TimeInterval) {
        guard !displayIsAsleep else { return }

        guard !cameras.isEmpty else {
            status = .cameraUnavailable("No camera was found.")
            displaySleepController.allow()
            return
        }

        resetCameraRetry()
        cameraGeneration += 1
        let generation = cameraGeneration
        probeSchedule.markProbeStarted(at: time)
        isCameraActive = true
        displaySleepController.prevent()
        status = .checking

        let deviceID = selectedCameraID.isEmpty ? nil : selectedCameraID
        cameraMonitor.start(
            deviceID: deviceID,
            onObservation: { [weak self] detected in
                Task { @MainActor in
                    guard let self,
                          self.isCameraActive,
                          self.cameraGeneration == generation,
                          detected else {
                        return
                    }
                    let now = ProcessInfo.processInfo.systemUptime
                    self.policy.observe(personDetected: true, at: now)
                    self.probeSchedule.markPresenceDetected(
                        at: now,
                        recheckInterval: Timing.presenceRecheck
                    )
                    self.stopCamera()
                    self.applyPolicyDecision(at: now)
                }
            },
            onError: { [weak self] message in
                Task { @MainActor in
                    guard let self,
                          self.isCameraActive,
                          self.cameraGeneration == generation else {
                        return
                    }
                    let now = ProcessInfo.processInfo.systemUptime
                    self.stopCamera()
                    self.probeSchedule.markProbeMissed(
                        at: now,
                        recheckInterval: Timing.cameraRetry
                    )
                    self.cameraFailureMessage =
                        "\(message) Display sleep is prevented while Presence retries."
                    self.cameraRetryAfter = now + Timing.cameraRetry
                    self.status = .cameraUnavailable(self.cameraFailureMessage ?? message)
                    self.displaySleepController.prevent()
                }
            }
        )
    }

    private func stopCamera() {
        guard isCameraActive else { return }
        cameraGeneration += 1
        cameraMonitor.stop()
        isCameraActive = false
    }

    private func restartCameraIfNeeded() {
        guard isCameraActive else { return }
        stopCamera()
        probeSchedule.reset()
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
            displaySleepController.prevent()
        } else {
            displaySleepController.allow()
        }
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

    private func resetMonitoringCycle() {
        stopCamera()
        policy.reset()
        probeSchedule.reset()
    }

    private func suspendMonitoring(
        with status: MonitoringStatus,
        keepDisplayAwake: Bool = false
    ) {
        self.status = status
        resetMonitoringCycle()
        if keepDisplayAwake {
            displaySleepController.prevent()
        } else {
            displaySleepController.allow()
        }
        resetCameraRetry()
    }

    private func refreshPlaybackActivityIfNeeded(at time: TimeInterval) {
        guard time >= nextPlaybackCheckAt else { return }
        if let activity = systemPlaybackMonitor.activity() {
            if playbackActivity != .none && activity == .none {
                userActivityMonitor.recordActivity(at: time)
            }
            playbackActivity = activity
        }
        nextPlaybackCheckAt = time + Timing.playbackCheck
    }

    private func reevaluate() {
        guard started else { return }
        tick()
    }

    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(
            withTimeInterval: Timing.tick,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func startCameraDeviceMonitoring() {
        let center = NotificationCenter.default
        let notifications = [
            AVCaptureDevice.wasConnectedNotification,
            AVCaptureDevice.wasDisconnectedNotification
        ]
        cameraDeviceObservers = notifications.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshCameras()
                }
            }
        }
    }
}
