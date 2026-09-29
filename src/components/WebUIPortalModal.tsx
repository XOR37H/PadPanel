import React, { useState } from "react";
import { UltraKioskSettings, ScreensaverMode, WakeupMethod } from "../types/settings";
import {
  X,
  Globe,
  Lock,
  Unlock,
  RefreshCw,
  Power,
  Sun,
  Eye,
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
} from "lucide-react";

interface WebUIPortalModalProps {
  isOpen: boolean;
  onClose: () => void;
  settings: UltraKioskSettings;
  onSaveSettings: (newSettings: UltraKioskSettings) => void;
  onTriggerAction: (action: "screensaver" | "wakeup" | "reload") => void;
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
  onTriggerAction,
  isScreensaverActive,
  batteryLevel,
  isCharging,
  inactivitySecondsLeft,
}) => {
  const [isAuthenticated, setIsAuthenticated] = useState<boolean>(!settings.webServerPassword);
  const [enteredPassword, setEnteredPassword] = useState<string>("");
  const [authError, setAuthError] = useState<string | null>(null);

  // Form state for remote settings editing
  const [form, setForm] = useState<UltraKioskSettings>({ ...settings });
  const [saveSuccessMsg, setSaveSuccessMsg] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState<"dashboard" | "settings" | "api">("dashboard");

  // Keep form in sync when modal opens
  React.useEffect(() => {
    if (isOpen) {
      setForm({ ...settings, slideshowURLs: [...settings.slideshowURLs] });
      setIsAuthenticated(!settings.webServerPassword);
      setEnteredPassword("");
      setAuthError(null);
      setSaveSuccessMsg(null);
    }
  }, [isOpen, settings]);

  if (!isOpen) return null;

  const handleLogin = (e: React.FormEvent) => {
    e.preventDefault();
    if (enteredPassword === settings.webServerPassword) {
      setIsAuthenticated(true);
      setAuthError(null);
    } else {
      setAuthError("Invalid password. Please check settings configured in PadPanel.");
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
      authRequired: Boolean(settings.webServerPassword),
    },
    display: {
      screensaverActive: isScreensaverActive,
      screensaverMode: settings.screensaverMode,
      inactivitySecondsLeft,
      screensaverTimeout: settings.screensaverTimeout,
      screenBrightnessNormal: settings.screenBrightnessNormal,
      screenBrightnessDimmed: settings.screenBrightnessDimmed,
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
      <div className="relative w-full max-w-4xl max-h-[92vh] bg-slate-900 border border-slate-700/80 rounded-2xl shadow-2xl flex flex-col overflow-hidden text-slate-100 font-sans animate-in fade-in zoom-in-95 duration-200">
        
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
              Enter the password configured in PadPanel settings to manage this device remotely.
            </p>

            <form onSubmit={handleLogin} className="w-full space-y-4">
              <div>
                <input
                  type="password"
                  placeholder="Enter web server password..."
                  value={enteredPassword}
                  onChange={(e) => setEnteredPassword(e.target.value)}
                  className="w-full px-4 py-2.5 rounded-xl bg-slate-950 border border-slate-700 text-sm focus:outline-none focus:border-indigo-500 text-white"
                  autoFocus
                />
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
                Sign In
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
                  <span>Remote Settings Editor</span>
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

              {settings.webServerPassword && (
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
                        <span>MQTT Integration</span>
                        <Radio className="w-3.5 h-3.5 text-emerald-400" />
                      </div>
                      <div className="text-lg font-bold text-white">
                        {settings.enableMQTT ? "Enabled" : "Disabled"}
                      </div>
                      <div className="text-[11px] text-slate-500 mt-1 truncate">
                        {settings.mqttBrokerIP}
                      </div>
                    </div>
                  </div>

                  {/* Remote Action Buttons */}
                  <div className="p-5 rounded-2xl bg-slate-950/50 border border-slate-800">
                    <h3 className="text-sm font-semibold text-white mb-3 flex items-center space-x-2">
                      <Server className="w-4 h-4 text-indigo-400" />
                      <span>Remote Trigger Actions (POST /api/action)</span>
                    </h3>
                    <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                      <button
                        onClick={() => onTriggerAction("screensaver")}
                        className="p-3.5 rounded-xl bg-slate-900 hover:bg-slate-800 active:scale-95 border border-slate-700/80 text-left transition flex items-start space-x-3"
                      >
                        <Power className="w-5 h-5 text-amber-400 shrink-0 mt-0.5" />
                        <div>
                          <div className="text-xs font-semibold text-white">Trigger Screensaver</div>
                          <div className="text-[11px] text-slate-400">Action: <code>screensaver</code></div>
                        </div>
                      </button>

                      <button
                        onClick={() => onTriggerAction("wakeup")}
                        className="p-3.5 rounded-xl bg-slate-900 hover:bg-slate-800 active:scale-95 border border-slate-700/80 text-left transition flex items-start space-x-3"
                      >
                        <Sun className="w-5 h-5 text-emerald-400 shrink-0 mt-0.5" />
                        <div>
                          <div className="text-xs font-semibold text-white">Wake Display</div>
                          <div className="text-[11px] text-slate-400">Action: <code>wakeup</code></div>
                        </div>
                      </button>

                      <button
                        onClick={() => onTriggerAction("reload")}
                        className="p-3.5 rounded-xl bg-slate-900 hover:bg-slate-800 active:scale-95 border border-slate-700/80 text-left transition flex items-start space-x-3"
                      >
                        <RefreshCw className="w-5 h-5 text-sky-400 shrink-0 mt-0.5" />
                        <div>
                          <div className="text-xs font-semibold text-white">Reload WebViews</div>
                          <div className="text-[11px] text-slate-400">Action: <code>reload</code></div>
                        </div>
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
                  {/* Screensaver Section */}
                  <div className="p-5 rounded-2xl bg-slate-950/50 border border-slate-800 space-y-4">
                    <h3 className="text-sm font-semibold text-white">Screensaver & Display Settings</h3>
                    
                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                      <div>
                        <label className="block text-xs text-slate-400 mb-1">Screensaver Mode</label>
                        <select
                          value={form.screensaverMode}
                          onChange={(e) => setForm({ ...form, screensaverMode: e.target.value as ScreensaverMode })}
                          className="w-full px-3 py-2 rounded-xl bg-slate-900 border border-slate-700 text-xs text-white focus:outline-none focus:border-indigo-500"
                        >
                          <option value="clock">Clock & Date (Normal Screensaver)</option>
                          <option value="dimming">Dim Only (Keep Dashboard Visible)</option>
                          <option value="urls">Cycle Dashboard URLs</option>
                          <option value="off">Off (Never Sleep/Screensaver)</option>
                        </select>
                      </div>

                      <div>
                        <label className="block text-xs text-slate-400 mb-1">
                          Inactivity Timeout: {form.screensaverTimeout}s
                        </label>
                        <input
                          type="range"
                          min="10"
                          max="600"
                          step="10"
                          value={form.screensaverTimeout}
                          onChange={(e) => setForm({ ...form, screensaverTimeout: Number(e.target.value) })}
                          className="w-full accent-indigo-500"
                        />
                      </div>

                      <div>
                        <label className="block text-xs text-slate-400 mb-1">
                          Dimmed Brightness: {Math.round(form.screenBrightnessDimmed * 100)}%
                        </label>
                        <input
                          type="range"
                          min="0.05"
                          max="0.8"
                          step="0.05"
                          value={form.screenBrightnessDimmed}
                          onChange={(e) => setForm({ ...form, screenBrightnessDimmed: Number(e.target.value) })}
                          className="w-full accent-indigo-500"
                        />
                      </div>

                      <div>
                        <label className="block text-xs text-slate-400 mb-1">
                          Normal Brightness: {Math.round(form.screenBrightnessNormal * 100)}%
                        </label>
                        <input
                          type="range"
                          min="0.3"
                          max="1.0"
                          step="0.05"
                          value={form.screenBrightnessNormal}
                          onChange={(e) => setForm({ ...form, screenBrightnessNormal: Number(e.target.value) })}
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
                          onChange={(e) => setForm({ ...form, wakeupMethod: e.target.value as WakeupMethod })}
                          className="w-full px-3 py-2 rounded-xl bg-slate-900 border border-slate-700 text-xs text-white focus:outline-none focus:border-indigo-500"
                        >
                          <option value="face">Face Detection (Local Camera)</option>
                          <option value="motion">Motion Detection (Optical Diff)</option>
                        </select>
                      </div>

                      <div>
                        <label className="block text-xs text-slate-400 mb-1">
                          Motion Sensitivity: {form.motionSensitivity} ({form.motionSensitivity <= 0.04 ? "High" : form.motionSensitivity <= 0.12 ? "Medium" : "Low"})
                        </label>
                        <input
                          type="range"
                          min="0.02"
                          max="0.25"
                          step="0.01"
                          value={form.motionSensitivity}
                          onChange={(e) => setForm({ ...form, motionSensitivity: Number(e.target.value) })}
                          className="w-full accent-indigo-500"
                        />
                      </div>

                      <div className="flex items-center space-x-2 pt-2">
                        <input
                          type="checkbox"
                          id="webui-debug"
                          checked={form.showDebugInfo}
                          onChange={(e) => setForm({ ...form, showDebugInfo: e.target.checked })}
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
                          onChange={(e) => setForm({ ...form, enableAutoRefresh: e.target.checked })}
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
                      <span>Save Changes via WebUI</span>
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
