import React, { useState, useCallback } from "react";
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
import { DeviceAuthModal } from "./components/DeviceAuthModal";
import { TripleTapArea } from "./components/TripleTapArea";
import { KioskControls } from "./components/KioskControls";
import { WebUIPortalModal } from "./components/WebUIPortalModal";
import { MQTTInspectorModal } from "./components/MQTTInspectorModal";

export function App() {
  const [settings, setSettings] = useState<UltraKioskSettings>(() => loadSettingsFromStorage());
  const [isSettingsOpen, setIsSettingsOpen] = useState<boolean>(false);
  const [isAuthModalOpen, setIsAuthModalOpen] = useState<boolean>(false);
  const [isWebUIPortalOpen, setIsWebUIPortalOpen] = useState<boolean>(false);
  const [isMQTTInspectorOpen, setIsMQTTInspectorOpen] = useState<boolean>(false);

  // Kiosk inactivity & slideshow manager
  const kiosk = useKioskManager({ settings });

  // Face / motion detection hook to wake screen
  const faceDetection = useFaceDetection({
    enabled: settings.enableVoiceActivation || kiosk.isScreensaverActive,
    interval: settings.faceDetectionInterval,
    wakeupMethod: settings.wakeupMethod,
    motionSensitivity: settings.motionSensitivity,
    showDebugInfo: settings.showDebugInfo,
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

  // Check if settings access needs password authentication
  const handleRequestOpenSettings = useCallback(() => {
    const adminPass = settings.deviceAdminPassword || settings.webServerPassword || "";
    const isAuthRequired = settings.requireDeviceAuth || adminPass.length > 0;

    if (isAuthRequired && adminPass.length > 0) {
      setIsAuthModalOpen(true);
    } else {
      setIsSettingsOpen(true);
    }
  }, [settings.deviceAdminPassword, settings.webServerPassword, settings.requireDeviceAuth]);

  // Handle successful device authentication
  const handleAuthSuccess = () => {
    setIsAuthModalOpen(false);
    setIsSettingsOpen(true);
  };

  // Save settings updates
  const handleSaveSettings = (newSettings: UltraKioskSettings) => {
    setSettings(newSettings);
    saveSettingsToStorage(newSettings);
  };

  // Real-time live settings update (e.g. while dragging brightness slider in WebUI or Settings)
  const handleLiveSettingChange = (key: keyof UltraKioskSettings, value: any) => {
    setSettings((prev) => {
      const updated = { ...prev, [key]: value };
      // Save in background
      saveSettingsToStorage(updated);
      return updated;
    });
  };

  // Handle remote action (e.g. from WebUI or MQTT)
  const handleTriggerAction = (action: "screensaver" | "wakeup" | "reload") => {
    if (action === "screensaver") {
      kiosk.activateScreensaver();
    } else if (action === "wakeup") {
      kiosk.exitScreensaver();
    } else if (action === "reload") {
      kiosk.reloadAllWebViews();
    }
  };

  // Determine slide slots (at least 1 slide slot, either welcome screen or configured URLs)
  const slots: (string | null)[] =
    kiosk.effectiveURLs.length === 0 ? [null] : kiosk.effectiveURLs;

  return (
    <div
      className="relative w-screen h-screen overflow-hidden bg-black text-white select-none transition-all duration-300"
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

      {/* Main Resident WebViews with Smooth Cross-fade matching iOS PadPanel */}
      <div className="relative w-full h-full">
        {slots.map((urlOrNil, index) => {
          const isActive =
            index === kiosk.currentSlideIndex && (!kiosk.isScreensaverActive || kiosk.isDimmedOnly);
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
                reloadCounter={kiosk.reloadCounter}
                onOpenSettings={handleRequestOpenSettings}
                onActivity={kiosk.handleUserActivity}
              />
            </div>
          );
        })}
      </div>

      {/* Screensaver Overlay (shown when mode is 'clock') */}
      {kiosk.shouldShowClockScreensaver && (
        <ScreensaverView
          onWake={kiosk.exitScreensaver}
          isFaceDetectionActive={faceDetection.isDetecting}
          onSimulateFaceWake={faceDetection.simulateDetection}
          motionLevel={faceDetection.motionLevel}
          wakeupMethod={settings.wakeupMethod}
          motionSensitivity={settings.motionSensitivity}
          showDebugInfo={settings.showDebugInfo}
          batteryLevel={kiosk.batteryLevel}
          isCharging={kiosk.isCharging}
        />
      )}

      {/* Top Right Triple-Tap Gesture Area */}
      <TripleTapArea onTrigger={handleRequestOpenSettings} />

      {/* Floating Kiosk Controls Bar (only shown when clock screensaver is inactive) */}
      {!kiosk.shouldShowClockScreensaver && (
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
          onReload={kiosk.reloadAllWebViews}
          onOpenSettings={handleRequestOpenSettings}
          onOpenWebUIPortal={() => setIsWebUIPortalOpen(true)}
          onOpenMQTTInspector={() => setIsMQTTInspectorOpen(true)}
          batteryLevel={kiosk.batteryLevel}
          isCharging={kiosk.isCharging}
          isVoiceActive={settings.enableVoiceActivation}
          voiceSatelliteStatus={voice.satelliteStatus}
          onTriggerVoiceAssistant={() => voice.triggerWakeWord()}
          screensaverMode={settings.screensaverMode}
          webServerEnabled={settings.enableWebServer}
          webServerPort={settings.webServerPort}
          mqttEnabled={settings.enableMQTT}
        />
      )}

      {/* Device Authentication Modal (Kiosk Settings Lock) */}
      <DeviceAuthModal
        isOpen={isAuthModalOpen}
        onClose={() => setIsAuthModalOpen(false)}
        onAuthenticated={handleAuthSuccess}
        expectedUsername={settings.deviceAdminUsername || settings.webServerUsername || "admin"}
        expectedPassword={settings.deviceAdminPassword || settings.webServerPassword || ""}
      />

      {/* Settings Modal */}
      <SettingsModal
        isOpen={isSettingsOpen}
        onClose={() => setIsSettingsOpen(false)}
        settings={settings}
        onSave={handleSaveSettings}
        onLiveSettingChange={handleLiveSettingChange}
        onTestVoiceSatellite={() => voice.triggerWakeWord("Living Room Light Toggle")}
        onOpenWebUIPortal={() => {
          setIsSettingsOpen(false);
          setIsWebUIPortalOpen(true);
        }}
        onOpenMQTTInspector={() => {
          setIsSettingsOpen(false);
          setIsMQTTInspectorOpen(true);
        }}
      />

      {/* Remote WebUI Portal Modal */}
      <WebUIPortalModal
        isOpen={isWebUIPortalOpen}
        onClose={() => setIsWebUIPortalOpen(false)}
        settings={settings}
        onSaveSettings={handleSaveSettings}
        onLiveSettingChange={handleLiveSettingChange}
        onTriggerAction={handleTriggerAction}
        isScreensaverActive={kiosk.isScreensaverActive}
        batteryLevel={kiosk.batteryLevel}
        isCharging={kiosk.isCharging}
        inactivitySecondsLeft={kiosk.inactivitySecondsLeft}
      />

      {/* MQTT Inspector & Command Tester Modal */}
      <MQTTInspectorModal
        isOpen={isMQTTInspectorOpen}
        onClose={() => setIsMQTTInspectorOpen(false)}
        settings={settings}
        onUpdateSetting={handleLiveSettingChange}
        onTriggerAction={handleTriggerAction}
        batteryLevel={kiosk.batteryLevel}
        isCharging={kiosk.isCharging}
        isScreensaverActive={kiosk.isScreensaverActive}
      />
    </div>
  );
}
export default App;
