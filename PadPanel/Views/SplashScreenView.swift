import SwiftUI

struct SplashScreenView: View {
    @ObservedObject var settings: SettingsManager
    @ObservedObject var webServer = WebServerManager.shared
    let isPermanent: Bool
    
    @State private var pulseAnimation = false
    
    private var displayURL: String {
        if !webServer.serverURL.isEmpty {
            return webServer.serverURL
        }
        let ip = WebServerManager.getWiFiAddress() ?? "localhost"
        return "http://\(ip):\(settings.webServerPort)"
    }

    var body: some View {
        ZStack {
            // Dark grey background
            Color(red: 0.07, green: 0.08, blue: 0.10)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                Spacer()
                
                // Centered Logo & Branding
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
                                .stroke(Color.white.opacity(0.12), lineWidth: 1.5)
                        )
                        .shadow(color: Color.black.opacity(0.45), radius: 24, x: 0, y: 12)
                    
                    // Custom PadPanel Logo (double size, clean white)
                    PadPanelLogoView(size: CGSize(width: 185, height: 112), tintColor: .white)
                        .scaleEffect(pulseAnimation ? 1.03 : 0.98)
                        .animation(
                            Animation.easeInOut(duration: 2.0).repeatForever(autoreverses: true),
                            value: pulseAnimation
                        )
                }
                
                Spacer()
                
                // Footer / Configuration status
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
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.6)))
                        .scaleEffect(0.9)
                        .padding(.bottom, 48)
                }
            }
        }
        .onAppear {
            pulseAnimation = true
        }
    }
}
