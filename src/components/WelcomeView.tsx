import React from "react";
import { Settings, Sparkles } from "lucide-react";

interface WelcomeViewProps {
  onOpenSettings: () => void;
}

export const WelcomeView: React.FC<WelcomeViewProps> = ({ onOpenSettings }) => {
  return (
    <div className="relative w-full h-full select-none overflow-hidden flex flex-col justify-center items-center bg-gradient-to-br from-[#667eea] to-[#764ba2] text-white">
      {/* Decorative ambient background glows */}
      <div className="absolute inset-0 pointer-events-none overflow-hidden">
        <div className="absolute -top-1/4 -left-1/4 w-[150%] h-[150%] bg-[radial-gradient(circle_at_30%_70%,rgba(255,255,255,0.12)_0%,transparent_50%),radial-gradient(circle_at_80%_20%,rgba(255,255,255,0.08)_0%,transparent_50%)] animate-pulse" />
      </div>

      <div className="relative z-10 text-center max-w-xl px-6 w-full flex flex-col items-center">
        {/* Title */}
        <h1 className="text-5xl sm:text-6xl md:text-7xl font-extrabold tracking-tight bg-gradient-to-r from-white via-slate-100 to-white bg-clip-text text-transparent drop-shadow-lg mb-6">
          UltraKiosk
        </h1>

        {/* Configuration Card */}
        <div className="bg-white/10 backdrop-blur-md border border-white/20 rounded-2xl p-6 sm:p-8 shadow-2xl text-center max-w-md w-full mx-auto">
          <p className="text-lg sm:text-xl font-medium text-white/95 mb-2">
            Welcome to UltraKiosk
          </p>
          <p className="text-sm sm:text-base text-white/85 leading-relaxed mb-6">
            <span className="text-amber-300 font-semibold">3 x Tap Settings</span> in the top corner to configure your kiosk experience.
          </p>

          <button
            onClick={onOpenSettings}
            className="inline-flex items-center space-x-2 px-5 py-2.5 rounded-xl bg-white/20 hover:bg-white/30 text-white font-medium text-sm transition-all shadow-md active:scale-95 border border-white/30"
          >
            <Settings className="w-4 h-4 text-white" />
            <span>Open Kiosk Settings</span>
          </button>
        </div>

        <p className="text-xs text-white/50 mt-6 flex items-center space-x-1.5">
          <Sparkles className="w-3.5 h-3.5 text-amber-300" />
          <span>Set your primary URL in Settings to begin full-screen kiosk browsing</span>
        </p>
      </div>
    </div>
  );
};
