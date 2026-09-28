import React, { useState, useEffect } from "react";
import { Eye, Sparkles, UserCheck } from "lucide-react";

interface ScreensaverViewProps {
  onWake: () => void;
  isFaceDetectionActive: boolean;
  onSimulateFaceWake: () => void;
  motionLevel: number;
}

export const ScreensaverView: React.FC<ScreensaverViewProps> = ({
  onWake,
  isFaceDetectionActive,
  onSimulateFaceWake,
  motionLevel,
}) => {
  const [currentTime, setCurrentTime] = useState<Date>(new Date());

  useEffect(() => {
    const timer = setInterval(() => {
      setCurrentTime(new Date());
    }, 1000);
    return () => clearInterval(timer);
  }, []);

  const timeString = currentTime.toLocaleTimeString([], {
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  });

  const dateString = currentTime.toLocaleDateString(undefined, {
    weekday: "long",
    month: "long",
    day: "numeric",
    year: "numeric",
  });

  return (
    <div
      onClick={onWake}
      onTouchStart={onWake}
      className="absolute inset-0 bg-black z-40 flex flex-col items-center justify-center p-6 text-center select-none cursor-pointer transition-opacity duration-700"
    >
      <div className="space-y-6 max-w-xl mx-auto">
        {/* Huge thin clock matching iOS ScreensaverView */}
        <div className="text-6xl sm:text-8xl md:text-9xl font-extralight tracking-tight text-white font-mono drop-shadow-sm">
          {timeString}
        </div>

        {/* Date string */}
        <div className="text-lg sm:text-2xl md:text-3xl font-light text-slate-400 tracking-wide">
          {dateString}
        </div>

        {/* Face detection status indicator matching iOS progress view */}
        {isFaceDetectionActive && (
          <div className="pt-8 flex flex-col items-center space-y-2">
            <div className="flex items-center space-x-2.5 px-4 py-1.5 rounded-full bg-white/5 border border-white/10 text-slate-400 text-sm">
              <div className="w-3.5 h-3.5 border-2 border-white/20 border-t-white rounded-full animate-spin"></div>
              <span>Face detection active...</span>
              {motionLevel > 0 && (
                <span className="text-xs text-indigo-400 font-mono">
                  {motionLevel}% motion
                </span>
              )}
            </div>
            <p className="text-xs text-slate-500">
              Approaching the iPad camera automatically wakes the display
            </p>
          </div>
        )}

        {/* Interactive test trigger & instructions */}
        <div className="pt-10 flex flex-col items-center space-y-3" onClick={(e) => e.stopPropagation()}>
          <button
            onClick={onSimulateFaceWake}
            className="px-4 py-2 rounded-xl bg-white/10 hover:bg-white/20 active:scale-95 text-xs font-medium text-slate-300 border border-white/15 flex items-center space-x-2 transition"
          >
            <UserCheck className="w-4 h-4 text-emerald-400" />
            <span>Simulate Face / Motion Wake</span>
          </button>
          <div className="text-[11px] text-slate-600 flex items-center space-x-1">
            <Sparkles className="w-3 h-3 text-slate-500" />
            <span>Tap screen anywhere to return to kiosk</span>
          </div>
        </div>
      </div>
    </div>
  );
};
