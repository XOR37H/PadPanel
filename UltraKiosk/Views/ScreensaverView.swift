import SwiftUI

struct ScreensaverView: View {
    @EnvironmentObject var kioskManager: KioskManager
    @EnvironmentObject var faceDetectionManager: FaceDetectionManager
    @EnvironmentObject var settings: SettingsManager
    @State private var currentTime = Date()
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
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
                    HStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: faceDetectionManager.faceDetected ? .green : .white))
                        Text(faceDetectionManager.faceDetected ? "Face detected! Waking up..." : "Face detection active...")
                            .foregroundColor(faceDetectionManager.faceDetected ? .green : .gray)
                            .font(.system(size: 16, weight: .medium))
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
