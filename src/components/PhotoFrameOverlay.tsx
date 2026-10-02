import React, { useState, useEffect } from "react";
import { Image as ImageIcon, Sparkles, UserCheck, Bug, BatteryCharging, Battery, AlertTriangle, Loader2 } from "lucide-react";
import { WakeupMethod } from "../types/settings";

interface PhotoFrameOverlayProps {
  photoFrameURL: string;
  photoFrameInterval: number;
  onWake: () => void;
  isFaceDetectionActive: boolean;
  onSimulateFaceWake: () => void;
  motionLevel: number;
  wakeupMethod?: WakeupMethod;
  motionSensitivity?: number;
  showDebugInfo?: boolean;
  batteryLevel?: number;
  isCharging?: boolean;
}

export const PhotoFrameOverlay: React.FC<PhotoFrameOverlayProps> = ({
  photoFrameURL,
  photoFrameInterval,
  onWake,
  isFaceDetectionActive,
  onSimulateFaceWake,
  motionLevel,
  wakeupMethod = "face",
  motionSensitivity = 0.08,
  showDebugInfo = true,
  batteryLevel = 85,
  isCharging = true,
}) => {
  const [imageSrc, setImageSrc] = useState<string>("");
  const [isLoading, setIsLoading] = useState<boolean>(false);
  const [loadFailed, setLoadFailed] = useState<boolean>(false);

  const cleanURL = photoFrameURL.trim();

  // Load and refresh image
  useEffect(() => {
    if (!cleanURL) {
      setImageSrc("");
      setLoadFailed(false);
      setIsLoading(false);
      return;
    }

    const fetchImage = () => {
      setIsLoading(true);
      const cacheBuster = `_cb=${Date.now()}`;
      const finalUrl = cleanURL.includes("?")
        ? `${cleanURL}&${cacheBuster}`
        : `${cleanURL}?${cacheBuster}`;

      const img = new Image();
      img.onload = () => {
        setImageSrc(finalUrl);
        setIsLoading(false);
        setLoadFailed(false);
      };
      img.onerror = () => {
        setIsLoading(false);
        setLoadFailed(true);
      };
      img.src = finalUrl;
    };

    fetchImage();
    const intervalSec = Math.max(5, photoFrameInterval);
    const timer = setInterval(fetchImage, intervalSec * 1000);

    return () => clearInterval(timer);
  }, [cleanURL, photoFrameInterval]);

  const thresholdPercent = Math.round(motionSensitivity * 100);

  return (
    <div
      onClick={onWake}
      onTouchStart={onWake}
      className="absolute inset-0 bg-black z-40 flex flex-col items-center justify-center p-6 text-center select-none cursor-pointer transition-opacity duration-700"
    >
      {/* Top telemetry debug overlay */}
      {showDebugInfo && (
        <div
          onClick={(e) => e.stopPropagation()}
          className="absolute top-4 left-4 right-4 flex items-center justify-between pointer-events-none z-50"
        >
          <div className="flex items-center space-x-2 px-3 py-1.5 rounded-xl bg-black/60 backdrop-blur-md border border-white/10 text-[11px] font-mono text-slate-300">
            <Bug className="w-3.5 h-3.5 text-indigo-400 shrink-0" />
            <span className="capitalize">{wakeupMethod} Wakeup</span>
            <span className="text-slate-500">|</span>
            <span>Sens: {thresholdPercent}%</span>
            <span className="text-slate-500">|</span>
            <span className={motionLevel >= thresholdPercent ? "text-emerald-400 font-bold" : "text-slate-400"}>
              Live Motion: {motionLevel}%
            </span>
          </div>

          <div className="flex items-center space-x-2 px-3 py-1.5 rounded-xl bg-black/60 backdrop-blur-md border border-white/10 text-[11px] font-mono text-slate-300">
            {isCharging ? (
              <BatteryCharging className="w-3.5 h-3.5 text-emerald-400 shrink-0" />
            ) : (
              <Battery className="w-3.5 h-3.5 text-slate-400 shrink-0" />
            )}
            <span>{batteryLevel}%</span>
          </div>
        </div>
      )}

      {/* Main Image or Placeholder */}
      <div className="w-full h-full flex items-center justify-center relative">
        {imageSrc && !loadFailed ? (
          <img
            src={imageSrc}
            alt="Photo Frame"
            className="max-w-full max-h-full object-contain transition-opacity duration-500"
          />
        ) : !cleanURL ? (
          <div className="flex flex-col items-center space-y-4 max-w-md p-8 rounded-2xl bg-slate-900/60 border border-slate-800 text-slate-300">
            <ImageIcon className="w-16 h-16 text-slate-500" />
            <div className="text-xl font-medium text-white">Photo Frame Screensaver</div>
            <p className="text-xs text-slate-400 leading-relaxed">
              Configure Photo Frame Image URL in Settings &gt; Display &gt; Photo frame or Remote WebUI to display rotating images, camera snapshots, or artwork.
            </p>
          </div>
        ) : isLoading && !imageSrc ? (
          <div className="flex flex-col items-center space-y-3 text-slate-400">
            <Loader2 className="w-8 h-8 text-indigo-400 animate-spin" />
            <span className="text-sm font-medium text-slate-300">Loading photo frame...</span>
          </div>
        ) : (
          <div className="flex flex-col items-center space-y-3 max-w-md p-6 rounded-2xl bg-rose-950/20 border border-rose-500/30 text-rose-300">
            <AlertTriangle className="w-10 h-10 text-rose-400" />
            <div className="text-base font-semibold text-white">Unable to Load Image from URL</div>
            <p className="text-xs font-mono text-slate-400 break-all px-4">{cleanURL}</p>
            <p className="text-[11px] text-slate-500">Tap screen to wake or update URL endpoint.</p>
          </div>
        )}
      </div>

      {/* Bottom Wake Controls & Simulation */}
      <div
        className="absolute bottom-6 left-0 right-0 flex flex-col items-center space-y-3 z-50"
        onClick={(e) => e.stopPropagation()}
      >
        {isFaceDetectionActive && (
          <div className="flex items-center space-x-2.5 px-4 py-1.5 rounded-full bg-black/70 backdrop-blur border border-white/10 text-slate-300 text-xs">
            <div className="w-3 h-3 border-2 border-white/20 border-t-white rounded-full animate-spin"></div>
            <span>
              {wakeupMethod === "face" ? "Face detection active..." : "Motion detection active..."}
            </span>
          </div>
        )}

        <div className="flex items-center space-x-3">
          <button
            onClick={onSimulateFaceWake}
            className="px-4 py-1.5 rounded-xl bg-white/10 hover:bg-white/20 active:scale-95 text-xs font-medium text-slate-300 border border-white/15 flex items-center space-x-2 transition"
          >
            <UserCheck className="w-3.5 h-3.5 text-emerald-400" />
            <span>Simulate {wakeupMethod === "face" ? "Face" : "Motion"} Wake</span>
          </button>
          <div className="text-[11px] text-slate-500 flex items-center space-x-1">
            <Sparkles className="w-3 h-3 text-slate-500" />
            <span>Tap screen to return</span>
          </div>
        </div>
      </div>
    </div>
  );
};
