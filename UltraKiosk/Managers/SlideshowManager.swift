import Foundation
import Combine

/// Manages cycling through URLs when the screensaver is in "URLs" mode.
/// Smoothly transitions between configured URLs and automatically resets
/// to slide 0 when the kiosk wakes up.
final class SlideshowManager: ObservableObject {

    @Published var currentIndex: Int = 0

    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private weak var settings: SettingsManager?
    private weak var kioskManager: KioskManager?

    /// Wires up Combine observers and prepares the manager for use.
    /// Must be called once from ContentView.onAppear before start().
    func configure(settings: SettingsManager, kioskManager: KioskManager) {
        self.settings = settings
        self.kioskManager = kioskManager

        // Watch screensaver state
        kioskManager.$isScreensaverActive
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateTimerState()
            }
            .store(in: &cancellables)

        // Watch screensaver mode
        settings.$screensaverMode
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateTimerState()
            }
            .store(in: &cancellables)

        // Restart when the URL list changes
        settings.$slideshowURLs
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.restart()
            }
            .store(in: &cancellables)

        // Restart when the interval changes
        settings.$slideshowInterval
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.restart()
            }
            .store(in: &cancellables)
    }

    /// Starts the slideshow. Call after configure().
    func start() {
        updateTimerState()
    }

    // MARK: - Private

    private func updateTimerState() {
        guard let s = settings, let km = kioskManager else { return }
        
        if s.screensaverMode == "urls" {
            if km.isScreensaverActive {
                startTimer()
            } else {
                pauseTimer()
                if currentIndex != 0 {
                    currentIndex = 0
                }
            }
        } else {
            pauseTimer()
            if currentIndex != 0 {
                currentIndex = 0
            }
        }
    }

    private func startTimer() {
        guard let s = settings,
              s.effectiveURLs.count > 1 else { return }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: s.slideshowInterval, repeats: true) { [weak self] _ in
            self?.advance()
        }
    }

    private func pauseTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func restart() {
        pauseTimer()
        let count = settings?.effectiveURLs.count ?? 0
        if count > 0 {
            let clamped = min(currentIndex, count - 1)
            if clamped != currentIndex { currentIndex = clamped }
        }
        updateTimerState()
    }

    private func advance() {
        guard let count = settings?.effectiveURLs.count, count > 1 else { return }
        currentIndex = (currentIndex + 1) % count
    }
}
