import React, { useState } from "react";
import {
  ChevronLeft,
  ChevronRight,
  Play,
  Pause,
  Maximize2,
  Minimize2,
  Clock,
  BatteryCharging,
  Battery,
  Mic,
  ChevronUp,
  ChevronDown,
  Globe,
  Radio,
  RefreshCw,
  Power,
  Sliders,
} from "lucide-react";
import { ScreensaverMode } from "../types/settings";

interface KioskControlsProps {
  currentSlide: number;
  totalSlides: number;
  isPaused: boolean;
  onNext: () => void;
  onPrev: () => void;
  onTogglePause: () => void;
  onGoToSlide: (idx: number) => void;
  inactivitySeconds: number;
  onTriggerScreensaver: () => void;
  onReload: () => void;
  onOpenSettings: () => void;
  onOpenWebUIPortal?: () => void;
  onOpenMQTTInspector?: () => void;
  batteryLevel: number;
  isCharging: boolean;
  isVoiceActive: boolean;
  voiceSatelliteStatus: string;
  onTriggerVoiceAssistant: () => void;
  screensaverMode?: ScreensaverMode;
  webServerEnabled?: boolean;
  webServerPort?: number;
  mqttEnabled?: boolean;
}

export const KioskControls: React.FC<KioskControlsProps> = ({
  currentSlide,
  totalSlides,
  isPaused,
  onNext,
  onPrev,
  onTogglePause,
  onGoToSlide,
  inactivitySeconds,
  onTriggerScreensaver,
  onReload,
  onOpenSettings,
  onOpenWebUIPortal,
  onOpenMQTTInspector,
  batteryLevel,
  isCharging,
  isVoiceActive,
  voiceSatelliteStatus,
  onTriggerVoiceAssistant,
  screensaverMode = "clock",
  webServerEnabled = true,
  webServerPort = 8080,
  mqttEnabled = true,
}) => {
  const [isFullscreen, setIsFullscreen] = useState<boolean>(false);
  const [collapsed, setCollapsed] = useState<boolean>(false);

  const toggleFullscreen = () => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const doc = document as any;
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const docEl = document.documentElement as any;

    const isFull = doc.fullscreenElement || doc.webkitFullscreenElement || doc.mozFullScreenElement;

    if (!isFull) {
      if (docEl.requestFullscreen) {
        docEl.requestFullscreen().catch(() => {});
      } else if (docEl.webkitRequestFullscreen) {
        docEl.webkitRequestFullscreen();
      } else if (docEl.webkitEnterFullscreen) {
        docEl.webkitEnterFullscreen();
      }
      setIsFullscreen(true);
    } else {
      if (doc.exitFullscreen) {
        doc.exitFullscreen().catch(() => {});
      } else if (doc.webkitExitFullscreen) {
        doc.webkitExitFullscreen();
      }
      setIsFullscreen(false);
    }
  };

  return (
    <div className="fixed bottom-3 left-1/2 -translate-x-1/2 z-30 select-none max-w-[95vw]">
      {collapsed ? (
        <button
          onClick={() => setCollapsed(false)}
          className="px-3 py-1.5 rounded-full bg-black/60 hover:bg-black/80 backdrop-blur-md border border-white/10 text-white/60 hover:text-white text-xs flex items-center space-x-1 shadow-lg transition"
        >
          <span>Kiosk Bar</span>
          <ChevronUp className="w-3.5 h-3.5" />
        </button>
      ) : (
        <div className="flex flex-wrap items-center gap-1.5 sm:gap-2 p-1.5 px-3 rounded-2xl bg-black/75 hover:bg-black/90 backdrop-blur-lg border border-white/15 text-white shadow-2xl transition duration-300">
          
          {/* Slideshow controls (if multiple slides) */}
          {totalSlides > 1 && (
            <div className="flex items-center space-x-1.5 pr-2 border-r border-white/15">
              <button
                onClick={onPrev}
                className="p-1 rounded-lg hover:bg-white/10 text-white/70 hover:text-white"
                title="Previous Slide"
              >
                <ChevronLeft className="w-4 h-4" />
              </button>

              <div className="flex space-x-1">
                {Array.from({ length: totalSlides }).map((_, idx) => (
                  <button
                    key={idx}
                    onClick={() => onGoToSlide(idx)}
                    className={`w-2.5 h-2.5 rounded-full transition-all ${
                      idx === currentSlide
                        ? "bg-indigo-400 w-5"
                        : "bg-white/30 hover:bg-white/50"
                    }`}
                    title={`Slide ${idx + 1}`}
                  />
                ))}
              </div>

              <button
                onClick={onNext}
                className="p-1 rounded-lg hover:bg-white/10 text-white/70 hover:text-white"
                title="Next Slide"
              >
                <ChevronRight className="w-4 h-4" />
              </button>

              <button
                onClick={onTogglePause}
                className="p-1 rounded-lg hover:bg-white/10 text-white/70 hover:text-white"
                title={isPaused ? "Resume Slideshow" : "Pause Slideshow"}
              >
                {isPaused ? <Play className="w-3.5 h-3.5 text-amber-400" /> : <Pause className="w-3.5 h-3.5" />}
              </button>
            </div>
          )}

          {/* Quick Reload WebView */}
          <button
            onClick={onReload}
            className="p-1.5 rounded-xl hover:bg-white/10 text-white/70 hover:text-white transition"
            title="Reload WebViews"
          >
            <RefreshCw className="w-3.5 h-3.5 text-sky-400" />
          </button>

          {/* WebUI Remote Launcher */}
          {webServerEnabled && onOpenWebUIPortal && (
            <button
              onClick={onOpenWebUIPortal}
              className="flex items-center space-x-1 px-2 py-1 rounded-xl bg-indigo-500/15 hover:bg-indigo-500/25 border border-indigo-500/30 text-indigo-300 text-xs transition active:scale-95"
              title={`Remote Web Server on :${webServerPort}`}
            >
              <Globe className="w-3.5 h-3.5 text-indigo-400" />
              <span className="hidden sm:inline font-mono">:{webServerPort}</span>
            </button>
          )}

          {/* MQTT Inspector Launcher */}
          {mqttEnabled && onOpenMQTTInspector && (
            <button
              onClick={onOpenMQTTInspector}
              className="flex items-center space-x-1 px-2 py-1 rounded-xl bg-emerald-500/15 hover:bg-emerald-500/25 border border-emerald-500/30 text-emerald-300 text-xs transition active:scale-95"
              title="MQTT Home Assistant Entities"
            >
              <Radio className="w-3.5 h-3.5 text-emerald-400" />
              <span className="hidden sm:inline">MQTT</span>
            </button>
          )}

          {/* Voice Satellite Trigger */}
          {isVoiceActive && (
            <button
              onClick={onTriggerVoiceAssistant}
              className="flex items-center space-x-1.5 px-2.5 py-1 rounded-xl bg-purple-500/20 hover:bg-purple-500/30 border border-purple-500/30 text-purple-200 text-xs transition active:scale-95"
              title={`Voice Satellite: ${voiceSatelliteStatus}`}
            >
              <Mic className="w-3.5 h-3.5 text-purple-400 animate-pulse" />
              <span className="hidden sm:inline">Voice</span>
            </button>
          )}

          {/* Inactivity & Screensaver button */}
          <button
            onClick={onTriggerScreensaver}
            className="flex items-center space-x-1.5 px-2.5 py-1 rounded-xl bg-white/10 hover:bg-white/20 border border-white/15 text-xs text-white/90 transition active:scale-95"
            title={`Idle timer: ${inactivitySeconds}s (Mode: ${screensaverMode})`}
          >
            <Clock className="w-3.5 h-3.5 text-indigo-300" />
            <span className="font-mono">{inactivitySeconds}s</span>
          </button>

          {/* Battery Status */}
          <div
            className="flex items-center space-x-1 px-2 py-1 rounded-xl bg-white/5 border border-white/10 text-xs text-white/70"
            title={`Battery: ${batteryLevel}% ${isCharging ? "(Charging)" : ""}`}
          >
            {isCharging ? (
              <BatteryCharging className="w-3.5 h-3.5 text-emerald-400" />
            ) : (
              <Battery className="w-3.5 h-3.5 text-slate-300" />
            )}
            <span className="font-mono text-[11px]">{batteryLevel}%</span>
          </div>

          {/* Settings Trigger */}
          <button
            onClick={onOpenSettings}
            className="p-1.5 rounded-xl hover:bg-white/10 text-white/70 hover:text-white transition"
            title="Open Settings"
          >
            <Sliders className="w-3.5 h-3.5" />
          </button>

          {/* Fullscreen Toggle */}
          <button
            onClick={toggleFullscreen}
            className="p-1.5 rounded-xl hover:bg-white/10 text-white/70 hover:text-white transition"
            title={isFullscreen ? "Exit Fullscreen" : "Enter Fullscreen"}
          >
            {isFullscreen ? <Minimize2 className="w-3.5 h-3.5" /> : <Maximize2 className="w-3.5 h-3.5" />}
          </button>

          {/* Collapse bar */}
          <button
            onClick={() => setCollapsed(true)}
            className="p-1 rounded-lg hover:bg-white/10 text-white/40 hover:text-white/80"
            title="Minimize Bar"
          >
            <ChevronDown className="w-3.5 h-3.5" />
          </button>
        </div>
      )}
    </div>
  );
};
