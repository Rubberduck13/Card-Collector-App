//
//  CardScanView.swift
//  Card Grading Scanner
//
//  A clean, modern card-scanning screen:
//  - Live camera viewfinder
//  - Card-shaped bounding box overlay (guides + detected rect)
//  - Real-time "Centering Quality" percentage meter
//  - "Generate Pre-Grading Report" action button
//
//  Requires: AVFoundation, Vision
//  Add "Privacy - Camera Usage Description" to Info.plist.
//

import SwiftUI
import AVFoundation
import Vision
import Combine

// MARK: - Camera Session Manager

final class CameraSessionManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let visionQueue = DispatchQueue(label: "camera.vision.queue")

    /// Normalized (0...1) detected card rectangle in view coordinates, nil if none found.
    @Published var detectedCardRect: CGRect?
    /// 0...100 centering quality score.
    @Published var centeringQuality: Double = 0

    override init() {
        super.init()
        configureSession()
    }

    private func configureSession() {
        sessionQueue.async {
            self.session.beginConfiguration()
            self.session.sessionPreset = .hd1920x1080

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                return
            }
            self.session.addInput(input)

            self.videoOutput.setSampleBufferDelegate(self, queue: self.visionQueue)
            self.videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
            }
            self.videoOutput.connection(with: .video)?.videoRotationAngle = 90

            self.session.commitConfiguration()
        }
    }

    func start() {
        sessionQueue.async {
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    // MARK: Vision rectangle detection

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectRectanglesRequest { [weak self] request, _ in
            guard let self else { return }
            guard let results = request.results as? [VNRectangleObservation],
                  let best = results.max(by: { $0.confidence < $1.confidence }) else {
                DispatchQueue.main.async {
                    self.detectedCardRect = nil
                    self.centeringQuality = 0
                }
                return
            }
            // Vision's origin is bottom-left; flip for SwiftUI's top-left.
            let rect = CGRect(
                x: best.boundingBox.origin.x,
                y: 1 - best.boundingBox.origin.y - best.boundingBox.height,
                width: best.boundingBox.width,
                height: best.boundingBox.height
            )
            let quality = Self.centeringScore(for: rect)
            DispatchQueue.main.async {
                self.detectedCardRect = rect
                self.centeringQuality = quality
            }
        }
        request.minimumAspectRatio = 0.55
        request.maximumAspectRatio = 0.75
        request.minimumSize = 0.3
        request.minimumConfidence = 0.7

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right)
        try? handler.perform([request])
    }

    /// Scores how centered/symmetric the detected rect is within the frame (mimics a border-symmetry
    /// centering check similar to physical card grading standards).
    private static func centeringScore(for rect: CGRect) -> Double {
        let leftMargin = rect.minX
        let rightMargin = 1 - rect.maxX
        let topMargin = rect.minY
        let bottomMargin = 1 - rect.maxY

        let horizontalBalance = 1 - abs(leftMargin - rightMargin) / max(leftMargin + rightMargin, 0.0001)
        let verticalBalance = 1 - abs(topMargin - bottomMargin) / max(topMargin + bottomMargin, 0.0001)

        let score = ((horizontalBalance + verticalBalance) / 2) * 100
        return max(0, min(100, score))
    }
}

// MARK: - Camera Preview (UIKit bridge)

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

// MARK: - Main Scan Screen

struct CardScanView: View {
    @StateObject private var camera = CameraSessionManager()
    @State private var isGeneratingReport = false

    private let cardAspectRatio: CGFloat = 2.5 / 3.5 // standard trading card ratio

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Live camera feed
                CameraPreview(session: camera.session)
                    .ignoresSafeArea()

                // Dark scrim with card-shaped cutout
                cutoutOverlay(in: geo.size)

                // Detected rectangle highlight (if Vision finds a card)
                if let rect = camera.detectedCardRect {
                    detectedRectOverlay(rect: rect, in: geo.size)
                }

                VStack {
                    header

                    Spacer()

                    centeringMeter
                        .padding(.horizontal, 24)

                    guidanceText

                    generateReportButton
                        .padding(.horizontal, 24)
                        .padding(.bottom, 28)
                        .padding(.top, 12)
                }
            }
        }
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
        .statusBarHidden(false)
        .preferredColorScheme(.dark)
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("Scan Card")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            Image(systemName: "bolt.slash.fill")
                .foregroundStyle(.white.opacity(0.85))
                .padding(10)
                .background(.ultraThinMaterial, in: Circle())
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    // MARK: Card-shaped cutout guide

    private func cutoutOverlay(in size: CGSize) -> some View {
        let cardWidth = size.width * 0.78
        let cardHeight = cardWidth / cardAspectRatio
        let cornerRadius: CGFloat = 18

        return ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.55))
                .reverseMask {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .frame(width: cardWidth, height: cardHeight)
                }

            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(borderColor, lineWidth: 3)
                .frame(width: cardWidth, height: cardHeight)

            cornerBrackets(width: cardWidth, height: cardHeight, radius: cornerRadius)
        }
        .ignoresSafeArea()
    }

    private func cornerBrackets(width: CGFloat, height: CGFloat, radius: CGFloat) -> some View {
        let length: CGFloat = 26
        let lineWidth: CGFloat = 4
        let corners: [(CGPoint, CGPoint, CGPoint)] = [
            (CGPoint(x: -width/2, y: -height/2 + length), CGPoint(x: -width/2, y: -height/2), CGPoint(x: -width/2 + length, y: -height/2)),
            (CGPoint(x: width/2 - length, y: -height/2), CGPoint(x: width/2, y: -height/2), CGPoint(x: width/2, y: -height/2 + length)),
            (CGPoint(x: -width/2, y: height/2 - length), CGPoint(x: -width/2, y: height/2), CGPoint(x: -width/2 + length, y: height/2)),
            (CGPoint(x: width/2 - length, y: height/2), CGPoint(x: width/2, y: height/2), CGPoint(x: width/2, y: height/2 - length))
        ]
        return ZStack {
            ForEach(0..<corners.count, id: \.self) { i in
                Path { path in
                    path.move(to: corners[i].0)
                    path.addLine(to: corners[i].1)
                    path.addLine(to: corners[i].2)
                }
                .stroke(borderColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func detectedRectOverlay(rect: CGRect, in size: CGSize) -> some View {
        let frame = CGRect(
            x: rect.minX * size.width,
            y: rect.minY * size.height,
            width: rect.width * size.width,
            height: rect.height * size.height
        )
        return RoundedRectangle(cornerRadius: 10)
            .strokeBorder(borderColor.opacity(0.9), lineWidth: 2)
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            .animation(.easeOut(duration: 0.15), value: rect)
    }

    private var borderColor: Color {
        switch camera.centeringQuality {
        case 90...100: return .green
        case 70..<90: return .yellow
        default: return .orange
        }
    }

    // MARK: Centering meter

    private var centeringMeter: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Centering Quality")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
                Text("\(Int(camera.centeringQuality))%")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(borderColor)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.2), value: camera.centeringQuality)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.15))
                    Capsule()
                        .fill(borderColor)
                        .frame(width: geo.size.width * camera.centeringQuality / 100)
                        .animation(.easeOut(duration: 0.2), value: camera.centeringQuality)
                }
            }
            .frame(height: 8)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var guidanceText: some View {
        Text(guidanceMessage)
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.7))
            .padding(.top, 10)
            .padding(.horizontal, 32)
            .multilineTextAlignment(.center)
    }

    private var guidanceMessage: String {
        guard camera.detectedCardRect != nil else {
            return "Align the card within the frame"
        }
        if camera.centeringQuality >= 90 {
            return "Great centering — hold steady"
        } else if camera.centeringQuality >= 70 {
            return "Almost there — nudge the card toward center"
        } else {
            return "Card is off-center — adjust position"
        }
    }

    // MARK: Generate report button

    private var generateReportButton: some View {
        Button {
            isGeneratingReport = true
            // Hook up to your grading pipeline here.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                isGeneratingReport = false
            }
        } label: {
            HStack(spacing: 10) {
                if isGeneratingReport {
                    ProgressView()
                        .tint(.black)
                } else {
                    Image(systemName: "doc.text.magnifyingglass")
                }
                Text(isGeneratingReport ? "Generating..." : "Generate Pre-Grading Report")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(buttonBackground, in: RoundedRectangle(cornerRadius: 16))
        }
        .disabled(!isReadyToGenerate || isGeneratingReport)
        .animation(.easeOut(duration: 0.2), value: isReadyToGenerate)
    }

    private var isReadyToGenerate: Bool {
        camera.detectedCardRect != nil && camera.centeringQuality >= 70
    }

    private var buttonBackground: Color {
        isReadyToGenerate ? .white : .white.opacity(0.3)
    }
}

// MARK: - Reverse mask helper

private extension View {
    @ViewBuilder
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask(
            ZStack {
                Rectangle()
                mask()
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
        )
    }
}

// MARK: - Preview

#Preview {
    CardScanView()
}
