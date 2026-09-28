import SwiftUI

struct ScreensaverView: View {
    @EnvironmentObject var kioskManager: KioskManager
    @EnvironmentObject var faceDetectionManager: FaceDetectionManager
    @EnvironmentObject var settings: SettingsManager
    @State private var currentTime = Date()
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    private var isMotionMode: Bool {
        settings.wakeupMethod == "motion"
    }
    
    private var statusText: String {
        if faceDetectionManager.faceDetected {
            return isMotionMode ? "Motion detected! Waking up..." : "Face detected! Waking up..."
        } else {
            return isMotionMode ? "Motion detection active..." : "Face detection active..."
        }
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 30) {
                Text(currentTime, style: .time)
                    .font(.system(size: 80, weight: .thin, design: .default))
                    .foregroundColor(.white)
                
                Text(currentTime, style: .date)
                    .font(.system(size: 24, weight: .light))
                    .foregroundColor(.gray)
                
                if faceDetectionManager.isDetecting {
                    VStack(spacing: 8) {
                        HStack(spacing: 12) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: faceDetectionManager.faceDetected ? .green : .white))
                            Text(statusText)
                                .foregroundColor(faceDetectionManager.faceDetected ? .green : .gray)
                                .font(.system(size: 16, weight: .medium))
                        }
                        
                        // Live diagnostics: shows whether camera frames are arriving and motion score
                        HStack(spacing: 14) {
                            Text("Frames: \(faceDetectionManager.framesReceived)")
                                .font(.system(size: 13, weight: .regular, design: .monospaced))
                                .foregroundColor(.gray.opacity(0.85))
                            
                            if isMotionMode {
                                Text(String(format: "Motion: %.1f%% / %.0f%%", faceDetectionManager.motionScore * 100, settings.motionSensitivity * 100))
                                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                                    .foregroundColor(faceDetectionManager.motionScore >= settings.motionSensitivity ? .green : .gray.opacity(0.85))
                            }
                        }
                    }
                    .padding(.top, 40)
                    .animation(.easeInOut(duration: 0.2), value: faceDetectionManager.faceDetected)
                }
            }
        }
        .onReceive(timer) { input in
            currentTime = input
        }
        .onTapGesture {
            kioskManager.handleUserActivity()
        }
        .onAppear {
            faceDetectionManager.startDetection()
        }
        .onDisappear {
            faceDetectionManager.stopDetection()
        }
    }
}
