import SwiftUI
import AVFoundation
import Vision
import Combine

class FaceDetectionManager: NSObject, ObservableObject {
    @Published var faceDetected = false
    @Published var isDetecting = false
    
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue", qos: .userInitiated)
    
    // Frame rate limiting properties
    private var lastDetectionTime: CFTimeInterval = 0
    private var detectionInterval: CFTimeInterval = SettingsManager.shared.faceDetectionInterval
    private var lastSuccessfulOrientation: CGImagePropertyOrientation = .leftMirrored
    private var isProcessing = false
    
    override init() {
        super.init()
        setupCamera()
    }
    
    func updateDetectionInterval(_ newInterval: CFTimeInterval) {
        sessionQueue.async { [weak self] in
            self?.detectionInterval = newInterval
            self?.lastDetectionTime = 0
        }
    }
    
    func reinitialize(withInterval newInterval: CFTimeInterval) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            let wasDetecting = self.isDetecting
            self.captureSession?.stopRunning()
            self.captureSession = nil
            self.previewLayer = nil
            self.detectionInterval = newInterval
            self.lastDetectionTime = 0
            self.configureCaptureSession()
            if wasDetecting {
                self.captureSession?.startRunning()
                DispatchQueue.main.async {
                    self.isDetecting = true
                }
            }
        }
    }
    
    func setupCamera() {
        sessionQueue.async { [weak self] in
            self?.configureCaptureSession()
        }
    }
    
    private func configureCaptureSession() {
        let session = AVCaptureSession()
        session.sessionPreset = .medium
        
        guard let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: frontCamera) else {
            AppLogger.app.warningConditional("Front camera input not available during configureCaptureSession.")
            return
        }
        
        if session.canAddInput(input) {
            session.addInput(input)
        }
        
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
        
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer?.videoGravity = .resizeAspectFill
        
        self.captureSession = session
        AppLogger.app.infoConditional("Camera capture session successfully configured.")
    }
    
    func startDetection() {
        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        switch authStatus {
        case .authorized:
            startDetectionInternal()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.startDetectionInternal()
                }
            }
        default:
            AppLogger.app.warningConditional("Camera access not authorized for face detection.")
        }
    }
    
    private func startDetectionInternal() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            if self.captureSession == nil || self.captureSession?.inputs.isEmpty == true {
                self.configureCaptureSession()
            }
            
            if self.captureSession?.isRunning == false {
                self.captureSession?.startRunning()
            }
            
            DispatchQueue.main.async {
                self.faceDetected = false
                self.isDetecting = true
            }
        }
    }
    
    func stopDetection() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.captureSession?.isRunning == true {
                self.captureSession?.stopRunning()
            }
            DispatchQueue.main.async {
                self.isDetecting = false
                self.faceDetected = false
            }
        }
    }
    
    func getPreviewLayer() -> AVCaptureVideoPreviewLayer? {
        return previewLayer
    }
    
    private func shouldProcessFrame() -> Bool {
        let currentTime = CACurrentMediaTime()
        if currentTime - lastDetectionTime >= detectionInterval {
            lastDetectionTime = currentTime
            return true
        }
        return false
    }
    
    private func detectFace(in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> Bool {
        var faceFound = false
        let request = VNDetectFaceRectanglesRequest { req, _ in
            if let results = req.results as? [VNFaceObservation], !results.isEmpty {
                faceFound = true
            }
        }
        // Revision 2 is fast, lightweight, and fully supported on iOS 14+ / iOS 15 on A8X
        request.revision = VNDetectFaceRectanglesRequestRevision2
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        try? handler.perform([request])
        return faceFound
    }
    
    private func processFaceDetection(pixelBuffer: CVPixelBuffer) {
        guard !isProcessing, !faceDetected else { return }
        isProcessing = true
        defer { isProcessing = false }
        
        // Prioritize last successful orientation first, then candidate orientations for iPad landscape/portrait
        var orientations: [CGImagePropertyOrientation] = [
            lastSuccessfulOrientation,
            .leftMirrored,
            .rightMirrored,
            .upMirrored,
            .downMirrored,
            .up,
            .left,
            .right,
            .down
        ]
        
        // Deduplicate while preserving priority order
        var seen = Set<UInt32>()
        orientations = orientations.filter { seen.insert($0.rawValue).inserted }
        
        for orientation in orientations {
            if detectFace(in: pixelBuffer, orientation: orientation) {
                lastSuccessfulOrientation = orientation
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, !self.faceDetected else { return }
                    self.faceDetected = true
                    AppLogger.app.infoConditional("Face detected with orientation \(orientation.rawValue) — waking kiosk!")
                }
                return
            }
        }
    }
}

extension FaceDetectionManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isDetecting, !faceDetected else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        if shouldProcessFrame() {
            processFaceDetection(pixelBuffer: pixelBuffer)
        }
    }
}
