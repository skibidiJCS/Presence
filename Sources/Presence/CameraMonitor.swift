@preconcurrency import AVFoundation
import Foundation
@preconcurrency import Vision

struct CameraChoice: Identifiable, Equatable {
    let id: String
    let name: String
}

final class CameraMonitor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.jiacai.presence.camera")
    private let analysisQueue = DispatchQueue(
        label: "com.jiacai.presence.vision",
        qos: .utility
    )
    private let callbackLock = NSLock()

    private var observationHandler: (@Sendable (Bool) -> Void)?
    private var errorHandler: (@Sendable (String) -> Void)?
    private var activeOutput: AVCaptureOutput?
    private var callbackGeneration = 0
    private var lastAnalysisTime: TimeInterval = 0
    private var lastBodyAnalysisTime: TimeInterval = 0
    private let analysisInterval: TimeInterval = 1
    private let bodyAnalysisInterval: TimeInterval = 3

    static func availableCameras() -> [CameraChoice] {
        captureDevices().map {
            CameraChoice(id: $0.uniqueID, name: $0.localizedName)
        }
    }

    func start(
        deviceID: String?,
        onObservation: @escaping @Sendable (Bool) -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) {
        let generation = installCallbacks(
            onObservation: onObservation,
            onError: onError
        )

        sessionQueue.async { [weak self] in
            self?.configureAndStart(
                deviceID: deviceID,
                generation: generation
            )
        }
    }

    func stop() {
        invalidateCallbacks()
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if session.isRunning {
                session.stopRunning()
            }
            session.beginConfiguration()
            session.inputs.forEach(session.removeInput)
            session.outputs.forEach(session.removeOutput)
            session.commitConfiguration()
        }
    }

    private func configureAndStart(
        deviceID: String?,
        generation: Int
    ) {
        guard isCurrentGeneration(generation) else { return }
        if session.isRunning {
            return
        }

        let cameras = Self.captureDevices()
        let selectedDevice = deviceID.flatMap { id in
            cameras.first(where: { $0.uniqueID == id })
        } ?? AVCaptureDevice.default(for: .video) ?? cameras.first

        guard let selectedDevice else {
            reportError("No camera was found.", generation: generation)
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: selectedDevice)
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String:
                    kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            ]
            output.setSampleBufferDelegate(self, queue: analysisQueue)

            session.beginConfiguration()
            session.sessionPreset = .low
            session.inputs.forEach(session.removeInput)
            session.outputs.forEach(session.removeOutput)

            guard session.canAddInput(input), session.canAddOutput(output) else {
                session.commitConfiguration()
                reportError(
                    "The selected camera could not be configured.",
                    generation: generation
                )
                return
            }

            session.addInput(input)
            session.addOutput(output)
            session.commitConfiguration()

            guard activate(output: output, generation: generation) else {
                return
            }
            lowerFrameRate(for: selectedDevice)
            session.startRunning()
        } catch {
            reportError(
                "Could not start \(selectedDevice.localizedName).",
                generation: generation
            )
        }
    }

    private static func captureDevices() -> [AVCaptureDevice] {
        var types: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .externalUnknown
        ]

        if #available(macOS 14.0, *) {
            types.append(.continuityCamera)
            types.append(.deskViewCamera)
        }

        return AVCaptureDevice.DiscoverySession(
            deviceTypes: types,
            mediaType: .video,
            position: .unspecified
        ).devices
    }

    private func lowerFrameRate(for device: AVCaptureDevice) {
        guard let slowestSupportedFPS = device.activeFormat
            .videoSupportedFrameRateRanges
            .map(\.minFrameRate)
            .min() else {
            return
        }
        let targetFPS = max(1, slowestSupportedFPS)

        guard (try? device.lockForConfiguration()) != nil else { return }
        let duration = CMTime(
            seconds: 1 / targetFPS,
            preferredTimescale: 600
        )
        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration
        device.unlockForConfiguration()
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastAnalysisTime >= analysisInterval,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        lastAnalysisTime = now

        do {
            let faceRequest = VNDetectFaceRectanglesRequest()
            let faceHandler = VNImageRequestHandler(
                cvPixelBuffer: pixelBuffer,
                orientation: .up,
                options: [:]
            )
            try faceHandler.perform([faceRequest])

            let faceDetected = (faceRequest.results ?? []).contains {
                $0.confidence >= 0.35 && $0.boundingBox.width >= 0.04
            }
            if faceDetected {
                reportObservation(true, from: output)
                return
            }

            guard now - lastBodyAnalysisTime >= bodyAnalysisInterval else {
                return
            }
            lastBodyAnalysisTime = now

            let personRequest = VNDetectHumanRectanglesRequest()
            personRequest.upperBodyOnly = true
            let personHandler = VNImageRequestHandler(
                cvPixelBuffer: pixelBuffer,
                orientation: .up,
                options: [:]
            )
            try personHandler.perform([personRequest])

            let personDetected = (personRequest.results ?? []).contains {
                $0.confidence >= 0.25 && $0.boundingBox.height >= 0.16
            }
            reportObservation(personDetected, from: output)
        } catch {
            reportError(
                "On-device presence detection failed.",
                from: output
            )
        }
    }

    private func installCallbacks(
        onObservation: @escaping @Sendable (Bool) -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) -> Int {
        callbackLock.lock()
        callbackGeneration += 1
        activeOutput = nil
        observationHandler = onObservation
        errorHandler = onError
        let generation = callbackGeneration
        callbackLock.unlock()
        return generation
    }

    private func invalidateCallbacks() {
        callbackLock.lock()
        callbackGeneration += 1
        activeOutput = nil
        callbackLock.unlock()
    }

    private func isCurrentGeneration(_ generation: Int) -> Bool {
        callbackLock.lock()
        let isCurrent = callbackGeneration == generation
        callbackLock.unlock()
        return isCurrent
    }

    private func activate(
        output: AVCaptureOutput,
        generation: Int
    ) -> Bool {
        callbackLock.lock()
        guard callbackGeneration == generation else {
            callbackLock.unlock()
            return false
        }
        activeOutput = output
        callbackLock.unlock()
        return true
    }

    private func reportObservation(
        _ detected: Bool,
        from output: AVCaptureOutput
    ) {
        callbackLock.lock()
        let handler = activeOutput === output ? observationHandler : nil
        callbackLock.unlock()
        handler?(detected)
    }

    private func reportError(
        _ message: String,
        from output: AVCaptureOutput
    ) {
        callbackLock.lock()
        let handler = activeOutput === output ? errorHandler : nil
        callbackLock.unlock()
        handler?(message)
    }

    private func reportError(_ message: String, generation: Int) {
        callbackLock.lock()
        let handler = callbackGeneration == generation ? errorHandler : nil
        callbackLock.unlock()
        handler?(message)
    }
}
