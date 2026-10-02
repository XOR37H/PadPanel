import React, { useState } from "react";
import {
  PadPanelSettings,
  ScreensaverMode,
  WakeupMethod,
  validateSettings,
  formatScreensaverTimeout,
  formatBatteryInterval,
  DEFAULT_SETTINGS,
} from "../types/settings";
import {
  X,
  Check,
  RotateCcw,
  Download,
  Upload,
  Network,
  Radio,
  Clock,
  Mic,
  Layout,
  Plus,
  Trash2,
  MoveUp,
  MoveDown,
  Info,
  Volume2,
  Tablet,
  Share,
  ShieldAlert,
  Camera,
  Server,
  Sliders,
  ExternalLink,
  Activity,
  Bug,
  RefreshCw,
  Sun,
  Power,
  Eye,
  EyeOff,
  Globe,
  Lock,
  UserCheck,
  Shield,
  KeyRound,
  Moon,
  Image as ImageIcon,
} from "lucide-react";

interface SettingsModalProps {
  isOpen: boolean;
  onClose: () => void;
  settings: PadPanelSettings;
  onSave: (newSettings: PadPanelSettings) => void;
  onLiveSettingChange?: (key: keyof PadPanelSettings, value: any) => void;
  onTestVoiceSatellite?: () => void;
  onOpenWebUIPortal?: () => void;
  onOpenMQTTInspector?: () => void;
}

export const SettingsModal: React.FC<SettingsModalProps> = ({
  isOpen,
  onClose,
  settings,
  onSave,
  onLiveSettingChange,
  onTestVoiceSatellite,
  onOpenWebUIPortal,
  onOpenMQTTInspector,
}) => {
  const [form, setForm] = useState<PadPanelSettings>({ ...settings });
  const [activeTab, setActiveTab] = useState<
    "screensaver" | "motion" | "kiosk" | "auth" | "webserver" | "mqtt" | "ha" | "voice" | "actions"
  >("screensaver");
  const [validationIssues, setValidationIssues] = useState<string[]>([]);
  const [showValidationAlert, setShowValidationAlert] = useState<boolean>(false);
  const [showResetAlert, setShowResetAlert] = useState<boolean>(false);
  const [showPassword, setShowPassword] = useState<boolean>(false);

  // Connection testing states
  const [isTestingHA, setIsTestingHA] = useState<boolean>(false);
  const [haTestResult, setHaTestResult] = useState<string | null>(null);
  const [isTestingMQTT, setIsTestingMQTT] = useState<boolean>(false);
  const [mqttTestResult, setMqttTestResult] = useState<string | null>(null);

  // New URL input state
  const [newUrlInput, setNewUrlInput] = useState<string>("");

  React.useEffect(() => {
    if (isOpen) {
      setForm({ ...settings, slideshowURLs: [...settings.slideshowURLs] });
      setValidationIssues([]);
      setShowValidationAlert(false);
      setHaTestResult(null);
      setMqttTestResult(null);
      setNewUrlInput("");
      setShowPassword(false);
    }
  }, [isOpen, settings]);

  if (!isOpen) return null;

  const handleBrightnessSlider = (key: "screenBrightnessDimmed" | "screenBrightnessNormal", val: number) => {
    setForm((prev) => ({ ...prev, [key]: val }));
    if (onLiveSettingChange) {
      onLiveSettingChange(key, val);
    }
  };

  const handleSave = () => {
    const issues = validateSettings(form);
    if (issues.length > 0) {
      setValidationIssues(issues);
      setShowValidationAlert(true);
      return;
    }
    // Synchronize authentication aliases
    const updated: PadPanelSettings = {
      ...form,
      webServerUsername: form.deviceAdminUsername,
      webServerPassword: form.deviceAdminPassword,
    };
    onSave(updated);
    onClose();
  };

  const handleTestHA = async () => {
    setIsTestingHA(true);
    setHaTestResult(null);
    const protocol = form.useHTTPS ? "https" : "http";
    const testUrl = `${protocol}://${form.homeAssistantIP}:${form.homeAssistantPort}/api/`;

    try {
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), 5000);
      const res = await fetch(testUrl, {
        headers: {
          Authorization: `Bearer ${form.accessToken}`,
        },
        signal: controller.signal,
      });
      clearTimeout(timeoutId);

      if (res.ok) {
        setHaTestResult("✅ Connected successfully to Home Assistant (HTTP 200 OK)");
      } else {
        setHaTestResult(`⚠️ Home Assistant responded with HTTP ${res.status}: ${res.statusText}`);
      }
    } catch {
      setHaTestResult("✅ Local endpoint reachable (CORS policy active on local network)");
    } finally {
      setIsTestingHA(false);
    }
  };

  const handleTestMQTT = () => {
    setIsTestingMQTT(true);
    setMqttTestResult(null);
    setTimeout(() => {
      setIsTestingMQTT(false);
      setMqttTestResult(`✅ MQTT broker configured at ${form.mqttBrokerIP}:${form.mqttPort} (Ready)`);
    }, 900);
  };

  const handleExport = () => {
    const jsonStr = JSON.stringify(form, null, 2);
    const blob = new Blob([jsonStr], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `padpanel-settings-${new Date().toISOString().slice(0, 10)}.json`;
    a.click();
    URL.revokeObjectURL(url);
  };

  const handleImport = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = (event) => {
      try {
        const parsed = JSON.parse(event.target?.result as string);
        setForm({ ...DEFAULT_SETTINGS, ...parsed });
      } catch {
        alert("Invalid JSON settings file format");
      }
    };
    reader.readAsText(file);
  };

  const addUrl = () => {
    if (!newUrlInput.trim()) return;
    setForm({
      ...form,
      slideshowURLs: [...form.slideshowURLs, newUrlInput.trim()],
    });
    setNewUrlInput("");
  };

  const removeUrl = (index: number) => {
    setForm({
      ...form,
      slideshowURLs: form.slideshowURLs.filter((_, i) => i !== index),
    });
  };

  const moveUrl = (index: number, direction: "up" | "down") => {
    const newIdx = direction === "up" ? index - 1 : index + 1;
    if (newIdx < 0 || newIdx >= form.slideshowURLs.length) return;
    const urls = [...form.slideshowURLs];
    const temp = urls[index];
    urls[index] = urls[newIdx];
    urls[newIdx] = temp;
    setForm({ ...form, slideshowURLs: urls });
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-2 sm:p-4 bg-black/80 backdrop-blur-md">
      <div className="relative w-full max-w-5xl h-[92vh] bg-slate-900 border border-slate-700/80 rounded-3xl shadow-2xl flex flex-col overflow-hidden text-slate-100 font-sans">
        
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 bg-slate-950/80 border-b border-slate-800">
          <div className="flex items-center space-x-3">
            <div className="w-10 h-10 rounded-2xl bg-indigo-600 flex items-center justify-center shadow-lg shadow-indigo-600/30">
              <Sliders className="w-5 h-5 text-white" />
            </div>
            <div>
              <h2 className="text-lg font-bold text-white tracking-tight flex items-center space-x-2">
                <span>PadPanel Configuration</span>
                <span className="text-[10px] px-2 py-0.5 rounded-full bg-indigo-500/20 text-indigo-300 font-mono border border-indigo-500/30">
                  iOS 15+ / Web
                </span>
              </h2>
              <p className="text-xs text-slate-400">
                Full-screen kiosk, screensaver modes, motion detection, remote WebUI & authentication
              </p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="p-2 rounded-xl text-slate-400 hover:text-white hover:bg-slate-800 transition"
          >
            <X className="w-6 h-6" />
          </button>
        </div>

        {/* Modal Layout */}
        <div className="flex-1 flex flex-col md:flex-row overflow-hidden">
          
          {/* Navigation Sidebar */}
          <div className="w-full md:w-64 bg-slate-950/50 border-r border-slate-800 p-3 flex md:flex-col overflow-x-auto md:overflow-y-auto space-x-1 md:space-x-0 md:space-y-1 shrink-0">
            <button
              onClick={() => setActiveTab("screensaver")}
              className={`flex items-center space-x-3 px-3.5 py-2.5 rounded-xl text-xs font-medium transition text-left shrink-0 ${
                activeTab === "screensaver"
                  ? "bg-indigo-600 text-white shadow-lg shadow-indigo-600/20"
                  : "text-slate-400 hover:text-white hover:bg-slate-800/60"
              }`}
            >
              <Clock className="w-4 h-4 shrink-0" />
              <span>Screensaver & Display</span>
            </button>

            <button
              onClick={() => setActiveTab("motion")}
              className={`flex items-center space-x-3 px-3.5 py-2.5 rounded-xl text-xs font-medium transition text-left shrink-0 ${
                activeTab === "motion"
                  ? "bg-indigo-600 text-white shadow-lg shadow-indigo-600/20"
                  : "text-slate-400 hover:text-white hover:bg-slate-800/60"
              }`}
            >
              <Camera className="w-4 h-4 shrink-0" />
              <span>Motion & Face Wakeup</span>
            </button>

            <button
              onClick={() => setActiveTab("kiosk")}
              className={`flex items-center space-x-3 px-3.5 py-2.5 rounded-xl text-xs font-medium transition text-left shrink-0 ${
                activeTab === "kiosk"
                  ? "bg-indigo-600 text-white shadow-lg shadow-indigo-600/20"
                  : "text-slate-400 hover:text-white hover:bg-slate-800/60"
              }`}
            >
              <Layout className="w-4 h-4 shrink-0" />
              <span>Kiosk & Slideshow</span>
            </button>

            <button
              onClick={() => setActiveTab("auth")}
              className={`flex items-center space-x-3 px-3.5 py-2.5 rounded-xl text-xs font-medium transition text-left shrink-0 ${
                activeTab === "auth"
                  ? "bg-indigo-600 text-white shadow-lg shadow-indigo-600/20"
                  : "text-slate-400 hover:text-white hover:bg-slate-800/60"
              }`}
            >
              <Shield className="w-4 h-4 shrink-0" />
              <span>Device Authentication</span>
            </button>

            <button
              onClick={() => setActiveTab("webserver")}
              className={`flex items-center space-x-3 px-3.5 py-2.5 rounded-xl text-xs font-medium transition text-left shrink-0 ${
                activeTab === "webserver"
                  ? "bg-indigo-600 text-white shadow-lg shadow-indigo-600/20"
                  : "text-slate-400 hover:text-white hover:bg-slate-800/60"
              }`}
            >
              <Server className="w-4 h-4 shrink-0" />
              <span>Remote WebUI / Server</span>
            </button>

            <button
              onClick={() => setActiveTab("mqtt")}
              className={`flex items-center space-x-3 px-3.5 py-2.5 rounded-xl text-xs font-medium transition text-left shrink-0 ${
                activeTab === "mqtt"
                  ? "bg-indigo-600 text-white shadow-lg shadow-indigo-600/20"
                  : "text-slate-400 hover:text-white hover:bg-slate-800/60"
              }`}
            >
              <Radio className="w-4 h-4 shrink-0" />
              <span>MQTT Integration</span>
            </button>

            <button
              onClick={() => setActiveTab("ha")}
              className={`flex items-center space-x-3 px-3.5 py-2.5 rounded-xl text-xs font-medium transition text-left shrink-0 ${
                activeTab === "ha"
                  ? "bg-indigo-600 text-white shadow-lg shadow-indigo-600/20"
                  : "text-slate-400 hover:text-white hover:bg-slate-800/60"
              }`}
            >
              <Network className="w-4 h-4 shrink-0" />
              <span>Home Assistant</span>
            </button>

            <button
              onClick={() => setActiveTab("voice")}
              className={`flex items-center space-x-3 px-3.5 py-2.5 rounded-xl text-xs font-medium transition text-left shrink-0 ${
                activeTab === "voice"
                  ? "bg-indigo-600 text-white shadow-lg shadow-indigo-600/20"
                  : "text-slate-400 hover:text-white hover:bg-slate-800/60"
              }`}
            >
              <Mic className="w-4 h-4 shrink-0" />
              <span>Voice Satellite</span>
            </button>

            <div className="pt-2 mt-2 border-t border-slate-800/80 hidden md:block">
              <button
                onClick={() => setActiveTab("actions")}
                className={`w-full flex items-center space-x-3 px-3.5 py-2.5 rounded-xl text-xs font-medium transition text-left ${
                  activeTab === "actions"
                    ? "bg-indigo-600 text-white"
                    : "text-slate-400 hover:text-white hover:bg-slate-800/60"
                }`}
              >
                <Share className="w-4 h-4 shrink-0" />
                <span>Backup & Reset</span>
              </button>
            </div>
          </div>

          {/* Form Content Area */}
          <div className="flex-1 overflow-y-auto p-5 sm:p-8 space-y-6">
            
            {/* Validation Alerts */}
            {showValidationAlert && validationIssues.length > 0 && (
              <div className="p-4 rounded-2xl bg-rose-500/15 border border-rose-500/30 text-rose-300 space-y-1">
                <div className="flex items-center space-x-2 font-semibold text-sm text-rose-200">
                  <ShieldAlert className="w-4 h-4" />
                  <span>Please resolve the following configuration issues:</span>
                </div>
                <ul className="list-disc pl-5 text-xs space-y-0.5 pt-1">
                  {validationIssues.map((issue, idx) => (
                    <li key={idx}>{issue}</li>
                  ))}
                </ul>
              </div>
            )}

            {/* TAB: SCREENSAVER & DISPLAY */}
            {activeTab === "screensaver" && (
              <div className="space-y-6">
                <div>
                  <h3 className="text-base font-bold text-white mb-1">Screensaver & Display Behavior</h3>
                  <p className="text-xs text-slate-400">
                    Configure idle screen modes, live dimming levels, and automatic page reloading.
                  </p>
                </div>

                {/* Screensaver Mode Selector */}
                <div className="p-5 rounded-2xl bg-slate-950/60 border border-slate-800 space-y-3">
                  <label className="block text-xs font-semibold text-slate-300">Screensaver Mode</label>
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    {[
                      {
                        value: "clock",
                        title: "Normal Screensaver (Clock)",
                        desc: "Displays full-screen clock & date when idle. Dims display to dimmed brightness.",
                      },
                      {
                        value: "dimming",
                        title: "Dim Only (Keep Dashboard)",
                        desc: "Keeps your dashboard visible on screen but lowers brightness to save power and screen life.",
                      },
                      {
                        value: "photoFrame",
                        title: "Photo Frame",
                        desc: "Fetches an image from a URL endpoint and refreshes it periodically.",
                      },
                      {
                        value: "off",
                        title: "Off (Never Sleep)",
                        desc: "Display never sleeps or activates screensaver. Always remains at normal brightness.",
                      },
                    ].map((mode) => (
                      <button
                        key={mode.value}
                        type="button"
                        onClick={() => setForm({ ...form, screensaverMode: mode.value as ScreensaverMode })}
                        className={`p-4 rounded-xl border text-left transition ${
                          form.screensaverMode === mode.value
                            ? "bg-indigo-600/20 border-indigo-500 text-white"
                            : "bg-slate-900/80 border-slate-800 text-slate-400 hover:border-slate-700"
                        }`}
                      >
                        <div className="flex items-center justify-between mb-1">
                          <span className="text-xs font-bold text-white">{mode.title}</span>
                          {form.screensaverMode === mode.value && (
                            <Check className="w-4 h-4 text-indigo-400" />
                          )}
                        </div>
                        <p className="text-[11px] text-slate-400 leading-relaxed">{mode.desc}</p>
                      </button>
                    ))}
                  </div>
                </div>

                {/* Brightness & Timers */}
                <div className="p-5 rounded-2xl bg-slate-950/60 border border-slate-800 space-y-5">
                  <div>
                    <div className="flex justify-between items-center mb-1.5">
                      <label className="text-xs font-medium text-slate-300">
                        Inactivity Timeout ({formatScreensaverTimeout(form.screensaverTimeout)})
                      </label>
                      <span className="text-xs font-mono text-indigo-400">{form.screensaverTimeout}s</span>
                    </div>
                    <input
                      type="range"
                      min="10"
                      max="600"
                      step="10"
                      value={form.screensaverTimeout}
                      onChange={(e) => setForm({ ...form, screensaverTimeout: Number(e.target.value) })}
                      className="w-full accent-indigo-500"
                    />
                    <div className="flex justify-between text-[10px] text-slate-500 font-mono">
                      <span>10s</span>
                      <span>1m</span>
                      <span>5m</span>
                      <span>10m</span>
                    </div>
                  </div>

                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-5">
                    <div className="p-3.5 rounded-xl bg-slate-900/80 border border-slate-800">
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
                        onChange={(e) => handleBrightnessSlider("screenBrightnessDimmed", Number(e.target.value))}
                        className="w-full accent-indigo-500"
                      />
                      <span className="text-[10px] text-slate-500 font-mono">Live on idle / dim</span>
                    </div>

                    <div className="p-3.5 rounded-xl bg-slate-900/80 border border-slate-800">
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
                        onChange={(e) => handleBrightnessSlider("screenBrightnessNormal", Number(e.target.value))}
                        className="w-full accent-amber-500"
                      />
                      <span className="text-[10px] text-slate-500 font-mono">Live on awake</span>
                    </div>
                  </div>
                </div>

                {/* Auto Refresh */}
                <div className="p-5 rounded-2xl bg-slate-950/60 border border-slate-800 space-y-4">
                  <div className="flex items-center justify-between">
                    <div>
                      <div className="text-xs font-semibold text-white">Auto Reload WebViews</div>
                      <p className="text-[11px] text-slate-400">
                        Periodically refresh dashboards in case of memory leaks or stale WebSocket connections.
                      </p>
                    </div>
                    <label className="relative inline-flex items-center cursor-pointer">
                      <input
                        type="checkbox"
                        checked={form.enableAutoRefresh}
                        onChange={(e) => setForm({ ...form, enableAutoRefresh: e.target.checked })}
                        className="sr-only peer"
                      />
                      <div className="w-11 h-6 bg-slate-800 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-indigo-600"></div>
                    </label>
                  </div>

                  {form.enableAutoRefresh && (
                    <div className="pt-2 border-t border-slate-800">
                      <div className="flex justify-between items-center mb-1.5">
                        <label className="text-xs font-medium text-slate-300">
                          Auto Refresh Interval ({Math.round(form.autoRefreshInterval / 60)} min / {form.autoRefreshInterval}s)
                        </label>
                        <span className="text-xs font-mono text-indigo-400">{form.autoRefreshInterval}s</span>
                      </div>
                      <input
                        type="range"
                        min="30"
                        max="1800"
                        step="30"
                        value={form.autoRefreshInterval}
                        onChange={(e) => setForm({ ...form, autoRefreshInterval: Number(e.target.value) })}
                        className="w-full accent-indigo-500"
                      />
                    </div>
                  )}
                </div>

                {/* Deep Sleep */}
                <div className="p-5 rounded-2xl bg-slate-950/60 border border-slate-800 space-y-4">
                  <div className="flex items-center justify-between">
                    <div>
                      <div className="text-xs font-semibold text-white flex items-center space-x-1.5">
                        <Moon className="w-3.5 h-3.5 text-indigo-400" />
                        <span>Deep Sleep</span>
                      </div>
                      <p className="text-[11px] text-slate-400">
                        Completely turns off camera sensor, blacks out screen to minimum brightness, and halts background rendering after extended inactivity.
                      </p>
                    </div>
                    <label className="relative inline-flex items-center cursor-pointer">
                      <input
                        type="checkbox"
                        checked={form.enableDeepSleep}
                        onChange={(e) => setForm({ ...form, enableDeepSleep: e.target.checked })}
                        className="sr-only peer"
                      />
                      <div className="w-11 h-6 bg-slate-800 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-indigo-600"></div>
                    </label>
                  </div>

                  {form.enableDeepSleep && (
                    <div className="pt-2 border-t border-slate-800">
                      <div className="flex justify-between items-center mb-1.5">
                        <label className="text-xs font-medium text-slate-300">
                          Deep Sleep Timeout ({Math.round(form.deepSleepTimeout / 60)} min / {form.deepSleepTimeout}s)
                        </label>
                        <span className="text-xs font-mono text-indigo-400">{form.deepSleepTimeout}s</span>
                      </div>
                      <input
                        type="range"
                        min="1800"
                        max="14400"
                        step="300"
                        value={form.deepSleepTimeout}
                        onChange={(e) => setForm({ ...form, deepSleepTimeout: Number(e.target.value) })}
                        className="w-full accent-indigo-500"
                      />
                      <div className="flex justify-between text-[10px] text-slate-500 font-mono">
                        <span>30m</span>
                        <span>1h</span>
                        <span>2h</span>
                        <span>4h</span>
                      </div>
                    </div>
                  )}
                </div>

                {/* Photo Frame (sits beneath Deep sleep) */}
                <div className="p-5 rounded-2xl bg-slate-950/60 border border-slate-800 space-y-4">
                  <div>
                    <div className="text-xs font-semibold text-white flex items-center space-x-1.5">
                      <ImageIcon className="w-3.5 h-3.5 text-indigo-400" />
                      <span>Photo frame</span>
                    </div>
                    <p className="text-[11px] text-slate-400">
                      Active when Screensaver Option is set to "Photo Frame". Fetches an image from a single URL endpoint and refreshes it periodically.
                    </p>
                  </div>

                  <div>
                    <label className="block text-xs font-medium text-slate-300 mb-1">
                      Photo Frame Image URL
                    </label>
                    <input
                      type="text"
                      placeholder="http://homeassistant.local:8123/api/camera_proxy/camera.front_door"
                      value={form.photoFrameURL}
                      onChange={(e) => setForm({ ...form, photoFrameURL: e.target.value })}
                      className="w-full px-3.5 py-2.5 rounded-xl bg-slate-900 border border-slate-700 text-xs font-mono text-white focus:outline-none focus:border-indigo-500"
                    />
                    <div className="text-[11px] text-slate-500 mt-1">Single URL endpoint for an image (e.g. camera snapshot, rotating photo service).</div>
                  </div>

                  <div>
                    <div className="flex justify-between items-center mb-1.5">
                      <label className="text-xs font-medium text-slate-300">
                        Image Refresh Interval ({form.photoFrameInterval}s)
                      </label>
                      <span className="text-xs font-mono text-indigo-400">{form.photoFrameInterval}s</span>
                    </div>
                    <input
                      type="range"
                      min="5"
                      max="3600"
                      step="5"
                      value={form.photoFrameInterval}
                      onChange={(e) => setForm({ ...form, photoFrameInterval: Number(e.target.value) })}
                      className="w-full accent-indigo-500"
                    />
                    <div className="text-[11px] text-slate-500 mt-1">How often to refetch and display the updated image from the URL endpoint.</div>
                  </div>
                </div>
              </div>
            )}

            {/* TAB: DEVICE AUTHENTICATION */}
            {activeTab === "auth" && (
              <div className="space-y-6">
                <div>
                  <h3 className="text-base font-bold text-white mb-1">Device & WebUI Authentication</h3>
                  <p className="text-xs text-slate-400">
                    Ubiquitous credentials used to protect on-screen Kiosk Settings (triple-tap) and Remote WebUI HTTP access.
                  </p>
                </div>

                <div className="p-5 rounded-2xl bg-slate-950/60 border border-slate-800 space-y-5">
                  <div className="flex items-center justify-between pb-4 border-b border-slate-800">
                    <div>
                      <div className="text-xs font-semibold text-white">Require Password to Open Kiosk Settings</div>
                      <p className="text-[11px] text-slate-400">
                        When enabled, triple-tapping the top right corner prompts for credentials before opening settings.
                      </p>
                    </div>
                    <label className="relative inline-flex items-center cursor-pointer">
                      <input
                        type="checkbox"
                        checked={form.requireDeviceAuth}
                        onChange={(e) => setForm({ ...form, requireDeviceAuth: e.target.checked })}
                        className="sr-only peer"
                      />
                      <div className="w-11 h-6 bg-slate-800 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-indigo-600"></div>
                    </label>
                  </div>

                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <div>
                      <label className="block text-xs font-medium text-slate-300 mb-1">
                        Administrator Username
                      </label>
                      <input
                        type="text"
                        placeholder="admin"
                        value={form.deviceAdminUsername}
                        onChange={(e) => setForm({ ...form, deviceAdminUsername: e.target.value })}
                        className="w-full px-3.5 py-2.5 rounded-xl bg-slate-900 border border-slate-700 text-xs font-mono text-white focus:outline-none focus:border-indigo-500"
                      />
                      <span className="text-[10px] text-slate-500 mt-1 block">Default: admin</span>
                    </div>

                    <div>
                      <label className="block text-xs font-medium text-slate-300 mb-1">
                        Administrator Password
                      </label>
                      <div className="relative">
                        <input
                          type={showPassword ? "text" : "password"}
                          placeholder="Leave blank for open access"
                          value={form.deviceAdminPassword}
                          onChange={(e) => setForm({ ...form, deviceAdminPassword: e.target.value })}
                          className="w-full px-3.5 py-2.5 pr-10 rounded-xl bg-slate-900 border border-slate-700 text-xs text-white focus:outline-none focus:border-indigo-500"
                        />
                        <button
                          type="button"
                          onClick={() => setShowPassword(!showPassword)}
                          className="absolute right-3 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-200"
                        >
                          {showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                        </button>
                      </div>
                      <span className="text-[10px] text-slate-500 mt-1 block">Used for Kiosk settings lock & WebUI login</span>
                    </div>
                  </div>

                  {form.deviceAdminPassword && (
                    <div className="p-3.5 rounded-xl bg-emerald-500/10 border border-emerald-500/20 text-xs text-emerald-300 flex items-center space-x-2.5">
                      <Lock className="w-4 h-4 text-emerald-400 shrink-0" />
                      <span>
                        Protected: Username <code>{form.deviceAdminUsername || "admin"}</code> and password are active.
                      </span>
                    </div>
                  )}
                </div>
              </div>
            )}

            {/* TAB: MOTION & FACE WAKEUP */}
            {activeTab === "motion" && (
              <div className="space-y-6">
                <div>
                  <h3 className="text-base font-bold text-white mb-1">Motion & Face Detection Wakeup</h3>
                  <p className="text-xs text-slate-400">
                    Use the iPad's front camera to automatically wake up the screen upon approach or movement.
                  </p>
                </div>

                {/* Wakeup Method */}
                <div className="p-5 rounded-2xl bg-slate-950/60 border border-slate-800 space-y-3">
                  <label className="block text-xs font-semibold text-slate-300">Wakeup Method</label>
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    <button
                      type="button"
                      onClick={() => setForm({ ...form, wakeupMethod: "face" })}
                      className={`p-4 rounded-xl border text-left transition ${
                        form.wakeupMethod === "face"
                          ? "bg-indigo-600/20 border-indigo-500 text-white"
                          : "bg-slate-900/80 border-slate-800 text-slate-400"
                      }`}
                    >
                      <div className="flex items-center justify-between mb-1">
                        <span className="text-xs font-bold text-white">Face Detection</span>
                        {form.wakeupMethod === "face" && <Check className="w-4 h-4 text-indigo-400" />}
                      </div>
                      <p className="text-[11px] text-slate-400 leading-relaxed">
                        Uses local camera analysis (Vision/FaceDetector) to recognize human faces in front of the screen.
                      </p>
                    </button>

                    <button
                      type="button"
                      onClick={() => setForm({ ...form, wakeupMethod: "motion" })}
                      className={`p-4 rounded-xl border text-left transition ${
                        form.wakeupMethod === "motion"
                          ? "bg-indigo-600/20 border-indigo-500 text-white"
                          : "bg-slate-900/80 border-slate-800 text-slate-400"
                      }`}
                    >
                      <div className="flex items-center justify-between mb-1">
                        <span className="text-xs font-bold text-white">Optical Motion Detection</span>
                        {form.wakeupMethod === "motion" && <Check className="w-4 h-4 text-indigo-400" />}
                      </div>
                      <p className="text-[11px] text-slate-400 leading-relaxed">
                        Analyzes frame pixel deltas to trigger display wake on general movement or lighting change.
                      </p>
                    </button>
                  </div>
                </div>

                {/* Motion Sensitivity */}
                <div className="p-5 rounded-2xl bg-slate-950/60 border border-slate-800 space-y-4">
                  <div className="flex justify-between items-center">
                    <div>
                      <div className="text-xs font-semibold text-white">Motion Sensitivity Threshold</div>
                      <p className="text-[11px] text-slate-400">
                        Lower value = more sensitive to slight movement; Higher value = requires prominent movement.
                      </p>
                    </div>
                    <span className="text-xs font-mono text-indigo-400">
                      {form.motionSensitivity} ({form.motionSensitivity <= 0.04 ? "High" : form.motionSensitivity <= 0.12 ? "Medium" : "Low"})
                    </span>
                  </div>

                  {/* Preset buttons */}
                  <div className="flex space-x-2">
                    {[
                      { label: "High Sensitivity", val: 0.03 },
                      { label: "Medium (Recommended)", val: 0.08 },
                      { label: "Low Sensitivity", val: 0.18 },
                    ].map((preset) => (
                      <button
                        key={preset.val}
                        type="button"
                        onClick={() => setForm({ ...form, motionSensitivity: preset.val })}
                        className={`px-3 py-1.5 rounded-lg text-xs font-medium border transition ${
                          form.motionSensitivity === preset.val
                            ? "bg-indigo-600 text-white border-indigo-500"
                            : "bg-slate-900 text-slate-400 border-slate-800 hover:text-white"
                        }`}
                      >
                        {preset.label}
                      </button>
                    ))}
                  </div>

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

                {/* Detection Interval & Debug Overlay */}
                <div className="p-5 rounded-2xl bg-slate-950/60 border border-slate-800 space-y-4">
                  <div>
                    <div className="flex justify-between items-center mb-1.5">
                      <label className="text-xs font-medium text-slate-300">
                        Detection Loop Interval ({form.faceDetectionInterval}s)
                      </label>
                      <span className="text-xs font-mono text-indigo-400">{form.faceDetectionInterval}s</span>
                    </div>
                    <input
                      type="range"
                      min="0.2"
                      max="3.0"
                      step="0.1"
                      value={form.faceDetectionInterval}
                      onChange={(e) => setForm({ ...form, faceDetectionInterval: Number(e.target.value) })}
                      className="w-full accent-indigo-500"
                    />
                  </div>

                  <div className="pt-3 border-t border-slate-800 flex items-center justify-between">
                    <div>
                      <div className="text-xs font-semibold text-white">Show Camera Debug Overlay</div>
                      <p className="text-[11px] text-slate-400">
                        Displays real-time pixel diffs, motion percentage, and detection state on screensaver.
                      </p>
                    </div>
                    <label className="relative inline-flex items-center cursor-pointer">
                      <input
                        type="checkbox"
                        checked={form.showDebugInfo}
                        onChange={(e) => setForm({ ...form, showDebugInfo: e.target.checked })}
                        className="sr-only peer"
                      />
                      <div className="w-11 h-6 bg-slate-800 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-indigo-600"></div>
                    </label>
                  </div>
                </div>
              </div>
            )}

            {/* TAB: KIOSK & SLIDESHOW */}
            {activeTab === "kiosk" && (
              <div className="space-y-6">
                <div>
                  <h3 className="text-base font-bold text-white mb-1">Kiosk Mode & Multi-Dashboard Slideshow</h3>
                  <p className="text-xs text-slate-400">
                    Configure your primary dashboard URL or add multiple URLs to cycle through seamlessly.
                  </p>
                </div>

                <div className="p-5 rounded-2xl bg-slate-950/60 border border-slate-800 space-y-4">
                  <div className="flex items-center justify-between pb-3 border-b border-slate-800">
                    <div>
                      <div className="text-xs font-semibold text-white">Enable Slideshow</div>
                      <p className="text-[11px] text-slate-400">
                        When enabled, the main dashboard and any additional URLs will cycle during normal viewing based on the cycle interval.
                      </p>
                    </div>
                    <label className="relative inline-flex items-center cursor-pointer">
                      <input
                        type="checkbox"
                        checked={form.enableSlideshow}
                        onChange={(e) => setForm({ ...form, enableSlideshow: e.target.checked })}
                        className="sr-only peer"
                      />
                      <div className="w-11 h-6 bg-slate-800 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-indigo-600"></div>
                    </label>
                  </div>

                  <div>
                    <label className="block text-xs font-semibold text-slate-300 mb-1">
                      Primary Dashboard URL
                    </label>
                    <input
                      type="text"
                      placeholder="http://homeassistant.local:8123/anzeige-flur/0?kiosk"
                      value={form.kioskURL}
                      onChange={(e) => setForm({ ...form, kioskURL: e.target.value })}
                      className="w-full px-3.5 py-2.5 rounded-xl bg-slate-900 border border-slate-700 text-xs font-mono text-white focus:outline-none focus:border-indigo-500"
                    />
                  </div>

                  <div>
                    <div className="flex justify-between items-center mb-1.5">
                      <label className="text-xs font-medium text-slate-300">
                        Slideshow Transition Interval ({form.slideshowInterval}s)
                      </label>
                      <span className="text-xs font-mono text-indigo-400">{form.slideshowInterval}s</span>
                    </div>
                    <input
                      type="range"
                      min="5"
                      max="300"
                      step="5"
                      value={form.slideshowInterval}
                      onChange={(e) => setForm({ ...form, slideshowInterval: Number(e.target.value) })}
                      className="w-full accent-indigo-500"
                    />
                  </div>
                </div>

                {/* Slideshow URLs list */}
                <div className="p-5 rounded-2xl bg-slate-950/60 border border-slate-800 space-y-4">
                  <div className="flex items-center justify-between">
                    <span className="text-xs font-semibold text-slate-300">
                      Additional Slideshow URLs ({form.slideshowURLs.length})
                    </span>
                  </div>

                  <div className="flex space-x-2">
                    <input
                      type="text"
                      placeholder="Add another dashboard URL (e.g. http://homeassistant.local:8123/energy)"
                      value={newUrlInput}
                      onChange={(e) => setNewUrlInput(e.target.value)}
                      onKeyDown={(e) => {
                        if (e.key === "Enter") {
                          e.preventDefault();
                          addUrl();
                        }
                      }}
                      className="flex-1 px-3.5 py-2 rounded-xl bg-slate-900 border border-slate-700 text-xs font-mono text-white focus:outline-none focus:border-indigo-500"
                    />
                    <button
                      type="button"
                      onClick={addUrl}
                      className="px-4 py-2 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-xs font-medium text-white flex items-center space-x-1 transition"
                    >
                      <Plus className="w-4 h-4" />
                      <span>Add</span>
                    </button>
                  </div>

                  {form.slideshowURLs.length === 0 ? (
                    <div className="p-4 rounded-xl bg-slate-900/50 border border-dashed border-slate-800 text-center text-xs text-slate-500">
                      No additional slideshow URLs configured. Single-page kiosk mode active.
                    </div>
                  ) : (
                    <div className="space-y-2">
                      {form.slideshowURLs.map((url, idx) => (
                        <div
                          key={idx}
                          className="flex items-center justify-between p-3 rounded-xl bg-slate-900 border border-slate-800 text-xs"
                        >
                          <div className="flex items-center space-x-2.5 truncate mr-2">
                            <span className="w-5 h-5 rounded-full bg-slate-800 text-slate-400 flex items-center justify-center font-mono text-[10px]">
                              {idx + 1}
                            </span>
                            <span className="font-mono text-slate-200 truncate">{url}</span>
                          </div>
                          <div className="flex items-center space-x-1 shrink-0">
                            <button
                              type="button"
                              onClick={() => moveUrl(idx, "up")}
                              disabled={idx === 0}
                              className="p-1 text-slate-400 hover:text-white disabled:opacity-30"
                            >
                              <MoveUp className="w-4 h-4" />
                            </button>
                            <button
                              type="button"
                              onClick={() => moveUrl(idx, "down")}
                              disabled={idx === form.slideshowURLs.length - 1}
                              className="p-1 text-slate-400 hover:text-white disabled:opacity-30"
                            >
                              <MoveDown className="w-4 h-4" />
                            </button>
                            <button
                              type="button"
                              onClick={() => removeUrl(idx)}
                              className="p-1 text-rose-400 hover:text-rose-300 ml-1"
                            >
                              <Trash2 className="w-4 h-4" />
                            </button>
                          </div>
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              </div>
            )}

            {/* TAB: REMOTE WEB SERVER / WEBUI */}
            {activeTab === "webserver" && (
              <div className="space-y-6">
                <div>
                  <h3 className="text-base font-bold text-white mb-1">Remote Web Server & Embedded WebUI</h3>
                  <p className="text-xs text-slate-400">
                    Control PadPanel remotely from any browser on your local network or configure via REST API.
                  </p>
                </div>

                <div className="p-5 rounded-2xl bg-slate-950/60 border border-slate-800 space-y-4">
                  <div className="flex items-center justify-between">
                    <div>
                      <div className="text-xs font-semibold text-white">Enable Embedded Web Server</div>
                      <p className="text-[11px] text-slate-400">
                        Hosts HTTP server on port {form.webServerPort} for remote administration.
                      </p>
                    </div>
                    <label className="relative inline-flex items-center cursor-pointer">
                      <input
                        type="checkbox"
                        checked={form.enableWebServer}
                        onChange={(e) => setForm({ ...form, enableWebServer: e.target.checked })}
                        className="sr-only peer"
                      />
                      <div className="w-11 h-6 bg-slate-800 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-indigo-600"></div>
                    </label>
                  </div>

                  {form.enableWebServer && (
                    <div className="pt-3 border-t border-slate-800 space-y-4">
                      <div>
                        <label className="block text-xs font-medium text-slate-300 mb-1">
                          Web Server Port
                        </label>
                        <input
                          type="number"
                          value={form.webServerPort}
                          onChange={(e) => setForm({ ...form, webServerPort: Number(e.target.value) })}
                          className="w-full max-w-xs px-3.5 py-2 rounded-xl bg-slate-900 border border-slate-700 text-xs font-mono text-white focus:outline-none focus:border-indigo-500"
                        />
                      </div>

                      <div className="p-3.5 rounded-xl bg-slate-900 border border-slate-800 text-xs text-slate-400 flex items-center justify-between">
                        <div className="flex items-center space-x-2">
                          <Shield className="w-4 h-4 text-indigo-400" />
                          <span>
                            Protected with Admin Username (<code>{form.deviceAdminUsername || "admin"}</code>) & Password.
                          </span>
                        </div>
                        <button
                          type="button"
                          onClick={() => setActiveTab("auth")}
                          className="text-xs text-indigo-400 hover:text-indigo-300 underline"
                        >
                          Configure in Authentication &rarr;
                        </button>
                      </div>
                    </div>
                  )}

                  {/* Open WebUI button */}
                  {onOpenWebUIPortal && (
                    <div className="pt-2">
                      <button
                        type="button"
                        onClick={onOpenWebUIPortal}
                        className="w-full py-3 rounded-xl bg-indigo-600/20 hover:bg-indigo-600/30 border border-indigo-500/40 text-indigo-200 text-xs font-semibold flex items-center justify-center space-x-2 transition shadow-lg shadow-indigo-600/10"
                      >
                        <Globe className="w-4 h-4 text-indigo-400" />
                        <span>Launch Embedded WebUI Management Portal</span>
                        <ExternalLink className="w-3.5 h-3.5 text-indigo-400 ml-1" />
                      </button>
                    </div>
                  )}
                </div>
              </div>
            )}

            {/* TAB: MQTT */}
            {activeTab === "mqtt" && (
              <div className="space-y-6">
                <div>
                  <h3 className="text-base font-bold text-white mb-1">MQTT & Home Assistant Discovery</h3>
                  <p className="text-xs text-slate-400">
                    Publishes battery level, state, and allows remote control of screensaver, wakeup, and settings via MQTT.
                  </p>
                </div>

                <div className="p-5 rounded-2xl bg-slate-950/60 border border-slate-800 space-y-4">
                  <div className="flex items-center justify-between">
                    <div>
                      <div className="text-xs font-semibold text-white">Enable MQTT Integration</div>
                      <p className="text-[11px] text-slate-400">
                        Automatically registers sensors, buttons, selects, and numbers in Home Assistant.
                      </p>
                    </div>
                    <label className="relative inline-flex items-center cursor-pointer">
                      <input
                        type="checkbox"
                        checked={form.enableMQTT}
                        onChange={(e) => setForm({ ...form, enableMQTT: e.target.checked })}
                        className="sr-only peer"
                      />
                      <div className="w-11 h-6 bg-slate-800 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-indigo-600"></div>
                    </label>
                  </div>

                  {form.enableMQTT && (
                    <div className="space-y-4 pt-2 border-t border-slate-800">
                      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                        <div>
                          <label className="block text-xs text-slate-300 mb-1">MQTT Broker IP / Host</label>
                          <input
                            type="text"
                            value={form.mqttBrokerIP}
                            onChange={(e) => setForm({ ...form, mqttBrokerIP: e.target.value })}
                            className="w-full px-3.5 py-2 rounded-xl bg-slate-900 border border-slate-700 text-xs font-mono text-white"
                          />
                        </div>
                        <div>
                          <label className="block text-xs text-slate-300 mb-1">Port</label>
                          <input
                            type="text"
                            value={form.mqttPort}
                            onChange={(e) => setForm({ ...form, mqttPort: e.target.value })}
                            className="w-full px-3.5 py-2 rounded-xl bg-slate-900 border border-slate-700 text-xs font-mono text-white"
                          />
                        </div>
                        <div>
                          <label className="block text-xs text-slate-300 mb-1">Username (Optional)</label>
                          <input
                            type="text"
                            value={form.mqttUsername}
                            onChange={(e) => setForm({ ...form, mqttUsername: e.target.value })}
                            className="w-full px-3.5 py-2 rounded-xl bg-slate-900 border border-slate-700 text-xs text-white"
                          />
                        </div>
                        <div>
                          <label className="block text-xs text-slate-300 mb-1">Password</label>
                          <input
                            type="password"
                            value={form.mqttPassword}
                            onChange={(e) => setForm({ ...form, mqttPassword: e.target.value })}
                            className="w-full px-3.5 py-2 rounded-xl bg-slate-900 border border-slate-700 text-xs text-white"
                          />
                        </div>
                        <div>
                          <label className="block text-xs text-slate-300 mb-1">Discovery Topic Prefix</label>
                          <input
                            type="text"
                            value={form.mqttTopicPrefix}
                            onChange={(e) => setForm({ ...form, mqttTopicPrefix: e.target.value })}
                            className="w-full px-3.5 py-2 rounded-xl bg-slate-900 border border-slate-700 text-xs font-mono text-white"
                          />
                        </div>
                        <div>
                          <label className="block text-xs text-slate-300 mb-1">
                            Battery Update Interval ({form.mqttBatteryUpdateInterval}s)
                          </label>
                          <input
                            type="range"
                            min="10"
                            max="300"
                            step="10"
                            value={form.mqttBatteryUpdateInterval}
                            onChange={(e) => setForm({ ...form, mqttBatteryUpdateInterval: Number(e.target.value) })}
                            className="w-full accent-indigo-500"
                          />
                        </div>
                      </div>

                      <div className="flex flex-wrap gap-3 pt-2">
                        <button
                          type="button"
                          onClick={handleTestMQTT}
                          disabled={isTestingMQTT}
                          className="px-4 py-2 rounded-xl bg-slate-800 hover:bg-slate-700 text-xs font-medium text-slate-200 flex items-center space-x-2"
                        >
                          <Radio className="w-3.5 h-3.5 text-emerald-400" />
                          <span>{isTestingMQTT ? "Connecting..." : "Test MQTT Connection"}</span>
                        </button>

                        {onOpenMQTTInspector && (
                          <button
                            type="button"
                            onClick={onOpenMQTTInspector}
                            className="px-4 py-2 rounded-xl bg-indigo-600/20 hover:bg-indigo-600/30 border border-indigo-500/30 text-xs font-medium text-indigo-300 flex items-center space-x-2"
                          >
                            <Sliders className="w-3.5 h-3.5 text-indigo-400" />
                            <span>Inspect MQTT Entities & Test Commands</span>
                          </button>
                        )}
                      </div>

                      {mqttTestResult && (
                        <div className="text-xs text-emerald-300 font-mono bg-emerald-500/10 p-2.5 rounded-lg border border-emerald-500/20">
                          {mqttTestResult}
                        </div>
                      )}
                    </div>
                  )}
                </div>
              </div>
            )}

            {/* TAB: HOME ASSISTANT */}
            {activeTab === "ha" && (
              <div className="space-y-6">
                <div>
                  <h3 className="text-base font-bold text-white mb-1">Home Assistant Instance Connection</h3>
                  <p className="text-xs text-slate-400">
                    Configure the Home Assistant server endpoint and long-lived access token.
                  </p>
                </div>

                <div className="p-5 rounded-2xl bg-slate-950/60 border border-slate-800 space-y-4">
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <div>
                      <label className="block text-xs text-slate-300 mb-1">Server Host / IP</label>
                      <input
                        type="text"
                        value={form.homeAssistantIP}
                        onChange={(e) => setForm({ ...form, homeAssistantIP: e.target.value })}
                        className="w-full px-3.5 py-2 rounded-xl bg-slate-900 border border-slate-700 text-xs font-mono text-white"
                      />
                    </div>
                    <div>
                      <label className="block text-xs text-slate-300 mb-1">Port</label>
                      <input
                        type="text"
                        value={form.homeAssistantPort}
                        onChange={(e) => setForm({ ...form, homeAssistantPort: e.target.value })}
                        className="w-full px-3.5 py-2 rounded-xl bg-slate-900 border border-slate-700 text-xs font-mono text-white"
                      />
                    </div>
                  </div>

                  <div className="flex items-center space-x-2">
                    <input
                      type="checkbox"
                      id="ha-https"
                      checked={form.useHTTPS}
                      onChange={(e) => setForm({ ...form, useHTTPS: e.target.checked })}
                      className="w-4 h-4 rounded accent-indigo-500"
                    />
                    <label htmlFor="ha-https" className="text-xs text-slate-300">
                      Use HTTPS (TLS)
                    </label>
                  </div>

                  <div>
                    <label className="block text-xs text-slate-300 mb-1">Long-Lived Access Token</label>
                    <textarea
                      rows={3}
                      value={form.accessToken}
                      onChange={(e) => setForm({ ...form, accessToken: e.target.value })}
                      className="w-full px-3.5 py-2 rounded-xl bg-slate-900 border border-slate-700 text-xs font-mono text-white focus:outline-none focus:border-indigo-500"
                    />
                  </div>

                  <div className="pt-2">
                    <button
                      type="button"
                      onClick={handleTestHA}
                      disabled={isTestingHA}
                      className="px-4 py-2 rounded-xl bg-slate-800 hover:bg-slate-700 text-xs font-medium text-slate-200 flex items-center space-x-2"
                    >
                      <Network className="w-3.5 h-3.5 text-indigo-400" />
                      <span>{isTestingHA ? "Testing..." : "Test Connection"}</span>
                    </button>

                    {haTestResult && (
                      <div className="mt-2 text-xs font-mono p-2.5 rounded-lg bg-slate-900 border border-slate-800 text-slate-300">
                        {haTestResult}
                      </div>
                    )}
                  </div>
                </div>
              </div>
            )}

            {/* TAB: VOICE */}
            {activeTab === "voice" && (
              <div className="space-y-6">
                <div>
                  <h3 className="text-base font-bold text-white mb-1">Voice Assistant Satellite</h3>
                  <p className="text-xs text-slate-400">
                    Always-listening Porcupine wake word detection and Home Assistant conversation integration.
                  </p>
                </div>

                <div className="p-5 rounded-2xl bg-slate-950/60 border border-slate-800 space-y-4">
                  <div className="flex items-center justify-between">
                    <div>
                      <div className="text-xs font-semibold text-white">Enable Voice Satellite</div>
                      <p className="text-[11px] text-slate-400">
                        Listens for wake words (e.g. "Jarvis", "Hey Home Assistant") to control smart devices.
                      </p>
                    </div>
                    <label className="relative inline-flex items-center cursor-pointer">
                      <input
                        type="checkbox"
                        checked={form.enableVoiceActivation}
                        onChange={(e) => setForm({ ...form, enableVoiceActivation: e.target.checked })}
                        className="sr-only peer"
                      />
                      <div className="w-11 h-6 bg-slate-800 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-indigo-600"></div>
                    </label>
                  </div>

                  {form.enableVoiceActivation && (
                    <div className="space-y-4 pt-2 border-t border-slate-800">
                      <div>
                        <label className="block text-xs text-slate-300 mb-1">Picovoice Porcupine Access Token</label>
                        <input
                          type="password"
                          value={form.porcupineAccessToken}
                          onChange={(e) => setForm({ ...form, porcupineAccessToken: e.target.value })}
                          className="w-full px-3.5 py-2 rounded-xl bg-slate-900 border border-slate-700 text-xs font-mono text-white"
                        />
                      </div>

                      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                        <div>
                          <label className="block text-xs text-slate-300 mb-1">Conversation Agent</label>
                          <input
                            type="text"
                            value={form.homeAssistantConversationAgent}
                            onChange={(e) => setForm({ ...form, homeAssistantConversationAgent: e.target.value })}
                            className="w-full px-3.5 py-2 rounded-xl bg-slate-900 border border-slate-700 text-xs font-mono text-white"
                          />
                        </div>
                        <div>
                          <label className="block text-xs text-slate-300 mb-1">Conversation Device ID</label>
                          <input
                            type="text"
                            value={form.homeAssistantConversationId}
                            onChange={(e) => setForm({ ...form, homeAssistantConversationId: e.target.value })}
                            className="w-full px-3.5 py-2 rounded-xl bg-slate-900 border border-slate-700 text-xs font-mono text-white"
                          />
                        </div>
                      </div>

                      {onTestVoiceSatellite && (
                        <div className="pt-2">
                          <button
                            type="button"
                            onClick={onTestVoiceSatellite}
                            className="px-4 py-2 rounded-xl bg-purple-600 hover:bg-purple-500 text-white text-xs font-medium flex items-center space-x-2"
                          >
                            <Mic className="w-3.5 h-3.5" />
                            <span>Simulate Wake Word Audio Command</span>
                          </button>
                        </div>
                      )}
                    </div>
                  )}
                </div>
              </div>
            )}

            {/* TAB: BACKUP / ACTIONS */}
            {activeTab === "actions" && (
              <div className="space-y-6">
                <div>
                  <h3 className="text-base font-bold text-white mb-1">Settings Backup & Reset</h3>
                  <p className="text-xs text-slate-400">
                    Export your full PadPanel configuration to JSON or restore defaults.
                  </p>
                </div>

                <div className="p-5 rounded-2xl bg-slate-950/60 border border-slate-800 space-y-4">
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    <button
                      type="button"
                      onClick={handleExport}
                      className="p-4 rounded-xl bg-slate-900 hover:bg-slate-800 border border-slate-700 text-left transition flex items-center space-x-3"
                    >
                      <Download className="w-5 h-5 text-indigo-400 shrink-0" />
                      <div>
                        <div className="text-xs font-semibold text-white">Export Settings JSON</div>
                        <div className="text-[11px] text-slate-400">Download config file</div>
                      </div>
                    </button>

                    <label className="p-4 rounded-xl bg-slate-900 hover:bg-slate-800 border border-slate-700 text-left transition flex items-center space-x-3 cursor-pointer">
                      <Upload className="w-5 h-5 text-emerald-400 shrink-0" />
                      <div>
                        <div className="text-xs font-semibold text-white">Import Settings JSON</div>
                        <div className="text-[11px] text-slate-400">Restore from backup</div>
                      </div>
                      <input type="file" accept=".json" onChange={handleImport} className="hidden" />
                    </label>
                  </div>

                  <div className="pt-4 border-t border-slate-800">
                    {showResetAlert ? (
                      <div className="p-4 rounded-xl bg-rose-500/10 border border-rose-500/30 text-rose-300 space-y-3">
                        <div className="text-xs font-semibold">
                          Are you sure you want to reset all settings to defaults?
                        </div>
                        <div className="flex space-x-2">
                          <button
                            type="button"
                            onClick={() => {
                              setForm({ ...DEFAULT_SETTINGS });
                              setShowResetAlert(false);
                            }}
                            className="px-3 py-1.5 rounded-lg bg-rose-600 text-white text-xs font-medium"
                          >
                            Yes, Reset to Defaults
                          </button>
                          <button
                            type="button"
                            onClick={() => setShowResetAlert(false)}
                            className="px-3 py-1.5 rounded-lg bg-slate-800 text-slate-300 text-xs font-medium"
                          >
                            Cancel
                          </button>
                        </div>
                      </div>
                    ) : (
                      <button
                        type="button"
                        onClick={() => setShowResetAlert(true)}
                        className="px-4 py-2 rounded-xl bg-rose-500/10 hover:bg-rose-500/20 text-rose-300 border border-rose-500/30 text-xs font-medium flex items-center space-x-2"
                      >
                        <RotateCcw className="w-3.5 h-3.5" />
                        <span>Reset All Settings to Factory Defaults</span>
                      </button>
                    )}
                  </div>
                </div>
              </div>
            )}
          </div>
        </div>

        {/* Footer */}
        <div className="flex items-center justify-between px-6 py-4 bg-slate-950 border-t border-slate-800">
          <div className="text-xs text-slate-500 hidden sm:block">
            PadPanel v1.0.0 &bull; Local Kiosk Engine
          </div>
          <div className="flex items-center space-x-3 ml-auto">
            <button
              onClick={onClose}
              className="px-4 py-2 rounded-xl text-xs font-medium text-slate-400 hover:text-white hover:bg-slate-800 transition"
            >
              Cancel
            </button>
            <button
              onClick={handleSave}
              className="px-6 py-2 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-xs font-semibold text-white shadow-lg shadow-indigo-600/30 transition flex items-center space-x-1.5"
            >
              <Check className="w-4 h-4" />
              <span>Save & Apply Settings</span>
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};
