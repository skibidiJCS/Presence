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

    private var observationHandler: (@Sendable (Bool) -> Void)?
    private var errorHandler: (@Sendable (String) -> Void)?
    private var lastAnalysisTime: TimeInterval = 0
    private var lastBodyAnalysisTime: TimeInterval = 0
    private let analysisInterval: TimeInterval = 1
    private let bodyAnalysisInterval: TimeInterval = 3

    static func availableCameras() -> [CameraChoice] {
        var deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .externalUnknown
        ]

        if #available(macOS 14.0, *) {
            deviceTypes.append(.continuityCamera)
            deviceTypes.append(.deskViewCamera)
        }

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: .unspecified
        )

        return discovery.devices.map {
            CameraChoice(id: $0.uniqueID, name: $0.localizedName)
        }
    }

    func start(
        deviceID: String?,
        onObservation: @escaping @Sendable (Bool) -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) {
        observationHandler = onObservation
        errorHandler = onError

        sessionQueue.async { [weak self] in
            self?.configureAndStart(deviceID: deviceID)
        }
    }

    func stop() {
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

    private func configureAndStart(deviceID: String?) {
        if session.isRunning {
            return
        }

        let cameras = Self.captureDevices()
        let selectedDevice = deviceID.flatMap { id in
            cameras.first(where: { $0.uniqueID == id })
        } ?? AVCaptureDevice.default(for: .video) ?? cameras.first

        guard let selectedDevice else {
            errorHandler?("No camera was found.")
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
                errorHandler?("The selected camera could not be configured.")
                return
            }

            session.addInput(input)
            session.addOutput(output)
            session.commitConfiguration()

            lowerFrameRate(for: selectedDevice)
            session.startRunning()
        } catch {
            errorHandler?("Could not start \(selectedDevice.localizedName).")
        }
    }

    private static func captureDevices() -> [AVCaptureDevice] {
        var deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .externalUnknown
        ]

        if #available(macOS 14.0, *) {
            deviceTypes.append(.continuityCamera)
            deviceTypes.append(.deskViewCamera)
        }

        return AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
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

        do {
            try device.lockForConfiguration()
            let duration = CMTime(
                seconds: 1 / targetFPS,
                preferredTimescale: 600
            )
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            device.unlockForConfiguration()
        } catch {
        }
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
                observationHandler?(true)
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
            observationHandler?(personDetected)
        } catch {
            errorHandler?("On-device presence detection failed.")
        }
    }
}
