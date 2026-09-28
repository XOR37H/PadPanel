import SwiftUI
import AVFoundation
import Vision
import Combine

class FaceDetectionManager: NSObject, ObservableObject {
    @Published var faceDetected = false
    @Published var isDetecting = false
    @Published var motionScore: Double = 0.0
    @Published var framesReceived: Int = 0
    @Published var cameraStatusText: String = "Initializing..."
    
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue", qos: .userInitiated)
    
    // Frame rate limiting properties for face detection
    private var lastDetectionTime: CFTimeInterval = 0
    private var detectionInterval: CFTimeInterval = SettingsManager.shared.faceDetectionInterval
    private var lastSuccessfulOrientation: CGImagePropertyOrientation = .leftMirrored
    private var isProcessing = false
    
    // Motion detection properties
    private var previousGridSample: [UInt8] = []
    private let gridCols = 16
    private let gridRows = 12
    
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
            self.previousGridSample.removeAll()
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
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        
        // 640x480 (VGA) is universally supported by the front camera on all iPads including iPad Air 2
        if session.canSetSessionPreset(.vga640x480) {
            session.sessionPreset = .vga640x480
        } else if session.canSetSessionPreset(.medium) {
            session.sessionPreset = .medium
        }
        
        guard let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            let errorMsg = "No front camera device found"
            AppLogger.app.warningConditional(errorMsg)
            DispatchQueue.main.async { self.cameraStatusText = errorMsg }
            return
        }
        
        guard let input = try? AVCaptureDeviceInput(device: frontCamera) else {
            let errorMsg = "Cannot create AVCaptureDeviceInput for front camera"
            AppLogger.app.warningConditional(errorMsg)
            DispatchQueue.main.async { self.cameraStatusText = errorMsg }
            return
        }
        
        guard session.canAddInput(input) else {
            let errorMsg = "Cannot add camera input to session"
            AppLogger.app.warningConditional(errorMsg)
            DispatchQueue.main.async { self.cameraStatusText = errorMsg }
            return
        }
        session.addInput(input)
        
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        
        guard session.canAddOutput(videoOutput) else {
            let errorMsg = "Cannot add videoOutput to session"
            AppLogger.app.warningConditional(errorMsg)
            DispatchQueue.main.async { self.cameraStatusText = errorMsg }
            return
        }
        session.addOutput(videoOutput)
        
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer?.videoGravity = .resizeAspectFill
        
        self.captureSession = session
        AppLogger.app.infoConditional("Camera capture session successfully configured.")
        DispatchQueue.main.async {
            self.cameraStatusText = "Session configured"
        }
    }
    
    func startDetection() {
        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        switch authStatus {
        case .authorized:
            startDetectionInternal()
        case .notDetermined:
            DispatchQueue.main.async { self.cameraStatusText = "Requesting permission..." }
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.startDetectionInternal()
                } else {
                    DispatchQueue.main.async { self?.cameraStatusText = "Camera permission denied" }
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.async { self.cameraStatusText = "Camera access denied in Settings" }
            AppLogger.app.warningConditional("Camera access not authorized for face/motion detection.")
        @unknown default:
            break
        }
    }
    
    private func startDetectionInternal() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            if self.captureSession == nil || self.captureSession?.inputs.isEmpty == true {
                self.configureCaptureSession()
            }
            
            self.previousGridSample.removeAll()
            
            let isRunningBefore = self.captureSession?.isRunning ?? false
            if !isRunningBefore {
                self.captureSession?.startRunning()
            }
            let isRunningAfter = self.captureSession?.isRunning ?? false
            
            DispatchQueue.main.async {
                self.faceDetected = false
                self.framesReceived = 0
                self.motionScore = 0.0
                self.isDetecting = true
                self.cameraStatusText = isRunningAfter ? "Camera running" : "Camera failed to start"
            }
        }
    }
    
    func stopDetection() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.captureSession?.isRunning == true {
                self.captureSession?.stopRunning()
            }
            self.previousGridSample.removeAll()
            DispatchQueue.main.async {
                self.isDetecting = false
                self.faceDetected = false
                self.motionScore = 0.0
                self.cameraStatusText = "Camera stopped"
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
    
    // MARK: - Motion Detection
    private func processMotionDetection(pixelBuffer: CVPixelBuffer) {
        guard !isProcessing, !faceDetected else { return }
        isProcessing = true
        defer { isProcessing = false }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)
        
        var currentSample = [UInt8]()
        currentSample.reserveCapacity(gridCols * gridRows)
        
        for row in 0..<gridRows {
            let y = (height * (row + 1)) / (gridRows + 1)
            let rowStart = y * bytesPerRow
            for col in 0..<gridCols {
                let x = (width * (col + 1)) / (gridCols + 1)
                let pixelOffset = rowStart + (x * 4)
                let b = UInt32(buffer[pixelOffset])
                let g = UInt32(buffer[pixelOffset + 1])
                let r = UInt32(buffer[pixelOffset + 2])
                let gray = UInt8((r + 2 * g + b) / 4)
                currentSample.append(gray)
            }
        }
        
        guard !previousGridSample.isEmpty, previousGridSample.count == currentSample.count else {
            previousGridSample = currentSample
            return
        }
        
        var totalDiff: Double = 0.0
        for i in 0..<currentSample.count {
            totalDiff += Double(abs(Int(currentSample[i]) - Int(previousGridSample[i])))
        }
        previousGridSample = currentSample
        
        let avgChange = (totalDiff / Double(currentSample.count)) / 255.0
        let threshold = SettingsManager.shared.motionSensitivity
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.motionScore = avgChange
            if avgChange >= threshold && !self.faceDetected {
                self.faceDetected = true
                AppLogger.app.infoConditional(String(format: "Motion detected (%.1f%% >= %.0f%%) — waking kiosk!", avgChange * 100, threshold * 100))
            }
        }
    }
    
    // MARK: - Face Detection
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
        
        DispatchQueue.main.async { [weak self] in
            self?.framesReceived += 1
        }
        
        if SettingsManager.shared.wakeupMethod == "motion" {
            processMotionDetection(pixelBuffer: pixelBuffer)
        } else {
            if shouldProcessFrame() {
                processFaceDetection(pixelBuffer: pixelBuffer)
            }
        }
    }
}
