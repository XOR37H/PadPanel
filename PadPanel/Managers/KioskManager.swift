import SwiftUI
import Combine

class KioskManager: ObservableObject {
    @Published var isScreensaverActive = false
    @Published var isDeepSleepActive = false
    @Published var inactivityTimer: Timer?
    @Published var deepSleepTimer: Timer?
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
                    if self.isScreensaverActive && !self.isDeepSleepActive {
                        self.exitScreensaver()
                    }
                } else if !self.isScreensaverActive && !self.isSettingsOpen {
                    self.resetInactivityTimer()
                }
            }
            .store(in: &cancellables)
            
        // Watch deep sleep toggle
        settings.$enableDeepSleep
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                guard let self = self else { return }
                if !enabled {
                    self.deepSleepTimer?.invalidate()
                    self.deepSleepTimer = nil
                    if self.isDeepSleepActive {
                        self.exitDeepSleep()
                    }
                } else if !self.isSettingsOpen {
                    self.resetDeepSleepTimer()
                }
            }
            .store(in: &cancellables)

        // Watch deep sleep timeout
        settings.$deepSleepTimeout
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                if self.settings.enableDeepSleep && !self.isDeepSleepActive && !self.isSettingsOpen {
                    self.resetDeepSleepTimer()
                }
            }
            .store(in: &cancellables)
    }
    
    func startInactivityMonitoring() {
        resetInactivityTimer()
        resetDeepSleepTimer()
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
            deepSleepTimer?.invalidate()
            deepSleepTimer = nil
            if isDeepSleepActive {
                exitDeepSleep()
            } else if isScreensaverActive {
                exitScreensaver()
            } else {
                brightnessManager.setNormalBrightness()
            }
        } else {
            resetInactivityTimer()
            resetDeepSleepTimer()
        }
    }
    
    func resetInactivityTimer() {
        inactivityTimer?.invalidate()
        inactivityTimer = nil
        
        guard !isSettingsOpen else { return }
        guard settings.screensaverMode != "off" else { return }
        
        if !isScreensaverActive {
            let timer = Timer.scheduledTimer(withTimeInterval: inactivityTimeout, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.activateScreensaver()
                }
            }
            timer.tolerance = min(1.0, max(0.2, inactivityTimeout * 0.05))
            inactivityTimer = timer
        }
    }
    
    func resetDeepSleepTimer() {
        deepSleepTimer?.invalidate()
        deepSleepTimer = nil
        
        guard !isSettingsOpen else { return }
        guard settings.enableDeepSleep else { return }
        guard !isDeepSleepActive else { return }
        
        let timeout = max(60.0, settings.deepSleepTimeout)
        let timer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.activateDeepSleep()
            }
        }
        timer.tolerance = 5.0 // Coalesce timer wakeups to save battery
        deepSleepTimer = timer
    }
    
    func activateScreensaver() {
        guard !isSettingsOpen else { return }
        guard !isDeepSleepActive else { return }
        guard settings.screensaverMode != "off" else { return }
        
        withAnimation(.easeInOut(duration: 0.5)) {
            isScreensaverActive = true
        }
        
        // Dim screen using brightness manager
        brightnessManager.dimScreen()
    }
    
    func activateDeepSleep(force: Bool = false) {
        if !force {
            guard !isSettingsOpen else { return }
            guard settings.enableDeepSleep else { return }
        } else {
            isSettingsOpen = false
        }
        
        withAnimation(.easeInOut(duration: 0.3)) {
            isDeepSleepActive = true
            isScreensaverActive = true
        }
        
        // Lower brightness to absolute minimum (0.0)
        brightnessManager.setMinimumBrightness()
        
        inactivityTimer?.invalidate()
        inactivityTimer = nil
        deepSleepTimer?.invalidate()
        deepSleepTimer = nil
        
        AppLogger.app.info("Entered App Deep Sleep mode — camera stopped, screen blacked out")
    }
    
    func exitDeepSleep() {
        withAnimation(.easeInOut(duration: 0.5)) {
            isDeepSleepActive = false
            isScreensaverActive = false
        }
        
        // Restore screen brightness
        brightnessManager.setNormalBrightness()
        
        resetInactivityTimer()
        resetDeepSleepTimer()
        
        AppLogger.app.info("Exited Deep Sleep mode — normal kiosk active")
    }
    
    func exitScreensaver() {
        if isDeepSleepActive {
            exitDeepSleep()
            return
        }
        
        withAnimation(.easeInOut(duration: 0.5)) {
            isScreensaverActive = false
        }
        
        // Restore screen brightness using brightness manager
        brightnessManager.setNormalBrightness()
        
        resetInactivityTimer()
        resetDeepSleepTimer()
    }
    
    func handleUserActivity() {
        if isDeepSleepActive {
            exitDeepSleep()
        } else if isScreensaverActive {
            exitScreensaver()
        } else {
            resetInactivityTimer()
            resetDeepSleepTimer()
        }
    }
}
