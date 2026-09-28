import { useState, useEffect, useRef, useCallback } from "react";
import { UltraKioskSettings } from "../types/settings";

interface KioskManagerProps {
  settings: UltraKioskSettings;
}

export function useKioskManager({ settings }: KioskManagerProps) {
  const [isScreensaverActive, setIsScreensaverActive] = useState<boolean>(false);
  const [currentSlideIndex, setCurrentSlideIndex] = useState<number>(0);
  const [isSlideshowPaused, setIsSlideshowPaused] = useState<boolean>(false);
  const [inactivitySecondsLeft, setInactivitySecondsLeft] = useState<number>(settings.screensaverTimeout);
  const [batteryLevel, setBatteryLevel] = useState<number>(85);
  const [isCharging, setIsCharging] = useState<boolean>(true);
  const [lastMqttReportTime, setLastMqttReportTime] = useState<Date | null>(null);

  const inactivityTimerRef = useRef<number | null>(null);
  const slideshowTimerRef = useRef<number | null>(null);
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
    setIsScreensaverActive(true);
  }, []);

  const exitScreensaver = useCallback(() => {
    setIsScreensaverActive(false);
    setInactivitySecondsLeft(settings.screensaverTimeout);
  }, [settings.screensaverTimeout]);

  // Inactivity countdown loop
  useEffect(() => {
    inactivityTimerRef.current = window.setInterval(() => {
      setInactivitySecondsLeft((prev) => {
        if (prev <= 1) {
          if (!isScreensaverActive) {
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
  }, [isScreensaverActive]);

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
  useEffect(() => {
    // Only run if multiple slides and not paused and not on screensaver
    if (totalSlides <= 1 || isSlideshowPaused || isScreensaverActive) {
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
  }, [totalSlides, isSlideshowPaused, isScreensaverActive, settings.slideshowInterval]);

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

  const goToSlide = (index: number) => {
    if (index >= 0 && index < totalSlides) {
      setCurrentSlideIndex(index);
      handleUserActivity();
    }
  };

  const togglePauseSlideshow = () => {
    setIsSlideshowPaused((prev) => !prev);
    handleUserActivity();
  };

  // Brightness factor: screenBrightnessDimmed when screensaver active, else screenBrightnessNormal
  const currentBrightness = isScreensaverActive
    ? settings.screenBrightnessDimmed
    : settings.screenBrightnessNormal;

  return {
    isScreensaverActive,
    currentSlideIndex,
    totalSlides,
    effectiveURLs,
    isSlideshowPaused,
    inactivitySecondsLeft,
    batteryLevel,
    isCharging,
    lastMqttReportTime,
    currentBrightness,
    activateScreensaver,
    exitScreensaver,
    handleUserActivity,
    nextSlide,
    prevSlide,
    goToSlide,
    togglePauseSlideshow,
  };
}
