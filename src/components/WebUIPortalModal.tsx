import React, { useState } from "react";
import { PadPanelSettings, ScreensaverMode, WakeupMethod } from "../types/settings";
import {
  X,
  Globe,
  Lock,
  Unlock,
  RefreshCw,
  Power,
  Sun,
  Eye,
  EyeOff,
  Camera,
  Sliders,
  Save,
  CheckCircle,
  Terminal,
  Server,
  Activity,
  Battery,
  BatteryCharging,
  Radio,
  Layers,
  User,
  Zap,
  Moon,
} from "lucide-react";

interface WebUIPortalModalProps {
  isOpen: boolean;
  onClose: () => void;
  settings: PadPanelSettings;
  onSaveSettings: (newSettings: PadPanelSettings) => void;
  onLiveSettingChange?: (key: keyof PadPanelSettings, value: any) => void;
  onTriggerAction: (action: "screensaver" | "wakeup" | "reload" | "sleep") => void;
  isScreensaverActive: boolean;
  batteryLevel: number;
  isCharging: boolean;
  inactivitySecondsLeft: number;
}

export const WebUIPortalModal: React.FC<WebUIPortalModalProps> = ({
  isOpen,
  onClose,
  settings,
  onSaveSettings,
  onLiveSettingChange,
  onTriggerAction,
  isScreensaverActive,
  batteryLevel,
  isCharging,
  inactivitySecondsLeft,
}) => {
  const adminPassword = settings.deviceAdminPassword || settings.webServerPassword || "";
  const adminUsername = settings.deviceAdminUsername || settings.webServerUsername || "admin";

  const [isAuthenticated, setIsAuthenticated] = useState<boolean>(!adminPassword);
  const [enteredUsername, setEnteredUsername] = useState<string>(adminUsername);
  const [enteredPassword, setEnteredPassword] = useState<string>("");
  const [showPassword, setShowPassword] = useState<boolean>(false);
  const [authError, setAuthError] = useState<string | null>(null);

  // Form state for remote settings editing
  const [form, setForm] = useState<PadPanelSettings>({ ...settings });
  const [saveSuccessMsg, setSaveSuccessMsg] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState<"dashboard" | "settings" | "api">("dashboard");

  // Keep form in sync when modal opens
  React.useEffect(() => {
    if (isOpen) {
      setForm({ ...settings, slideshowURLs: [...settings.slideshowURLs] });
      setIsAuthenticated(!adminPassword);
      setEnteredUsername(adminUsername);
      setEnteredPassword("");
      setShowPassword(false);
      setAuthError(null);
      setSaveSuccessMsg(null);
    }
  }, [isOpen, settings, adminPassword, adminUsername]);

  if (!isOpen) return null;

  const handleLogin = (e: React.FormEvent) => {
    e.preventDefault();
    const isUserValid = !adminUsername || enteredUsername.trim().toLowerCase() === adminUsername.trim().toLowerCase();
    const isPassValid = enteredPassword === adminPassword;

    if (isUserValid && isPassValid) {
      setIsAuthenticated(true);
      setAuthError(null);
    } else {
      setAuthError("Authentication failed: Invalid username or password.");
    }
  };

  // Real-time brightness & setting slider handler
  const handleBrightnessChange = (key: "screenBrightnessDimmed" | "screenBrightnessNormal", val: number) => {
    setForm((prev) => ({ ...prev, [key]: val }));
    if (onLiveSettingChange) {
      onLiveSettingChange(key, val);
    }
  };

  const handleLiveSliderChange = (key: keyof PadPanelSettings, val: any) => {
    setForm((prev) => ({ ...prev, [key]: val }));
    if (onLiveSettingChange) {
      onLiveSettingChange(key, val);
    }
  };

  const handleRemoteSave = (e: React.FormEvent) => {
    e.preventDefault();
    onSaveSettings(form);
    setSaveSuccessMsg("Settings saved via Remote WebUI API (POST /api/settings)");
    setTimeout(() => setSaveSuccessMsg(null), 3500);
  };

  const currentHost = typeof window !== "undefined" ? window.location.hostname : "192.168.1.150";
  const webServerAddress = `http://${currentHost}:${settings.webServerPort}`;

  // Simulated status JSON
  const statusJson = {
    app: "PadPanel",
    version: "1.0.0",
    platform: "iOS 15 / Web",
    webServer: {
      enabled: settings.enableWebServer,
      port: settings.webServerPort,
      authRequired: Boolean(adminPassword),
      username: adminUsername,
    },
    display: {
      screensaverActive: isScreensaverActive,
      screensaverMode: settings.screensaverMode,
      inactivitySecondsLeft,
      screensaverTimeout: settings.screensaverTimeout,
      screenBrightnessNormal: form.screenBrightnessNormal,
      screenBrightnessDimmed: form.screenBrightnessDimmed,
    },
    camera: {
      wakeupMethod: settings.wakeupMethod,
      motionSensitivity: settings.motionSensitivity,
      faceDetectionInterval: settings.faceDetectionInterval,
      showDebugInfo: settings.showDebugInfo,
    },
    battery: {
      level: batteryLevel,
      charging: isCharging,
      batteryUpdateInterval: settings.mqttBatteryUpdateInterval,
    },
    mqtt: {
      enabled: settings.enableMQTT,
      broker: `${settings.mqttBrokerIP}:${settings.mqttPort}`,
      topicPrefix: settings.mqttTopicPrefix,
    },
    autoRefresh: {
      enabled: settings.enableAutoRefresh,
      interval: settings.autoRefreshInterval,
    },
    slideshow: {
      urlCount: settings.slideshowURLs.length,
      interval: settings.slideshowInterval,
    },
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-3 sm:p-6 bg-black/80 backdrop-blur-md">
      <div className="relative w-full max-w-4xl max-h-[92vh] bg-slate-900 border border-slate-700/80 rounded-3xl shadow-2xl flex flex-col overflow-hidden text-slate-100 font-sans animate-in fade-in zoom-in-95 duration-200">
        
        {/* Browser Mockup Chrome Bar */}
        <div className="flex items-center justify-between px-4 py-3 bg-slate-950/90 border-b border-slate-800">
          <div className="flex items-center space-x-3">
            <div className="flex space-x-1.5">
              <div className="w-3 h-3 rounded-full bg-red-500/80" />
              <div className="w-3 h-3 rounded-full bg-yellow-500/80" />
              <div className="w-3 h-3 rounded-full bg-green-500/80" />
            </div>
            <div className="flex items-center space-x-2 px-3 py-1 bg-slate-900 rounded-lg border border-slate-800 text-xs font-mono text-slate-400 max-w-sm sm:max-w-md truncate">
              <Globe className="w-3.5 h-3.5 text-indigo-400 shrink-0" />
              <span className="text-slate-200">{webServerAddress}</span>
              <span className="text-slate-500 hidden sm:inline"> — Embedded Remote WebUI</span>
            </div>
          </div>
          <button
            onClick={onClose}
            className="p-1.5 rounded-lg text-slate-400 hover:text-white hover:bg-slate-800 transition"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Content */}
        {!isAuthenticated ? (
          <div className="flex-1 p-8 flex flex-col items-center justify-center max-w-md mx-auto text-center">
            <div className="w-14 h-14 rounded-2xl bg-indigo-500/10 border border-indigo-500/20 flex items-center justify-center mb-4">
              <Lock className="w-7 h-7 text-indigo-400" />
            </div>
            <h2 className="text-xl font-bold text-white mb-1">PadPanel Remote Admin</h2>
            <p className="text-xs text-slate-400 mb-6">
              Enter the administrator credentials configured in PadPanel Device Authentication.
            </p>

            <form onSubmit={handleLogin} className="w-full space-y-4 text-left">
              <div>
                <label className="block text-xs font-medium text-slate-300 mb-1">Username</label>
                <div className="relative">
                  <input
                    type="text"
                    value={enteredUsername}
                    onChange={(e) => setEnteredUsername(e.target.value)}
                    placeholder="admin"
                    className="w-full px-4 py-2.5 rounded-xl bg-slate-950 border border-slate-700 text-xs focus:outline-none focus:border-indigo-500 text-white font-mono"
                  />
                  <User className="w-4 h-4 text-slate-500 absolute right-3.5 top-1/2 -translate-y-1/2" />
                </div>
              </div>

              <div>
                <label className="block text-xs font-medium text-slate-300 mb-1">Password</label>
                <div className="relative">
                  <input
                    type={showPassword ? "text" : "password"}
                    placeholder="Enter password..."
                    value={enteredPassword}
                    onChange={(e) => setEnteredPassword(e.target.value)}
                    className="w-full px-4 py-2.5 pr-10 rounded-xl bg-slate-950 border border-slate-700 text-xs focus:outline-none focus:border-indigo-500 text-white"
                    autoFocus
                  />
                  <button
                    type="button"
                    onClick={() => setShowPassword(!showPassword)}
                    className="absolute right-3 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-200"
                  >
                    {showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                  </button>
                </div>
              </div>

              {authError && (
                <div className="text-xs text-rose-400 bg-rose-500/10 border border-rose-500/20 rounded-lg p-2.5">
                  {authError}
                </div>
              )}

              <button
                type="submit"
                className="w-full py-2.5 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white font-medium text-sm transition shadow-lg shadow-indigo-600/20"
              >
                Sign In to Remote WebUI
              </button>
            </form>
          </div>
        ) : (
          <div className="flex-1 flex flex-col overflow-hidden">
            {/* Nav Tabs */}
            <div className="flex items-center justify-between px-6 py-2.5 bg-slate-950/60 border-b border-slate-800 text-xs">
              <div className="flex space-x-2">
                <button
                  onClick={() => setActiveTab("dashboard")}
                  className={`px-3 py-1.5 rounded-lg font-medium transition flex items-center space-x-1.5 ${
                    activeTab === "dashboard"
                      ? "bg-indigo-600 text-white"
                      : "text-slate-400 hover:text-white hover:bg-slate-800"
                  }`}
                >
                  <Activity className="w-3.5 h-3.5" />
                  <span>Dashboard & Remote Controls</span>
                </button>
                <button
                  onClick={() => setActiveTab("settings")}
                  className={`px-3 py-1.5 rounded-lg font-medium transition flex items-center space-x-1.5 ${
                    activeTab === "settings"
                      ? "bg-indigo-600 text-white"
                      : "text-slate-400 hover:text-white hover:bg-slate-800"
                  }`}
                >
                  <Sliders className="w-3.5 h-3.5" />
                  <span>Remote Settings (Real-time)</span>
                </button>
                <button
                  onClick={() => setActiveTab("api")}
                  className={`px-3 py-1.5 rounded-lg font-medium transition flex items-center space-x-1.5 ${
                    activeTab === "api"
                      ? "bg-indigo-600 text-white"
                      : "text-slate-400 hover:text-white hover:bg-slate-800"
                  }`}
                >
                  <Terminal className="w-3.5 h-3.5" />
                  <span>REST API (/api/status)</span>
                </button>
              </div>

              {adminPassword && (
                <button
                  onClick={() => setIsAuthenticated(false)}
                  className="text-xs text-slate-400 hover:text-slate-200 flex items-center space-x-1"
                >
                  <Lock className="w-3 h-3" />
                  <span>Lock</span>
                </button>
              )}
            </div>

            {saveSuccessMsg && (
              <div className="bg-emerald-500/15 border-b border-emerald-500/30 px-6 py-2 text-xs text-emerald-300 flex items-center space-x-2">
                <CheckCircle className="w-4 h-4 text-emerald-400 shrink-0" />
                <span>{saveSuccessMsg}</span>
              </div>
            )}

            {/* Tab Body */}
            <div className="flex-1 overflow-y-auto p-6 space-y-6">
              {activeTab === "dashboard" && (
                <div className="space-y-6">
                  {/* Status Banner */}
                  <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
                    <div className="p-4 rounded-xl bg-slate-950/70 border border-slate-800">
                      <div className="text-xs text-slate-400 mb-1 flex items-center justify-between">
                        <span>Screensaver</span>
                        <Power className="w-3.5 h-3.5 text-indigo-400" />
                      </div>
                      <div className="text-lg font-bold text-white">
                        {isScreensaverActive ? (
                          <span className="text-amber-400">Active ({settings.screensaverMode})</span>
                        ) : (
                          <span className="text-emerald-400">Awake</span>
                        )}
                      </div>
                      <div className="text-[11px] text-slate-500 mt-1">
                        Inactivity: {inactivitySecondsLeft}s left
                      </div>
                    </div>

                    <div className="p-4 rounded-xl bg-slate-950/70 border border-slate-800">
                      <div className="text-xs text-slate-400 mb-1 flex items-center justify-between">
                        <span>Battery</span>
                        {isCharging ? (
                          <BatteryCharging className="w-3.5 h-3.5 text-emerald-400" />
                        ) : (
                          <Battery className="w-3.5 h-3.5 text-slate-400" />
                        )}
                      </div>
                      <div className="text-lg font-bold text-white">{batteryLevel}%</div>
                      <div className="text-[11px] text-slate-500 mt-1">
                        {isCharging ? "Charging" : "On Battery"}
                      </div>
                    </div>

                    <div className="p-4 rounded-xl bg-slate-950/70 border border-slate-800">
                      <div className="text-xs text-slate-400 mb-1 flex items-center justify-between">
                        <span>Wakeup Method</span>
                        <Camera className="w-3.5 h-3.5 text-indigo-400" />
                      </div>
                      <div className="text-lg font-bold capitalize text-white">
                        {settings.wakeupMethod} Detection
                      </div>
                      <div className="text-[11px] text-slate-500 mt-1">
                        Sens: {settings.motionSensitivity} ({Math.round(settings.motionSensitivity * 100)}%)
                      </div>
                    </div>

                    <div className="p-4 rounded-xl bg-slate-950/70 border border-slate-800">
                      <div className="text-xs text-slate-400 mb-1 flex items-center justify-between">
                        <span>Brightness</span>
                        <Sun className="w-3.5 h-3.5 text-amber-400" />
                      </div>
                      <div className="text-lg font-bold text-white">
                        {Math.round((isScreensaverActive ? form.screenBrightnessDimmed : form.screenBrightnessNormal) * 100)}%
                      </div>
                      <div className="text-[11px] text-slate-500 mt-1">
                        Norm: {Math.round(form.screenBrightnessNormal * 100)}% / Dim: {Math.round(form.screenBrightnessDimmed * 100)}%
                      </div>
                    </div>
                  </div>

                  {/* Remote Action Buttons */}
                  <div className="p-5 rounded-2xl bg-slate-950/50 border border-slate-800">
                    <h3 className="text-sm font-semibold text-white mb-3 flex items-center space-x-2">
                      <Zap className="w-4 h-4 text-indigo-400" />
                      <span>Quick triggers</span>
                    </h3>
                    <div className="grid grid-cols-2 sm:grid-cols-5 gap-2.5">
                      <button
                        onClick={() => onTriggerAction("screensaver")}
                        className="p-3 rounded-xl bg-slate-900 hover:bg-slate-800 active:scale-95 border border-slate-700/80 text-left transition flex items-center space-x-2.5"
                      >
                        <Power className="w-4 h-4 text-amber-400 shrink-0" />
                        <span className="text-xs font-semibold text-white">Screensaver</span>
                      </button>

                      <button
                        onClick={() => onTriggerAction("sleep")}
                        className="p-3 rounded-xl bg-slate-900 hover:bg-slate-800 active:scale-95 border border-slate-700/80 text-left transition flex items-center space-x-2.5"
                      >
                        <Moon className="w-4 h-4 text-purple-400 shrink-0" />
                        <span className="text-xs font-semibold text-white">Sleep</span>
                      </button>

                      <button
                        onClick={() => onTriggerAction("wakeup")}
                        className="p-3 rounded-xl bg-slate-900 hover:bg-slate-800 active:scale-95 border border-slate-700/80 text-left transition flex items-center space-x-2.5"
                      >
                        <Sun className="w-4 h-4 text-emerald-400 shrink-0" />
                        <span className="text-xs font-semibold text-white">Wake</span>
                      </button>

                      <a
                        href={`${webServerAddress}/api/screenshot?token=padpanel`}
                        target="_blank"
                        rel="noreferrer"
                        className="p-3 rounded-xl bg-slate-900 hover:bg-slate-800 active:scale-95 border border-slate-700/80 text-left transition flex items-center space-x-2.5"
                      >
                        <Camera className="w-4 h-4 text-sky-400 shrink-0" />
                        <span className="text-xs font-semibold text-white">Screenshot</span>
                      </a>

                      <button
                        onClick={() => onTriggerAction("reload")}
                        className="p-3 rounded-xl bg-slate-900 hover:bg-slate-800 active:scale-95 border border-slate-700/80 text-left transition flex items-center space-x-2.5"
                      >
                        <RefreshCw className="w-4 h-4 text-blue-400 shrink-0" />
                        <span className="text-xs font-semibold text-white">Reload pages</span>
                      </button>
                    </div>
                  </div>

                  {/* Configured Dashboard Details */}
                  <div className="p-5 rounded-2xl bg-slate-950/50 border border-slate-800 space-y-3">
                    <h3 className="text-sm font-semibold text-white flex items-center space-x-2">
                      <Layers className="w-4 h-4 text-indigo-400" />
                      <span>Active Dashboard & Slideshow Config</span>
                    </h3>
                    <div className="text-xs text-slate-300">
                      <span className="text-slate-500">Primary URL:</span>{" "}
                      <code className="bg-slate-900 px-2 py-0.5 rounded border border-slate-800 text-indigo-300">
                        {settings.kioskURL || "Built-in PadPanel Demo Dashboard"}
                      </code>
                    </div>
                    {settings.slideshowURLs.length > 0 && (
                      <div className="space-y-1">
                        <div className="text-xs text-slate-500">
                          Slideshow URLs ({settings.slideshowURLs.length} configured, interval: {settings.slideshowInterval}s):
                        </div>
                        <ul className="space-y-1 text-xs font-mono text-slate-400 pl-2">
                          {settings.slideshowURLs.map((url, i) => (
                            <li key={i} className="truncate">
                              {i + 1}. {url}
                            </li>
                          ))}
                        </ul>
                      </div>
                    )}
                  </div>
                </div>
              )}

              {activeTab === "settings" && (
                <form onSubmit={handleRemoteSave} className="space-y-6">
                  {/* Real-time Brightness & Screensaver Section */}
                  <div className="p-5 rounded-2xl bg-slate-950/50 border border-slate-800 space-y-4">
                    <div className="flex items-center justify-between">
                      <div>
                        <h3 className="text-sm font-semibold text-white">Display Brightness (Real-time Live Updating)</h3>
                        <p className="text-[11px] text-slate-400">Adjusting sliders updates the screen brightness instantly on device.</p>
                      </div>
                      <span className="text-[10px] uppercase font-mono px-2 py-0.5 rounded-full bg-emerald-500/20 text-emerald-300 border border-emerald-500/30">
                        Live Sync
                      </span>
                    </div>
                    
                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-5">
                      {/* Normal Brightness Slider */}
                      <div className="p-4 rounded-xl bg-slate-900/80 border border-slate-800">
                        <div className="flex justify-between items-center mb-1.5">
                          <label className="text-xs font-medium text-slate-300 flex items-center space-x-1.5">
                            <Sun className="w-3.5 h-3.5 text-amber-400" />
                            <span>Normal Brightness</span>
                          </label>
                          <span className="text-xs font-mono font-bold text-amber-400">
                            {Math.round(form.screenBrightnessNormal * 100)}%
                          </span>
                        </div>
                        <input
                          type="range"
                          min="0.3"
                          max="1.0"
                          step="0.05"
                          value={form.screenBrightnessNormal}
                          onChange={(e) => handleBrightnessChange("screenBrightnessNormal", Number(e.target.value))}
                          className="w-full accent-amber-500"
                        />
                        <div className="flex justify-between text-[10px] text-slate-500 font-mono mt-1">
                          <span>30%</span>
                          <span>70% (Default)</span>
                          <span>100%</span>
                        </div>
                      </div>

                      {/* Dimmed Brightness Slider */}
                      <div className="p-4 rounded-xl bg-slate-900/80 border border-slate-800">
                        <div className="flex justify-between items-center mb-1.5">
                          <label className="text-xs font-medium text-slate-300 flex items-center space-x-1.5">
                            <Power className="w-3.5 h-3.5 text-indigo-400" />
                            <span>Dimmed Brightness</span>
                          </label>
                          <span className="text-xs font-mono font-bold text-indigo-400">
                            {Math.round(form.screenBrightnessDimmed * 100)}%
                          </span>
                        </div>
                        <input
                          type="range"
                          min="0.05"
                          max="0.8"
                          step="0.05"
                          value={form.screenBrightnessDimmed}
                          onChange={(e) => handleBrightnessChange("screenBrightnessDimmed", Number(e.target.value))}
                          className="w-full accent-indigo-500"
                        />
                        <div className="flex justify-between text-[10px] text-slate-500 font-mono mt-1">
                          <span>5% (Deep Dim)</span>
                          <span>20% (Default)</span>
                          <span>80%</span>
                        </div>
                      </div>
                    </div>

                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 pt-2">
                      <div>
                        <label className="block text-xs text-slate-400 mb-1">Screensaver Mode</label>
                        <select
                          value={form.screensaverMode}
                          onChange={(e) => handleLiveSliderChange("screensaverMode", e.target.value as ScreensaverMode)}
                          className="w-full px-3 py-2 rounded-xl bg-slate-900 border border-slate-700 text-xs text-white focus:outline-none focus:border-indigo-500"
                        >
                          <option value="clock">Clock & Date (Normal Screensaver)</option>
                          <option value="dimming">Dim Only (Keep Dashboard Visible)</option>
                          <option value="urls">Cycle Dashboard URLs</option>
                          <option value="off">Off (Never Sleep/Screensaver)</option>
                        </select>
                      </div>

                      <div>
                        <div className="flex justify-between items-center mb-1">
                          <label className="text-xs text-slate-400">Inactivity Timeout</label>
                          <span className="text-xs font-mono text-indigo-400">{form.screensaverTimeout}s</span>
                        </div>
                        <input
                          type="range"
                          min="10"
                          max="600"
                          step="10"
                          value={form.screensaverTimeout}
                          onChange={(e) => handleLiveSliderChange("screensaverTimeout", Number(e.target.value))}
                          className="w-full accent-indigo-500"
                        />
                      </div>
                    </div>
                  </div>

                  {/* Motion & Wakeup Section */}
                  <div className="p-5 rounded-2xl bg-slate-950/50 border border-slate-800 space-y-4">
                    <h3 className="text-sm font-semibold text-white">Motion & Wakeup Detection</h3>
                    
                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                      <div>
                        <label className="block text-xs text-slate-400 mb-1">Wakeup Method</label>
                        <select
                          value={form.wakeupMethod}
                          onChange={(e) => handleLiveSliderChange("wakeupMethod", e.target.value as WakeupMethod)}
                          className="w-full px-3 py-2 rounded-xl bg-slate-900 border border-slate-700 text-xs text-white focus:outline-none focus:border-indigo-500"
                        >
                          <option value="face">Face Detection (Local Camera)</option>
                          <option value="motion">Motion Detection (Optical Diff)</option>
                        </select>
                      </div>

                      <div>
                        <div className="flex justify-between items-center mb-1">
                          <label className="text-xs text-slate-400">Motion Sensitivity</label>
                          <span className="text-xs font-mono text-indigo-400">
                            {form.motionSensitivity} ({form.motionSensitivity <= 0.04 ? "High" : form.motionSensitivity <= 0.12 ? "Medium" : "Low"})
                          </span>
                        </div>
                        <input
                          type="range"
                          min="0.02"
                          max="0.25"
                          step="0.01"
                          value={form.motionSensitivity}
                          onChange={(e) => handleLiveSliderChange("motionSensitivity", Number(e.target.value))}
                          className="w-full accent-indigo-500"
                        />
                      </div>

                      <div className="flex items-center space-x-2 pt-2">
                        <input
                          type="checkbox"
                          id="webui-debug"
                          checked={form.showDebugInfo}
                          onChange={(e) => handleLiveSliderChange("showDebugInfo", e.target.checked)}
                          className="w-4 h-4 rounded accent-indigo-500"
                        />
                        <label htmlFor="webui-debug" className="text-xs text-slate-300">
                          Show Camera Debug Telemetry Overlay
                        </label>
                      </div>

                      <div className="flex items-center space-x-2 pt-2">
                        <input
                          type="checkbox"
                          id="webui-refresh"
                          checked={form.enableAutoRefresh}
                          onChange={(e) => handleLiveSliderChange("enableAutoRefresh", e.target.checked)}
                          className="w-4 h-4 rounded accent-indigo-500"
                        />
                        <label htmlFor="webui-refresh" className="text-xs text-slate-300">
                          Enable Auto Reload WebViews ({form.autoRefreshInterval}s)
                        </label>
                      </div>
                    </div>
                  </div>

                  {/* Save Button */}
                  <div className="flex justify-end pt-2">
                    <button
                      type="submit"
                      className="px-5 py-2.5 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white font-medium text-xs flex items-center space-x-2 shadow-lg shadow-indigo-600/20 transition"
                    >
                      <Save className="w-4 h-4" />
                      <span>Save & Persist via WebUI</span>
                    </button>
                  </div>
                </form>
              )}

              {activeTab === "api" && (
                <div className="space-y-4">
                  <div className="flex items-center justify-between">
                    <span className="text-xs font-mono text-slate-400">GET /api/status</span>
                    <span className="text-[11px] text-emerald-400 font-mono">200 OK — application/json</span>
                  </div>
                  <pre className="p-4 rounded-xl bg-slate-950 border border-slate-800 text-xs font-mono text-indigo-300 overflow-x-auto">
                    {JSON.stringify(statusJson, null, 2)}
                  </pre>
                </div>
              )}
            </div>
          </div>
        )}
      </div>
    </div>
  );
};
