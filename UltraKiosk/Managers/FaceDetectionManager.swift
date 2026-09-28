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
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    
    // Frame rate limiting properties
    private var lastDetectionTime: CFTimeInterval = 0
    private var detectionInterval: CFTimeInterval = SettingsManager.shared.faceDetectionInterval
    private var pendingPixelBuffer: CVPixelBuffer?
    
    // Reusable Vision request for performance optimization
    private lazy var faceDetectionRequest: VNDetectFaceRectanglesRequest = {
        let request = VNDetectFaceRectanglesRequest { [weak self] request, error in
            guard let self = self else { return }
            
            if let error = error {
                AppLogger.app.warningConditional("Face detection error: \(error.localizedDescription)")
                return
            }
            
            guard let results = request.results as? [VNFaceObservation] else { return }
            
            DispatchQueue.main.async {
                let hasFaces = !results.isEmpty
                if hasFaces != self.faceDetected {
                    self.faceDetected = hasFaces
                    if hasFaces {
                        AppLogger.app.infoConditional("Face detected! Waking up kiosk.")
                    }
                }
            }
        }
        
        return request
    }()
    
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
    
    private func currentVideoOrientation() -> AVCaptureVideoOrientation {
        if let windowScene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            switch windowScene.interfaceOrientation {
            case .landscapeLeft:
                return .landscapeLeft
            case .landscapeRight:
                return .landscapeRight
            case .portraitUpsideDown:
                return .portraitUpsideDown
            default:
                return .landscapeRight
            }
        }
        return .landscapeRight
    }
    
    private func configureCaptureSession() {
        captureSession = AVCaptureSession()
        captureSession?.sessionPreset = .medium
        
        guard let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: frontCamera),
              let captureSession = captureSession else {
            return
        }
        
        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }
        
        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }
        
        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = currentVideoOrientation()
            }
        }
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer?.videoGravity = .resizeAspectFill
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
            
            // Reconfigure session if needed (e.g. if permissions were granted after init)
            if self.captureSession == nil || self.captureSession?.inputs.isEmpty == true {
                self.configureCaptureSession()
            }
            
            // Re-sync orientation with current UI landscape orientation
            DispatchQueue.main.async {
                let orientation = self.currentVideoOrientation()
                self.sessionQueue.async {
                    if let connection = self.videoOutput.connection(with: .video), connection.isVideoOrientationSupported {
                        connection.videoOrientation = orientation
                    }
                }
            }
            
            if self.captureSession?.isRunning == false {
                self.captureSession?.startRunning()
            }
            
            DispatchQueue.main.async {
                self.isDetecting = true
            }
        }
    }
    
    func stopDetection() {
        sessionQueue.async { [weak self] in
            self?.captureSession?.stopRunning()
            DispatchQueue.main.async {
                self?.isDetecting = false
                self?.faceDetected = false
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
    
    private func processFaceDetection(pixelBuffer: CVPixelBuffer) {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        
        do {
            try handler.perform([faceDetectionRequest])
        } catch {
            AppLogger.app.warningConditional("Failed to perform face detection: \(error.localizedDescription)")
        }
    }
}

extension FaceDetectionManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        pendingPixelBuffer = pixelBuffer
        
        if shouldProcessFrame() {
            processFaceDetection(pixelBuffer: pixelBuffer)
        }
    }
}
