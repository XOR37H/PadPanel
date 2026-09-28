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
} from "lucide-react";

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
  batteryLevel: number;
  isCharging: boolean;
  isVoiceActive: boolean;
  voiceSatelliteStatus: string;
  onTriggerVoiceAssistant: () => void;
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
  batteryLevel,
  isCharging,
  isVoiceActive,
  voiceSatelliteStatus,
  onTriggerVoiceAssistant,
}) => {
  const [isFullscreen, setIsFullscreen] = useState<boolean>(false);
  const [collapsed, setCollapsed] = useState<boolean>(false);

  // Fullscreen with WebKit prefix support for iPadOS 15 Safari
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
        <div className="flex flex-wrap items-center gap-2 p-1.5 px-3 rounded-2xl bg-black/70 hover:bg-black/85 backdrop-blur-lg border border-white/15 text-white shadow-2xl transition duration-300">
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
            className="flex items-center space-x-1.5 px-2.5 py-1 rounded-xl bg-white/5 hover:bg-white/15 text-xs text-slate-300 transition"
            title="Click to activate screensaver now"
          >
            <Clock className="w-3.5 h-3.5 text-amber-400" />
            <span className="font-mono text-[11px]">{inactivitySeconds}s</span>
          </button>

          {/* Battery Status */}
          <div className="flex items-center space-x-1 text-xs text-slate-400 px-1.5">
            {isCharging ? (
              <BatteryCharging className="w-3.5 h-3.5 text-emerald-400" />
            ) : (
              <Battery className="w-3.5 h-3.5 text-slate-300" />
            )}
            <span className="text-[11px] font-mono">{batteryLevel}%</span>
          </div>

          {/* Fullscreen Toggle */}
          <button
            onClick={toggleFullscreen}
            className="p-1 rounded-lg hover:bg-white/10 text-white/70 hover:text-white"
            title="Toggle Kiosk Fullscreen (supports iPadOS 15)"
          >
            {isFullscreen ? <Minimize2 className="w-3.5 h-3.5" /> : <Maximize2 className="w-3.5 h-3.5" />}
          </button>

          {/* Collapse button */}
          <button
            onClick={() => setCollapsed(true)}
            className="p-1 rounded-lg hover:bg-white/10 text-white/40 hover:text-white"
            title="Collapse control bar"
          >
            <ChevronDown className="w-3.5 h-3.5" />
          </button>
        </div>
      )}
    </div>
  );
};
