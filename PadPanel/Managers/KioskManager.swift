import SwiftUI
import Combine

class KioskManager: ObservableObject {
    @Published var isScreensaverActive = false
    @Published var inactivityTimer: Timer?
    @Published var isSettingsOpen = false
    
    private let settings = SettingsManager.shared
    private let brightnessManager: BrightnessControlling
    private var inactivityTimeout: TimeInterval = 60.0
    private var cancellables = Set<AnyCancellable>()

    /// Production init uses a real BrightnessManager.
    /// Pass a mock that conforms to BrightnessControlling in unit tests.
    init(brightnessManager: BrightnessControlling = BrightnessManager()) {
        self.brightnessManager = brightnessManager
        inactivityTimeout = settings.screensaverTimeout
        
        settings.$screensaverMode
            .receive(on: RunLoop.main)
            .sink { [weak self] mode in
                guard let self = self else { return }
                if mode == "off" {
                    self.inactivityTimer?.invalidate()
                    self.inactivityTimer = nil
                    if self.isScreensaverActive {
                        self.exitScreensaver()
                    }
                } else if !self.isScreensaverActive && !self.isSettingsOpen {
                    self.resetInactivityTimer()
                }
            }
            .store(in: &cancellables)
    }
    
    func startInactivityMonitoring() {
        resetInactivityTimer()
    }
    
    func updateTimeout(_ newTimeout: TimeInterval) {
        inactivityTimeout = newTimeout
        if !isScreensaverActive && !isSettingsOpen {
            resetInactivityTimer()
        }
    }
    
    func setSettingsOpen(_ isOpen: Bool) {
        isSettingsOpen = isOpen
        if isOpen {
            inactivityTimer?.invalidate()
            inactivityTimer = nil
            if isScreensaverActive {
                exitScreensaver()
            } else {
                brightnessManager.setNormalBrightness()
            }
        } else {
            resetInactivityTimer()
        }
    }
    
    func resetInactivityTimer() {
        inactivityTimer?.invalidate()
        inactivityTimer = nil
        
        guard !isSettingsOpen else { return }
        guard settings.screensaverMode != "off" else { return }
        
        if !isScreensaverActive {
            inactivityTimer = Timer.scheduledTimer(withTimeInterval: inactivityTimeout, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.activateScreensaver()
                }
            }
        }
    }
    
    func activateScreensaver() {
        guard !isSettingsOpen else { return }
        guard settings.screensaverMode != "off" else { return }
        
        withAnimation(.easeInOut(duration: 0.5)) {
            isScreensaverActive = true
        }
        
        // Dim screen using brightness manager
        brightnessManager.dimScreen()
    }
    
    func exitScreensaver() {
        withAnimation(.easeInOut(duration: 0.5)) {
            isScreensaverActive = false
        }
        
        // Restore screen brightness using brightness manager
        brightnessManager.setNormalBrightness()
        
        resetInactivityTimer()
    }
    
    func handleUserActivity() {
        if isScreensaverActive {
            exitScreensaver()
        } else {
            resetInactivityTimer()
        }
    }
}
