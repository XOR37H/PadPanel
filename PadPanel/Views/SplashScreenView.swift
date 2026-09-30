import SwiftUI
import Combine
import Foundation

struct SplashScreenView: View {
    @ObservedObject var settings: SettingsManager
    let isPermanent: Bool
    var onDismiss: (() -> Void)? = nil
    
    @State private var pulseAnimation = false
    @State private var logoTapCount = 0
    @State private var showingResetAlert = false
    @State private var resetSuccessNotice = false
    @State private var remainingSeconds = 10
    @State private var isCountdownPaused = false
    @State private var timerActive = true

    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    
    private var displayURL: String {
        let serverURL = WebServerManager.shared.serverURL
        if !serverURL.isEmpty {
            return serverURL
        }
        let ip = WebServerManager.getWiFiAddress() ?? "localhost"
        return "http://\(ip):\(settings.webServerPort)"
    }

    var body: some View {
        ZStack {
            // Dark background matching kiosk aesthetic
            Color(red: 0.06, green: 0.07, blue: 0.09)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                Spacer()
                
                // Centered Logo & Branding with 5-tap physical reset detector
                VStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.14, green: 0.17, blue: 0.22),
                                        Color(red: 0.09, green: 0.11, blue: 0.15)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 230, height: 190)
                            .overlay(
                                RoundedRectangle(cornerRadius: 32, style: .continuous)
                                    .stroke(
                                        logoTapCount > 0 ? Color.blue.opacity(0.4) : Color.white.opacity(0.12),
                                        lineWidth: 1.5
                                    )
                            )
                            .shadow(color: Color.black.opacity(0.45), radius: 24, x: 0, y: 12)
                        
                        // Custom PadPanel Logo
                        PadPanelLogoView(size: CGSize(width: 185, height: 112), tintColor: .white)
                            .scaleEffect(pulseAnimation ? 1.03 : 0.98)
                            .animation(
                                Animation.easeInOut(duration: 2.0).repeatForever(autoreverses: true),
                                value: pulseAnimation
                            )
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        handleLogoTap()
                    }
                    
                    if logoTapCount > 0 && logoTapCount < 5 {
                        Text("Tap \(5 - logoTapCount) more time\(5 - logoTapCount == 1 ? "" : "s") to reset password")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.blue.opacity(0.85))
                            .transition(.opacity)
                    }
                }
                
                Spacer()
                
                // Footer / Configuration & Loading status
                if isPermanent {
                    VStack(spacing: 10) {
                        Text("No dashboard URL configured")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                        
                        VStack(spacing: 4) {
                            Text("Configure via Remote WebUI:")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.5))
                            
                            Text(displayURL)
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .foregroundColor(Color(red: 0.35, green: 0.65, blue: 1.0))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(8)
                        
                        Text("or tap top-right corner 3 times to open on-device Settings")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                            .padding(.top, 4)
                    }
                    .padding(.bottom, 36)
                    .transition(.opacity)
                } else {
                    VStack(spacing: 12) {
                        if resetSuccessNotice {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("WebUI password has been reset to default.")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.green.opacity(0.15))
                            .cornerRadius(8)
                        } else {
                            // Loading indicator and status
                            VStack(spacing: 8) {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.7)))
                                        .scaleEffect(0.8)
                                    Text("Loading dashboard...")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white.opacity(0.85))
                                }
                                
                                Text("Starting kiosk services (\(remainingSeconds)s)")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.45))
                            }
                        }
                    }
                    .padding(.bottom, 48)
                }
            }
        }
        .onAppear {
            pulseAnimation = true
        }
        .onReceive(timer) { _ in
            guard !self.isPermanent && self.timerActive && !self.isCountdownPaused else { return }
            if self.remainingSeconds > 1 {
                self.remainingSeconds -= 1
            } else {
                self.timerActive = false
                self.onDismiss?()
            }
        }
        .alert(isPresented: $showingResetAlert) {
            Alert(
                title: Text("Reset WebUI Password?"),
                message: Text("This will clear the WebUI password and set access back to open/default."),
                primaryButton: .destructive(Text("Reset Password")) {
                    self.settings.webServerPassword = ""
                    self.settings.requireDeviceAuth = false
                    self.settings.saveSettings()
                    WebServerManager.shared.clearAllSessions()
                    self.resetSuccessNotice = true
                    self.logoTapCount = 0
                    
                    // Allow 1.5 seconds for user to see confirmation before entering dashboard
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        self.onDismiss?()
                    }
                },
                secondaryButton: .cancel(Text("Cancel")) {
                    self.logoTapCount = 0
                    self.isCountdownPaused = false
                    if self.remainingSeconds <= 1 {
                        self.onDismiss?()
                    }
                }
            )
        }
    }
    
    private func handleLogoTap() {
        logoTapCount += 1
        if logoTapCount >= 5 {
            isCountdownPaused = true
            showingResetAlert = true
        }
    }
}
