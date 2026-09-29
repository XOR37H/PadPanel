import AVFoundation
import SwiftUI
import Vision
import WebKit

struct ContentView: View {
    @StateObject private var kioskManager = KioskManager()
    @StateObject private var audioManager = AudioManager()
    @StateObject private var faceDetectionManager = FaceDetectionManager()
    @StateObject private var mqttManager = MQTTManager()
    @StateObject private var settings = SettingsManager.shared
    @StateObject private var brightnessManager = BrightnessManager()
    @StateObject private var slideshowManager = SlideshowManager()
    @StateObject private var webServerManager = WebServerManager.shared

    @State private var showingSettings = false

    var body: some View {
        ZStack {
            // All WebViews are always resident in memory; visibility is controlled via
            // opacity so WKWebView instances stay alive and sessions are preserved.
            let slots: [String?] = {
                let urls = settings.effectiveURLs
                return urls.isEmpty ? [nil] : urls.map { Optional($0) }
            }()

            ForEach(Array(slots.enumerated()), id: \.offset) { index, urlOrNil in
                KioskWebView(url: urlOrNil)
                    .environmentObject(kioskManager)
                    .opacity(webViewOpacity(for: index))
                    .animation(.easeInOut(duration: 0.8), value: slideshowManager.currentIndex)
                    .animation(.easeInOut(duration: 0.5), value: kioskManager.isScreensaverActive)
                    .allowsHitTesting(
                        index == slideshowManager.currentIndex &&
                        !kioskManager.isScreensaverActive
                    )
            }

            // Dimming or URLs screensaver mode: transparent overlay intercepts touches to wake kiosk
            if kioskManager.isScreensaverActive && (settings.screensaverMode == "dimming" || settings.screensaverMode == "urls") {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        kioskManager.handleUserActivity()
                    }
            }

            // Clock Screensaver overlay
            if kioskManager.isScreensaverActive && (settings.screensaverMode == "clock" || settings.screensaverMode.isEmpty) {
                ScreensaverView()
                    .environmentObject(kioskManager)
                    .environmentObject(faceDetectionManager)
                    .environmentObject(settings)
                    .transition(.opacity)
            }

            // Settings Access (Hidden gesture area)
            VStack {
                HStack {
                    Spacer()
                    Rectangle()
                        .fill(Color.gray)
                        .cornerRadius(25)
                        .opacity(0.1)
                        .frame(width: 50, height: 50)
                        .onTapGesture(count: 3) {
                            kioskManager.setSettingsOpen(true)
                            showingSettings = true
                        }
                }
                Spacer()
            }
        }
        .onAppear {
            setupApp()
            setupNotifications()
            slideshowManager.configure(settings: settings, kioskManager: kioskManager)
            slideshowManager.start()
        }
        .onDisappear {
            brightnessManager.restoreOriginalBrightness()
            webServerManager.stop()
        }
        .onChange(of: showingSettings) { isOpen in
            kioskManager.setSettingsOpen(isOpen)
        }
        .onReceive(kioskManager.$isScreensaverActive) { active in
            if active && (settings.screensaverMode == "dimming" || settings.screensaverMode == "urls") {
                faceDetectionManager.startDetection()
            } else if !active && (settings.screensaverMode == "dimming" || settings.screensaverMode == "urls") {
                faceDetectionManager.stopDetection()
            }
        }
        .onReceive(faceDetectionManager.$faceDetected) { faceDetected in
            if faceDetected && kioskManager.isScreensaverActive {
                kioskManager.exitScreensaver()
            }
        }
        .onReceive(settings.$screensaverTimeout) { newTimeout in
            kioskManager.updateTimeout(newTimeout)
        }
        .onReceive(settings.$faceDetectionInterval) { newInterval in
            faceDetectionManager.reinitialize(withInterval: newInterval)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .statusBarHidden(true)
    }

    /// Returns 1.0 for the currently active slide, 0.0 for all others.
    /// In "urls" or "dimming" mode during screensaver, active slide stays visible.
    /// In "clock" mode, webview opacity is 0.0 beneath the black screensaver.
    private func webViewOpacity(for index: Int) -> Double {
        if kioskManager.isScreensaverActive {
            if settings.screensaverMode == "urls" || settings.screensaverMode == "dimming" {
                return index == slideshowManager.currentIndex ? 1.0 : 0.0
            } else {
                return 0.0
            }
        }
        return index == slideshowManager.currentIndex ? 1.0 : 0.0
    }

    private func setupApp() {
        // Prevent device from sleeping
        UIApplication.shared.isIdleTimerDisabled = true

        // Save original brightness and set to configured value
        brightnessManager.saveAndSetBrightness()

        // Setup audio session for continuous recording
        audioManager.setupAudioSession()

        // Start recording only if voice activation is enabled
        if settings.enableVoiceActivation {
            audioManager.startRecording()
        }

        // Start inactivity monitoring with current timeout
        kioskManager.startInactivityMonitoring()

        // Connect to MQTT if enabled
        if settings.enableMQTT {
            mqttManager.connect()
        }

        // Start remote web server if enabled
        webServerManager.start()
    }

    private func setupNotifications() {
        // Settings changed notification
        NotificationCenter.default.addObserver(
            forName: .settingsChanged,
            object: nil,
            queue: .main
        ) { _ in
            handleSettingsChanged()
        }

        // Screensaver notification
        NotificationCenter.default.addObserver(
            forName: .mqttScreensaverActivated,
            object: nil,
            queue: .main
        ) { _ in
            handleScreensaverActivated()
        }

        // Remote wakeup notification
        NotificationCenter.default.addObserver(
            forName: Notification.Name("UltraKiosk.remoteWakeup"),
            object: nil,
            queue: .main
        ) { _ in
            kioskManager.exitScreensaver()
        }
    }

    private func handleScreensaverActivated() {
        AppLogger.app.info("Activating screensaver")
        kioskManager.activateScreensaver()
    }

    private func handleSettingsChanged() {
        AppLogger.app.info("Settings changed – updating components")

        // Update audio recording based on voice activation setting
        if settings.enableVoiceActivation && !audioManager.isRecording {
            audioManager.startRecording()
        } else if !settings.enableVoiceActivation && audioManager.isRecording {
            audioManager.stopRecording()
        }

        // Update timeout
        kioskManager.updateTimeout(settings.screensaverTimeout)

        // Handle MQTT connection
        if settings.enableMQTT && !mqttManager.isConnected {
            mqttManager.connect()
        } else if !settings.enableMQTT && mqttManager.isConnected {
            mqttManager.disconnect()
        }

        // Clear the WKWebView HTTP and service-worker cache so stale assets are
        // never shown after settings are saved. Cookies and local/session storage
        // are intentionally preserved to keep login sessions (e.g. HA auth) alive.
        // After the async clear completes, each KioskWebView reloads itself.
        clearWebViewCachePreservingAuth()
    }

    /// Removes disk cache, memory cache, and service-worker registrations from the
    /// shared WKWebsiteDataStore, then signals every KioskWebView to reload.
    /// Auth state (cookies, localStorage, IndexedDB) is left untouched so that
    /// an existing Home Assistant login remains valid after the reload.
    private func clearWebViewCachePreservingAuth() {
        let cacheTypes: Set<String> = [
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeOfflineWebApplicationCache,
            WKWebsiteDataTypeServiceWorkerRegistrations,
        ]
        WKWebsiteDataStore.default().removeData(
            ofTypes: cacheTypes,
            modifiedSince: .distantPast
        ) {
            // Completion is called on the main thread by WKWebsiteDataStore.
            AppLogger.app.info("WKWebView cache cleared — triggering reload of all slides")
            NotificationCenter.default.post(name: .reloadAllWebViews, object: nil)
        }
    }
}
