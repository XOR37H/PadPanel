import { useState, useEffect, useRef, useCallback } from "react";
import { PadPanelSettings } from "../types/settings";

interface KioskManagerProps {
  settings: PadPanelSettings;
}

export function useKioskManager({ settings }: KioskManagerProps) {
  const [isScreensaverActive, setIsScreensaverActive] = useState<boolean>(false);
  const [currentSlideIndex, setCurrentSlideIndex] = useState<number>(0);
  const [isSlideshowPaused, setIsSlideshowPaused] = useState<boolean>(false);
  const [inactivitySecondsLeft, setInactivitySecondsLeft] = useState<number>(settings.screensaverTimeout);
  const [batteryLevel, setBatteryLevel] = useState<number>(88);
  const [isCharging, setIsCharging] = useState<boolean>(true);
  const [lastMqttReportTime, setLastMqttReportTime] = useState<Date | null>(null);
  const [reloadCounter, setReloadCounter] = useState<number>(0);

  const inactivityTimerRef = useRef<number | null>(null);
  const slideshowTimerRef = useRef<number | null>(null);
  const autoRefreshTimerRef = useRef<number | null>(null);
  const batteryTimerRef = useRef<number | null>(null);

  // Filter non-empty URLs
  const effectiveURLs = settings.slideshowURLs.filter((u) => u.trim().length > 0);
  const totalSlides = effectiveURLs.length === 0 ? 1 : effectiveURLs.length;

  // Wake display / reset inactivity timer
  const handleUserActivity = useCallback(() => {
    setInactivitySecondsLeft(settings.screensaverTimeout);
    if (isScreensaverActive) {
      setIsScreensaverActive(false);
    }
  }, [settings.screensaverTimeout, isScreensaverActive]);

  const activateScreensaver = useCallback(() => {
    if (settings.screensaverMode === "off") return;
    setIsScreensaverActive(true);
  }, [settings.screensaverMode]);

  const exitScreensaver = useCallback(() => {
    setIsScreensaverActive(false);
    setInactivitySecondsLeft(settings.screensaverTimeout);
  }, [settings.screensaverTimeout]);

  const reloadAllWebViews = useCallback(() => {
    setReloadCounter((c) => c + 1);
  }, []);

  // Inactivity countdown loop
  useEffect(() => {
    if (settings.screensaverMode === "off") {
      if (isScreensaverActive) setIsScreensaverActive(false);
      return;
    }

    inactivityTimerRef.current = window.setInterval(() => {
      setInactivitySecondsLeft((prev) => {
        if (prev <= 1) {
          if (!isScreensaverActive && settings.screensaverMode !== "off") {
            setIsScreensaverActive(true);
          }
          return 0;
        }
        return prev - 1;
      });
    }, 1000);

    return () => {
      if (inactivityTimerRef.current) {
        clearInterval(inactivityTimerRef.current);
      }
    };
  }, [isScreensaverActive, settings.screensaverMode]);

  // When timeout setting changes, update remaining seconds
  useEffect(() => {
    setInactivitySecondsLeft(settings.screensaverTimeout);
  }, [settings.screensaverTimeout]);

  // Global activity listener (click, touch, pointer, keypress)
  useEffect(() => {
    const handleEvent = () => {
      handleUserActivity();
    };

    window.addEventListener("pointerdown", handleEvent, { passive: true });
    window.addEventListener("keydown", handleEvent, { passive: true });
    window.addEventListener("touchstart", handleEvent, { passive: true });

    return () => {
      window.removeEventListener("pointerdown", handleEvent);
      window.removeEventListener("keydown", handleEvent);
      window.removeEventListener("touchstart", handleEvent);
    };
  }, [handleUserActivity]);

  // Slideshow advance timer
  // Runs if multiple slides, or if screensaverMode === 'urls' and on screensaver
  useEffect(() => {
    const isUrlsScreensaver = isScreensaverActive && settings.screensaverMode === "urls";
    const canRunSlideshow = (totalSlides > 1 && !isSlideshowPaused && !isScreensaverActive) || (isUrlsScreensaver && totalSlides > 1);

    if (!canRunSlideshow) {
      if (slideshowTimerRef.current) {
        clearInterval(slideshowTimerRef.current);
        slideshowTimerRef.current = null;
      }
      return;
    }

    const intervalMs = Math.max(5, settings.slideshowInterval) * 1000;
    slideshowTimerRef.current = window.setInterval(() => {
      setCurrentSlideIndex((prev) => (prev + 1) % totalSlides);
    }, intervalMs);

    return () => {
      if (slideshowTimerRef.current) {
        clearInterval(slideshowTimerRef.current);
        slideshowTimerRef.current = null;
      }
    };
  }, [totalSlides, isSlideshowPaused, isScreensaverActive, settings.screensaverMode, settings.slideshowInterval]);

  // Auto-refresh WebView timer
  useEffect(() => {
    if (!settings.enableAutoRefresh) {
      if (autoRefreshTimerRef.current) {
        clearInterval(autoRefreshTimerRef.current);
        autoRefreshTimerRef.current = null;
      }
      return;
    }

    const refreshMs = Math.max(10, settings.autoRefreshInterval) * 1000;
    autoRefreshTimerRef.current = window.setInterval(() => {
      setReloadCounter((c) => c + 1);
    }, refreshMs);

    return () => {
      if (autoRefreshTimerRef.current) {
        clearInterval(autoRefreshTimerRef.current);
        autoRefreshTimerRef.current = null;
      }
    };
  }, [settings.enableAutoRefresh, settings.autoRefreshInterval]);

  // Listen to remote actions (MQTT & WebUI)
  useEffect(() => {
    const handleRemoteAction = (e: CustomEvent) => {
      const action = e.detail?.action;
      if (action === "screensaver") {
        activateScreensaver();
      } else if (action === "wakeup") {
        exitScreensaver();
      } else if (action === "reload") {
        reloadAllWebViews();
      }
    };

    window.addEventListener("padpanel:remote-action" as any, handleRemoteAction);
    return () => {
      window.removeEventListener("padpanel:remote-action" as any, handleRemoteAction);
    };
  }, [activateScreensaver, exitScreensaver, reloadAllWebViews]);

  // Make sure currentSlideIndex is in bounds if URLs change
  useEffect(() => {
    if (currentSlideIndex >= totalSlides) {
      setCurrentSlideIndex(0);
    }
  }, [currentSlideIndex, totalSlides]);

  // Battery monitoring (real navigator.getBattery API if available)
  useEffect(() => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const nav = navigator as any;
    if (nav.getBattery) {
      nav.getBattery().then((battery: { level: number; charging: boolean; addEventListener: (event: string, cb: () => void) => void }) => {
        const update = () => {
          setBatteryLevel(Math.round(battery.level * 100));
          setIsCharging(battery.charging);
        };
        update();
        battery.addEventListener("levelchange", update);
        battery.addEventListener("chargingchange", update);
      }).catch(() => {});
    }

    // MQTT reporting interval simulation
    const reportIntervalMs = Math.max(10, settings.mqttBatteryUpdateInterval) * 1000;
    batteryTimerRef.current = window.setInterval(() => {
      if (settings.enableMQTT) {
        setLastMqttReportTime(new Date());
      }
    }, reportIntervalMs);

    return () => {
      if (batteryTimerRef.current) {
        clearInterval(batteryTimerRef.current);
      }
    };
  }, [settings.enableMQTT, settings.mqttBatteryUpdateInterval]);

  const nextSlide = () => {
    setCurrentSlideIndex((prev) => (prev + 1) % totalSlides);
    handleUserActivity();
  };

  const prevSlide = () => {
    setCurrentSlideIndex((prev) => (prev - 1 + totalSlides) % totalSlides);
    handleUserActivity();
  };

  const togglePauseSlideshow = () => {
    setIsSlideshowPaused((prev) => !prev);
  };

  const goToSlide = (index: number) => {
    if (index >= 0 && index < totalSlides) {
      setCurrentSlideIndex(index);
      handleUserActivity();
    }
  };

  // Compute display brightness based on state and mode
  // If screensaver is active:
  // - "clock": brightness is screenBrightnessDimmed (and clock view is overlayed)
  // - "dimming": brightness is screenBrightnessDimmed (kiosk webview stays visible)
  // - "urls": brightness is screenBrightnessNormal (or dimmed if configured)
  // When active: screenBrightnessNormal
  let currentBrightness = settings.screenBrightnessNormal;
  if (isScreensaverActive) {
    if (settings.screensaverMode === "dimming" || settings.screensaverMode === "clock") {
      currentBrightness = settings.screenBrightnessDimmed;
    }
  }

  // Determine whether the clock screensaver overlay should actually be shown
  const shouldShowClockScreensaver = isScreensaverActive && settings.screensaverMode === "clock";
  const isDimmedOnly = isScreensaverActive && settings.screensaverMode === "dimming";

  return {
    isScreensaverActive,
    shouldShowClockScreensaver,
    isDimmedOnly,
    currentBrightness,
    currentSlideIndex,
    isSlideshowPaused,
    inactivitySecondsLeft,
    effectiveURLs,
    totalSlides,
    batteryLevel,
    isCharging,
    lastMqttReportTime,
    reloadCounter,
    handleUserActivity,
    activateScreensaver,
    exitScreensaver,
    reloadAllWebViews,
    nextSlide,
    prevSlide,
    togglePauseSlideshow,
    goToSlide,
  };
}
