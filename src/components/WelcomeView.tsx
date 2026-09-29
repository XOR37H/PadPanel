import React from "react";

export const WelcomeView: React.FC = () => {
  return (
    <div className="relative w-full h-full select-none overflow-hidden flex flex-col justify-center items-center bg-gradient-to-br from-[#667eea] to-[#764ba2] text-white">
      {/* Decorative ambient background glows */}
      <div className="absolute inset-0 pointer-events-none overflow-hidden">
        <div className="absolute -top-1/2 -left-1/2 w-[200%] h-[200%] bg-[radial-gradient(circle_at_30%_70%,rgba(255,255,255,0.1)_0%,transparent_50%),radial-gradient(circle_at_80%_20%,rgba(255,255,255,0.05)_0%,transparent_50%)] animate-pulse" />
      </div>

      <div className="relative z-10 text-center max-w-[90%] w-full flex flex-col items-center">
        {/* Title */}
        <h1 className="text-6xl sm:text-7xl md:text-8xl font-extrabold tracking-tight bg-gradient-to-r from-white via-gray-100 to-white bg-clip-text text-transparent drop-shadow-[0_4px_20px_rgba(0,0,0,0.3)] mb-8">
          UltraKiosk
        </h1>

        {/* Configuration Card matching iOS hardware */}
        <div className="bg-white/10 backdrop-blur-md border border-white/20 rounded-2xl p-6 sm:p-8 shadow-2xl text-center max-w-[600px] w-full mx-auto text-white/90 text-base sm:text-lg md:text-xl font-normal leading-relaxed">
          Welcome to UltraKiosk
          <br />
          <span className="text-amber-400 font-semibold">3 x Tap Settings</span> in the top corner to configure your kiosk experience.
        </div>
      </div>
    </div>
  );
};

