import React, { useState } from "react";
import {
  loadSettingsFromStorage,
  saveSettingsToStorage,
  UltraKioskSettings,
} from "./types/settings";
import { useKioskManager } from "./hooks/useKioskManager";
import { useFaceDetection } from "./hooks/useFaceDetection";
import { useVoiceSatellite } from "./hooks/useVoiceSatellite";
import { KioskWebView } from "./components/KioskWebView";
import { ScreensaverView } from "./components/ScreensaverView";
import { SettingsModal } from "./components/SettingsModal";
import { TripleTapArea } from "./components/TripleTapArea";
import { KioskControls } from "./components/KioskControls";

export function App() {
  const [settings, setSettings] = useState<UltraKioskSettings>(() => loadSettingsFromStorage());
  const [isSettingsOpen, setIsSettingsOpen] = useState<boolean>(false);

  // Kiosk inactivity & slideshow manager
  const kiosk = useKioskManager({ settings });

  // Face / motion detection hook to wake screen
  const faceDetection = useFaceDetection({
    enabled: settings.enableVoiceActivation || kiosk.isScreensaverActive,
    interval: settings.faceDetectionInterval,
    onFaceDetected: () => {
      if (kiosk.isScreensaverActive) {
        kiosk.exitScreensaver();
      } else {
        kiosk.handleUserActivity();
      }
    },
  });

  // Voice satellite hook
  const voice = useVoiceSatellite({
    settings,
    onVoiceCommand: (cmd) => {
      console.log("[Voice Command Executed]:", cmd);
    },
  });

  // Save settings updates
  const handleSaveSettings = (newSettings: UltraKioskSettings) => {
    setSettings(newSettings);
    saveSettingsToStorage(newSettings);
  };

  // Determine slide slots (at least 1 slide slot, either welcome screen or configured URLs)
  const slots: (string | null)[] =
    kiosk.effectiveURLs.length === 0 ? [null] : kiosk.effectiveURLs;

  return (
    <div
      className="relative w-screen h-screen overflow-hidden bg-black text-white select-none transition-all duration-500"
      style={{
        filter: `brightness(${kiosk.currentBrightness})`,
      }}
    >
      {/* Hidden camera preview and processing canvas with iOS 15 playsinline requirements */}
      <div className="absolute opacity-0 pointer-events-none w-0 h-0 overflow-hidden" aria-hidden="true">
        <video
          ref={faceDetection.videoRef}
          playsInline
          muted
          autoPlay
          {...({ "webkit-playsinline": "true" } as React.VideoHTMLAttributes<HTMLVideoElement>)}
          className="w-16 h-12"
        />
        <canvas ref={faceDetection.canvasRef} className="w-16 h-12" />
      </div>

      {/* Main Resident WebViews with Smooth Cross-fade matching iOS UltraKiosk */}
      <div className="relative w-full h-full">
        {slots.map((urlOrNil, index) => {
          const isActive =
            index === kiosk.currentSlideIndex && !kiosk.isScreensaverActive;
          return (
            <div
              key={index}
              className="absolute inset-0 transition-opacity duration-500"
              style={{
                opacity: isActive ? 1 : 0,
                pointerEvents: isActive ? "auto" : "none",
                zIndex: isActive ? 10 : 0,
              }}
            >
              <KioskWebView
                url={urlOrNil}
                isActive={isActive}
                onOpenSettings={() => setIsSettingsOpen(true)}
                onActivity={kiosk.handleUserActivity}
              />
            </div>
          );
        })}
      </div>

      {/* Screensaver Overlay */}
      {kiosk.isScreensaverActive && (
        <ScreensaverView
          onWake={kiosk.exitScreensaver}
          isFaceDetectionActive={faceDetection.isDetecting}
          onSimulateFaceWake={faceDetection.simulateDetection}
          motionLevel={faceDetection.motionLevel}
        />
      )}

      {/* Top Right Triple-Tap Gesture Area */}
      <TripleTapArea onTrigger={() => setIsSettingsOpen(true)} />

      {/* Floating Kiosk Controls Bar (only shown when screensaver is inactive) */}
      {!kiosk.isScreensaverActive && (
        <KioskControls
          currentSlide={kiosk.currentSlideIndex}
          totalSlides={kiosk.totalSlides}
          isPaused={kiosk.isSlideshowPaused}
          onNext={kiosk.nextSlide}
          onPrev={kiosk.prevSlide}
          onTogglePause={kiosk.togglePauseSlideshow}
          onGoToSlide={kiosk.goToSlide}
          inactivitySeconds={kiosk.inactivitySecondsLeft}
          onTriggerScreensaver={kiosk.activateScreensaver}
          batteryLevel={kiosk.batteryLevel}
          isCharging={kiosk.isCharging}
          isVoiceActive={settings.enableVoiceActivation}
          voiceSatelliteStatus={voice.satelliteStatus}
          onTriggerVoiceAssistant={() => voice.triggerWakeWord()}
        />
      )}

      {/* Settings Modal */}
      <SettingsModal
        isOpen={isSettingsOpen}
        onClose={() => setIsSettingsOpen(false)}
        settings={settings}
        onSave={handleSaveSettings}
        onTestVoiceSatellite={() => voice.triggerWakeWord("Living Room Light Toggle")}
      />
    </div>
  );
}
export default App;
