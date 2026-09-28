import React, { useState } from "react";
import {
  Lightbulb,
  Thermometer,
  Lock,
  Music,
  Power,
  Zap,
  Wind,
  Droplets,
  Tv,
  Sun,
  Moon,
  Coffee,
  CheckCircle2,
  ExternalLink,
} from "lucide-react";

interface HomeAssistantDemoProps {
  onOpenSettings: () => void;
  kioskUrlText?: string;
}

export const HomeAssistantDemoView: React.FC<HomeAssistantDemoProps> = ({
  onOpenSettings,
}) => {
  // Interactive smart home entity states
  const [lights, setLights] = useState({
    livingRoom: true,
    kitchen: true,
    hallway: false,
    balcony: false,
  });

  const [livingRoomBrightness, setLivingRoomBrightness] = useState<number>(85);
  const [temperature, setTemperature] = useState<number>(21.5);
  const [hvacMode, setHvacMode] = useState<"heat" | "cool" | "off">("heat");
  const [doorLocked, setDoorLocked] = useState<boolean>(true);
  const [isPlaying, setIsPlaying] = useState<boolean>(true);
  const [activeScene, setActiveScene] = useState<string>("Bright Day");

  const toggleLight = (key: keyof typeof lights) => {
    setLights((prev) => ({ ...prev, [key]: !prev[key] }));
  };

  const applyScene = (sceneName: string) => {
    setActiveScene(sceneName);
    if (sceneName === "All Off") {
      setLights({ livingRoom: false, kitchen: false, hallway: false, balcony: false });
      setIsPlaying(false);
    } else if (sceneName === "Movie Night") {
      setLights({ livingRoom: true, kitchen: false, hallway: false, balcony: false });
      setLivingRoomBrightness(25);
      setIsPlaying(true);
    } else if (sceneName === "Bright Day") {
      setLights({ livingRoom: true, kitchen: true, hallway: true, balcony: false });
      setLivingRoomBrightness(95);
    } else if (sceneName === "Relax") {
      setLights({ livingRoom: true, kitchen: false, hallway: true, balcony: false });
      setLivingRoomBrightness(45);
    }
  };

  return (
    <div className="relative w-full h-full overflow-y-auto bg-gradient-to-br from-[#1a1e36] via-[#161a2e] to-[#0f111a] text-white p-4 sm:p-8 flex flex-col justify-between select-none">
      {/* Subtle floating background glow */}
      <div className="absolute inset-0 overflow-hidden pointer-events-none">
        <div className="absolute -top-32 -left-32 w-96 h-96 bg-indigo-600/15 rounded-full blur-3xl animate-pulse"></div>
        <div className="absolute top-1/2 -right-32 w-96 h-96 bg-purple-600/15 rounded-full blur-3xl animate-pulse delay-1000"></div>
        <div className="absolute -bottom-32 left-1/3 w-96 h-96 bg-blue-600/15 rounded-full blur-3xl"></div>
      </div>

      <div className="relative z-10 max-w-6xl mx-auto w-full space-y-6">
        {/* Header Bar */}
        <div className="flex flex-wrap items-center justify-between gap-4 border-b border-white/10 pb-4">
          <div className="flex items-center space-x-3">
            <div className="w-10 h-10 rounded-xl bg-gradient-to-tr from-indigo-500 to-purple-500 flex items-center justify-center shadow-lg shadow-indigo-500/30">
              <Tv className="w-5 h-5 text-white" />
            </div>
            <div>
              <div className="flex items-center space-x-2">
                <h1 className="text-xl sm:text-2xl font-bold tracking-tight text-white">UltraKiosk</h1>
                <span className="text-xs font-semibold px-2 py-0.5 rounded-full bg-indigo-500/20 text-indigo-300 border border-indigo-500/30">
                  Home Assistant Display
                </span>
              </div>
              <p className="text-xs sm:text-sm text-slate-400">
                Wall-Mounted Smart Display · Triple-tap top right corner for settings
              </p>
            </div>
          </div>

          <div className="flex items-center space-x-3">
            <div className="hidden sm:flex items-center space-x-4 px-3 py-1.5 rounded-xl bg-white/5 border border-white/10 text-xs">
              <span className="flex items-center text-emerald-400">
                <span className="w-2 h-2 rounded-full bg-emerald-400 animate-ping mr-1.5"></span>
                Connected
              </span>
              <span className="text-slate-400">21.8°C Flur</span>
              <span className="text-slate-400">420 W</span>
            </div>

            <button
              onClick={onOpenSettings}
              className="px-3.5 py-1.5 rounded-xl bg-white/10 hover:bg-white/20 active:scale-95 transition flex items-center space-x-1.5 text-xs font-medium border border-white/15"
            >
              <span>Settings</span>
              <ExternalLink className="w-3.5 h-3.5 opacity-70" />
            </button>
          </div>
        </div>

        {/* Quick Scenes Row */}
        <div>
          <div className="text-xs font-semibold uppercase tracking-wider text-slate-400 mb-2">
            Active Presets & Scenes
          </div>
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
            {[
              { name: "Bright Day", icon: Sun, color: "from-amber-500/20 to-orange-500/20 border-amber-500/40 text-amber-300" },
              { name: "Movie Night", icon: Tv, color: "from-purple-500/20 to-indigo-500/20 border-purple-500/40 text-purple-300" },
              { name: "Relax", icon: Coffee, color: "from-blue-500/20 to-cyan-500/20 border-blue-500/40 text-blue-300" },
              { name: "All Off", icon: Moon, color: "from-slate-700/20 to-slate-800/20 border-slate-600/40 text-slate-300" },
            ].map((scene) => {
              const Icon = scene.icon;
              const isSelected = activeScene === scene.name;
              return (
                <button
                  key={scene.name}
                  onClick={() => applyScene(scene.name)}
                  className={`p-3 rounded-2xl border text-left transition-all duration-200 flex items-center justify-between ${
                    isSelected
                      ? `bg-gradient-to-r ${scene.color} shadow-lg shadow-indigo-500/10 scale-[1.02]`
                      : "bg-white/5 border-white/10 hover:bg-white/10 text-slate-300"
                  }`}
                >
                  <div className="flex items-center space-x-2.5">
                    <Icon className="w-4 h-4" />
                    <span className="text-sm font-medium">{scene.name}</span>
                  </div>
                  {isSelected && <CheckCircle2 className="w-4 h-4 text-emerald-400" />}
                </button>
              );
            })}
          </div>
        </div>

        {/* Main Smart Home Entity Grid */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          {/* Card 1: Lighting Control */}
          <div className="p-4 sm:p-5 rounded-2xl bg-white/5 border border-white/10 backdrop-blur-md space-y-4">
            <div className="flex items-center justify-between">
              <div className="flex items-center space-x-2">
                <Lightbulb className="w-5 h-5 text-amber-400" />
                <h3 className="font-semibold text-sm sm:text-base">Lighting</h3>
              </div>
              <span className="text-xs px-2 py-0.5 rounded-full bg-white/10 text-slate-300">
                {Object.values(lights).filter(Boolean).length} on
              </span>
            </div>

            <div className="space-y-2.5">
              {[
                { id: "livingRoom", label: "Living Room Main" },
                { id: "kitchen", label: "Kitchen Spotlights" },
                { id: "hallway", label: "Hallway Ambient" },
                { id: "balcony", label: "Balcony LED" },
              ].map((item) => {
                const isOn = lights[item.id as keyof typeof lights];
                return (
                  <div
                    key={item.id}
                    onClick={() => toggleLight(item.id as keyof typeof lights)}
                    className={`flex items-center justify-between p-2.5 rounded-xl cursor-pointer border transition-all ${
                      isOn
                        ? "bg-amber-400/10 border-amber-400/30 text-white"
                        : "bg-white/5 border-white/5 text-slate-400 hover:bg-white/10"
                    }`}
                  >
                    <span className="text-sm font-medium">{item.label}</span>
                    <div
                      className={`w-10 h-6 flex items-center rounded-full p-1 transition duration-300 ${
                        isOn ? "bg-amber-400 justify-end" : "bg-white/20 justify-start"
                      }`}
                    >
                      <div className="w-4 h-4 rounded-full bg-white shadow-md"></div>
                    </div>
                  </div>
                );
              })}
            </div>

            {/* Brightness slider for living room */}
            {lights.livingRoom && (
              <div className="pt-2 border-t border-white/10">
                <div className="flex justify-between text-xs text-slate-400 mb-1">
                  <span>Living Room Brightness</span>
                  <span>{livingRoomBrightness}%</span>
                </div>
                <input
                  type="range"
                  min="5"
                  max="100"
                  value={livingRoomBrightness}
                  onChange={(e) => setLivingRoomBrightness(Number(e.target.value))}
                  className="w-full h-1.5 bg-white/20 rounded-lg appearance-none cursor-pointer accent-amber-400"
                />
              </div>
            )}
          </div>

          {/* Card 2: Climate & Security */}
          <div className="p-4 sm:p-5 rounded-2xl bg-white/5 border border-white/10 backdrop-blur-md space-y-4">
            <div className="flex items-center justify-between">
              <div className="flex items-center space-x-2">
                <Thermometer className="w-5 h-5 text-rose-400" />
                <h3 className="font-semibold text-sm sm:text-base">Climate Control</h3>
              </div>
              <span className="text-xs px-2 py-0.5 rounded-full bg-rose-500/20 text-rose-300 capitalize">
                {hvacMode}
              </span>
            </div>

            {/* Thermostat dial presentation */}
            <div className="flex items-center justify-between p-3 rounded-2xl bg-white/5 border border-white/5">
              <div>
                <div className="text-xs text-slate-400">Current / Target</div>
                <div className="text-3xl font-light tracking-tight text-white">
                  {temperature.toFixed(1)}°C
                </div>
                <div className="text-xs text-slate-400 mt-0.5">Floor Heating Active</div>
              </div>

              <div className="flex flex-col space-y-2">
                <button
                  onClick={() => setTemperature((t) => Math.min(28, +(t + 0.5).toFixed(1)))}
                  className="w-8 h-8 rounded-lg bg-white/10 hover:bg-white/20 flex items-center justify-center font-bold text-lg active:scale-95"
                >
                  +
                </button>
                <button
                  onClick={() => setTemperature((t) => Math.max(16, +(t - 0.5).toFixed(1)))}
                  className="w-8 h-8 rounded-lg bg-white/10 hover:bg-white/20 flex items-center justify-center font-bold text-lg active:scale-95"
                >
                  -
                </button>
              </div>
            </div>

            {/* HVAC Mode selector */}
            <div className="grid grid-cols-3 gap-2">
              {(["heat", "cool", "off"] as const).map((mode) => (
                <button
                  key={mode}
                  onClick={() => setHvacMode(mode)}
                  className={`py-1.5 rounded-lg text-xs font-medium uppercase tracking-wider transition ${
                    hvacMode === mode
                      ? mode === "heat"
                        ? "bg-rose-500 text-white font-bold"
                        : mode === "cool"
                        ? "bg-cyan-500 text-white font-bold"
                        : "bg-slate-600 text-white font-bold"
                      : "bg-white/5 text-slate-400 hover:bg-white/10"
                  }`}
                >
                  {mode}
                </button>
              ))}
            </div>

            {/* Security Lock Entity */}
            <div
              onClick={() => setDoorLocked(!doorLocked)}
              className={`p-3 rounded-xl border cursor-pointer transition flex items-center justify-between ${
                doorLocked
                  ? "bg-emerald-500/10 border-emerald-500/30 text-emerald-300"
                  : "bg-rose-500/10 border-rose-500/30 text-rose-300"
              }`}
            >
              <div className="flex items-center space-x-2.5">
                <Lock className="w-5 h-5" />
                <div>
                  <div className="text-xs text-slate-400">Front Door Lock</div>
                  <div className="text-sm font-semibold">{doorLocked ? "Secured & Locked" : "Unlocked"}</div>
                </div>
              </div>
              <span className="text-xs px-2 py-1 rounded bg-white/10 font-mono">
                {doorLocked ? "SECURE" : "OPEN"}
              </span>
            </div>
          </div>

          {/* Card 3: Media & Environment Telemetry */}
          <div className="p-4 sm:p-5 rounded-2xl bg-white/5 border border-white/10 backdrop-blur-md space-y-4">
            <div className="flex items-center justify-between">
              <div className="flex items-center space-x-2">
                <Music className="w-5 h-5 text-indigo-400" />
                <h3 className="font-semibold text-sm sm:text-base">Media & Sensors</h3>
              </div>
              <span className="text-xs text-slate-400">Sonos Arc</span>
            </div>

            {/* Media Player Card */}
            <div className="p-3 rounded-2xl bg-white/5 border border-white/5 space-y-3">
              <div className="flex items-center space-x-3">
                <div className="w-12 h-12 rounded-xl bg-gradient-to-tr from-indigo-500 to-pink-500 flex items-center justify-center shadow-md">
                  <Music className="w-6 h-6 text-white" />
                </div>
                <div className="flex-1 min-w-0">
                  <div className="text-sm font-medium truncate text-white">Chilled Lounge & Lo-Fi</div>
                  <div className="text-xs text-slate-400 truncate">Home Assistant Radio</div>
                </div>
                <button
                  onClick={() => setIsPlaying(!isPlaying)}
                  className="w-9 h-9 rounded-full bg-white text-slate-900 flex items-center justify-center font-bold hover:scale-105 active:scale-95 transition"
                >
                  <Power className="w-4 h-4" />
                </button>
              </div>

              {/* Progress bar */}
              <div className="space-y-1">
                <div className="w-full bg-white/10 h-1.5 rounded-full overflow-hidden">
                  <div className="bg-indigo-400 h-full w-2/3 rounded-full animate-pulse"></div>
                </div>
                <div className="flex justify-between text-[10px] text-slate-400">
                  <span>2:14</span>
                  <span>3:45</span>
                </div>
              </div>
            </div>

            {/* Live Environment Badges */}
            <div className="grid grid-cols-3 gap-2 pt-1">
              <div className="p-2 rounded-xl bg-white/5 border border-white/5 text-center">
                <Droplets className="w-4 h-4 mx-auto text-blue-400 mb-1" />
                <div className="text-xs text-slate-400">Humidity</div>
                <div className="text-sm font-semibold">46%</div>
              </div>
              <div className="p-2 rounded-xl bg-white/5 border border-white/5 text-center">
                <Wind className="w-4 h-4 mx-auto text-emerald-400 mb-1" />
                <div className="text-xs text-slate-400">Air Quality</div>
                <div className="text-sm font-semibold">18 AQI</div>
              </div>
              <div className="p-2 rounded-xl bg-white/5 border border-white/5 text-center">
                <Zap className="w-4 h-4 mx-auto text-amber-400 mb-1" />
                <div className="text-xs text-slate-400">Power</div>
                <div className="text-sm font-semibold">420 W</div>
              </div>
            </div>
          </div>
        </div>

        {/* Footer info pill */}
        <div className="flex flex-col sm:flex-row items-center justify-between px-4 py-3 rounded-2xl bg-indigo-950/40 border border-indigo-500/20 text-xs text-indigo-200">
          <div className="flex items-center space-x-2">
            <span className="w-2 h-2 rounded-full bg-indigo-400"></span>
            <span>
              <strong>Kiosk Mode Active:</strong> You can load your live Home Assistant dashboard by adding its URL in Settings.
            </span>
          </div>
          <span className="mt-1 sm:mt-0 font-mono text-[11px] text-indigo-300/80">
            e.g. http://homeassistant.local:8123/lovelace/0?kiosk
          </span>
        </div>
      </div>
    </div>
  );
};
