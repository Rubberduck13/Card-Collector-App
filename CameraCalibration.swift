import Foundation
import AVFoundation
import CoreMedia
import CoreMotion

public enum CameraCalibrationAlert: Equatable {
    case ready
    case insufficientLighting
    case unstableMotion
    case focusNotLocked
}

public struct CameraCalibrationStatus {
    public let ambientLuxEstimate: Float?
    public let isFocusLocked: Bool
    public let isMotionStable: Bool
    public let alert: CameraCalibrationAlert
}

@MainActor
public final class CameraCalibration: NSObject {

    // MARK: - Configuration

    /// Approximate threshold. Tune for your camera pipeline.
    public var minimumLuxEstimate: Float = 80.0

    /// Maximum allowed device motion (g).
    public var maximumAccelerationMagnitude: Double = 0.04

    // MARK: - Public State

    public private(set) var ambientLuxEstimate: Float?
    public private(set) var isFocusLocked = false
    public private(set) var isMotionStable = true

    // MARK: - Private

    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let motionManager = CMMotionManager()

    private let outputQueue = DispatchQueue(
        label: "CameraCalibration.VideoQueue"
    )

    private var videoDevice: AVCaptureDevice?

    // MARK: - Lifecycle

    public override init() {
        super.init()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        stopMonitoring()
    }

    // MARK: - Monitoring

    public func startMonitoring() throws {

        guard !captureSession.isRunning else { return }

        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) else {
            throw NSError(
                domain: "CameraCalibration",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Back camera unavailable."]
            )
        }

        videoDevice = device

        let input = try AVCaptureDeviceInput(device: device)

        captureSession.beginConfiguration()

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: outputQueue)

        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        captureSession.commitConfiguration()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(subjectAreaChanged),
            name: AVCaptureDevice.subjectAreaDidChangeNotification,
            object: device
        )

        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0

        if motionManager.isDeviceMotionAvailable {
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
                guard let self, let motion else { return }

                let a = motion.userAcceleration

                let magnitude = sqrt(
                    a.x * a.x +
                    a.y * a.y +
                    a.z * a.z
                )

                self.isMotionStable =
                    magnitude <= self.maximumAccelerationMagnitude
            }
        }

        captureSession.startRunning()
    }

    public func stopMonitoring() {

        if captureSession.isRunning {
            captureSession.stopRunning()
        }

        motionManager.stopDeviceMotionUpdates()
    }

    // MARK: - Validation

    public func calibrationStatus() -> CameraCalibrationStatus {

        let alert: CameraCalibrationAlert

        if let lux = ambientLuxEstimate,
           lux < minimumLuxEstimate {
            alert = .insufficientLighting
        } else if !isMotionStable {
            alert = .unstableMotion
        } else if !isFocusLocked {
            alert = .focusNotLocked
        } else {
            alert = .ready
        }

        return CameraCalibrationStatus(
            ambientLuxEstimate: ambientLuxEstimate,
            isFocusLocked: isFocusLocked,
            isMotionStable: isMotionStable,
            alert: alert
        )
    }

    // MARK: - Focus

    @objc
    private func subjectAreaChanged() {
        updateFocusState()
    }

    private func updateFocusState() {

        guard let device = videoDevice else {
            isFocusLocked = false
            return
        }

        switch device.focusMode {
        case .locked:
            isFocusLocked = true

        case .continuousAutoFocus:
            isFocusLocked = !device.isAdjustingFocus

        case .autoFocus:
            isFocusLocked = !device.isAdjustingFocus

        @unknown default:
            isFocusLocked = false
        }
    }

    // MARK: - Exposure → Approximate Lux

    private func updateExposureEstimate(from device: AVCaptureDevice) {

        let duration = CMTimeGetSeconds(device.exposureDuration)

        guard duration > 0 else { return }

        let iso = Double(device.iso)

        // Approximate EV100
        let ev100 = log2((100.0 * duration) / iso)

        // Approximate lux estimate.
        let lux = Float(pow(2.0, -ev100) * 2.5)

        ambientLuxEstimate = lux
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraCalibration: AVCaptureVideoDataOutputSampleBufferDelegate {

    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {

        guard let device = videoDevice else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            self.updateExposureEstimate(from: device)
            self.updateFocusState()
        }
    }
}
