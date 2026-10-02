import SwiftUI

struct PhotoFrameScreensaverView: View {
    @EnvironmentObject var kioskManager: KioskManager
    @EnvironmentObject var faceDetectionManager: FaceDetectionManager
    @EnvironmentObject var settings: SettingsManager
    
    @State private var currentImage: UIImage? = nil
    @State private var isLoading: Bool = false
    @State private var loadFailed: Bool = false
    @State private var refreshTimer: Timer? = nil
    
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
            
            if let image = currentImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                    .id(image.hash)
            } else if settings.photoFrameURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 64, weight: .light))
                        .foregroundColor(.gray.opacity(0.6))
                    Text("Photo Frame Screensaver")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(.white)
                    Text("Configure Photo Frame Image URL in Settings > Display > Photo frame")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            } else if isLoading && currentImage == nil {
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    Text("Loading photo...")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
            } else if loadFailed && currentImage == nil {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.orange)
                    Text("Unable to load image from URL")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                    Text(settings.photoFrameURL)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.gray)
                        .lineLimit(2)
                        .padding(.horizontal, 40)
                }
            }
            
            // Motion/Face detection feedback overlay
            if faceDetectionManager.isDetecting && (settings.showDebugInfo || faceDetectionManager.faceDetected) {
                VStack {
                    Spacer()
                    HStack(spacing: 10) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: faceDetectionManager.faceDetected ? .green : .white))
                            .scaleEffect(0.8)
                        Text(statusText)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(faceDetectionManager.faceDetected ? .green : .white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.75))
                    .cornerRadius(20)
                    .padding(.bottom, 24)
                }
                .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            kioskManager.handleUserActivity()
        }
        .onAppear {
            faceDetectionManager.startDetection()
            loadImage()
            startTimer()
        }
        .onDisappear {
            stopTimer()
            faceDetectionManager.stopDetection()
        }
        .onReceive(kioskManager.$isDeepSleepActive) { inDeepSleep in
            if inDeepSleep {
                stopTimer()
                faceDetectionManager.stopDetection()
            }
        }
        .onChange(of: settings.photoFrameURL) { _ in
            loadImage()
        }
        .onChange(of: settings.photoFrameInterval) { _ in
            startTimer()
        }
    }
    
    private func startTimer() {
        stopTimer()
        let interval = max(5.0, settings.photoFrameInterval)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            DispatchQueue.main.async {
                self.loadImage()
            }
        }
    }
    
    private func stopTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    private func loadImage() {
        let rawURL = settings.photoFrameURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawURL.isEmpty else {
            self.currentImage = nil
            self.loadFailed = false
            return
        }
        
        // Append cache-busting timestamp
        let cacheBuster = "_cb=\(Int(Date().timeIntervalSince1970))"
        let finalURLString: String
        if rawURL.contains("?") {
            finalURLString = "\(rawURL)&\(cacheBuster)"
        } else {
            finalURLString = "\(rawURL)?\(cacheBuster)"
        }
        
        guard let url = URL(string: finalURLString) ?? URL(string: rawURL) else {
            self.loadFailed = true
            return
        }
        
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 15.0
        
        isLoading = true
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isLoading = false
                if let data = data, let image = UIImage(data: data) {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        self.currentImage = image
                        self.loadFailed = false
                    }
                } else if error != nil {
                    if self.currentImage == nil {
                        self.loadFailed = true
                    }
                }
            }
        }.resume()
    }
}
