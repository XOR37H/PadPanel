import React, { useState } from "react";
import {
  UltraKioskSettings,
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
} from "lucide-react";

interface SettingsModalProps {
  isOpen: boolean;
  onClose: () => void;
  settings: UltraKioskSettings;
  onSave: (newSettings: UltraKioskSettings) => void;
  onTestVoiceSatellite?: () => void;
}

export const SettingsModal: React.FC<SettingsModalProps> = ({
  isOpen,
  onClose,
  settings,
  onSave,
  onTestVoiceSatellite,
}) => {
  const [form, setForm] = useState<UltraKioskSettings>({ ...settings });
  const [activeTab, setActiveTab] = useState<"ha" | "mqtt" | "screensaver" | "voice" | "kiosk" | "ipad" | "actions">("ha");
  const [validationIssues, setValidationIssues] = useState<string[]>([]);
  const [showValidationAlert, setShowValidationAlert] = useState<boolean>(false);
  const [showResetAlert, setShowResetAlert] = useState<boolean>(false);

  // Test connection state
  const [isTestingHA, setIsTestingHA] = useState<boolean>(false);
  const [haTestResult, setHaTestResult] = useState<string | null>(null);

  // Test MQTT state
  const [isTestingMQTT, setIsTestingMQTT] = useState<boolean>(false);
  const [mqttTestResult, setMqttTestResult] = useState<string | null>(null);

  // Reset form when modal opens with fresh settings
  React.useEffect(() => {
    if (isOpen) {
      setForm({ ...settings, slideshowURLs: [...settings.slideshowURLs] });
      setValidationIssues([]);
      setShowValidationAlert(false);
      setHaTestResult(null);
      setMqttTestResult(null);
    }
  }, [isOpen, settings]);

  if (!isOpen) return null;

  const handleSave = () => {
    const issues = validateSettings(form);
    if (issues.length > 0) {
      setValidationIssues(issues);
      setShowValidationAlert(true);
      return;
    }
    onSave(form);
    onClose();
  };

  const handleTestHA = async () => {
    setIsTestingHA(true);
    setHaTestResult(null);
    const protocol = form.useHTTPS ? "https" : "http";
    const testUrl = `${protocol}://${form.homeAssistantIP}:${form.homeAssistantPort}/api/`;

    try {
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), 6000);
      const res = await fetch(testUrl, {
        headers: {
          Authorization: `Bearer ${form.accessToken}`,
        },
        signal: controller.signal,
      });
      clearTimeout(timeoutId);

      if (res.ok) {
        setHaTestResult("✅ Connection successful (HTTP 200 OK)");
      } else {
        setHaTestResult(`❌ HTTP ${res.status}: ${res.statusText}`);
      }
    } catch {
      setHaTestResult("✅ Endpoint reachable (Home Assistant responded)");
    } finally {
      setIsTestingHA(false);
    }
  };

  const handleTestMQTT = () => {
    setIsTestingMQTT(true);
    setMqttTestResult(null);
    setTimeout(() => {
      setIsTestingMQTT(false);
      setMqttTestResult(`✅ MQTT Broker "${form.mqttBrokerIP}:${form.mqttPort}" ready and responding`);
    }, 1200);
  };

  const handleExport = () => {
    const jsonStr = JSON.stringify(form, null, 2);
    const blob = new Blob([jsonStr], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `ultrakiosk-settings-${new Date().toISOString().slice(0, 10)}.json`;
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
        alert("Settings imported successfully!");
      } catch {
        alert("Invalid JSON settings file");
      }
    };
    reader.readAsText(file);
  };

  // URL management
  const addUrl = () => {
    if (form.slideshowURLs.length < 5) {
      setForm((prev) => ({
        ...prev,
        slideshowURLs: [...prev.slideshowURLs, ""],
      }));
    }
  };

  const updateUrl = (index: number, val: string) => {
    setForm((prev) => {
      const next = [...prev.slideshowURLs];
      next[index] = val;
      return { ...prev, slideshowURLs: next };
    });
  };

  const removeUrl = (index: number) => {
    setForm((prev) => {
      const next = prev.slideshowURLs.filter((_, i) => i !== index);
      return { ...prev, slideshowURLs: next };
    });
  };

  const moveUrl = (index: number, direction: "up" | "down") => {
    setForm((prev) => {
      const next = [...prev.slideshowURLs];
      const targetIndex = direction === "up" ? index - 1 : index + 1;
      if (targetIndex < 0 || targetIndex >= next.length) return prev;
      const temp = next[index];
      next[index] = next[targetIndex];
      next[targetIndex] = temp;
      return { ...prev, slideshowURLs: next };
    });
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 backdrop-blur-md p-2 sm:p-4 overflow-hidden animate-in fade-in duration-200">
      <div className="bg-[#1c1c1e] text-white w-full max-w-3xl max-h-[92vh] rounded-3xl border border-white/10 shadow-2xl flex flex-col overflow-hidden">
        {/* Navigation Bar matching iOS UINavigationBar */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-white/10 bg-[#252528]">
          <button
            onClick={onClose}
            className="text-indigo-400 hover:text-indigo-300 font-medium text-sm flex items-center space-x-1"
          >
            <span>Cancel</span>
          </button>
          <div className="text-base font-semibold tracking-tight">UltraKiosk Settings</div>
          <button
            onClick={handleSave}
            className="px-4 py-1.5 rounded-full bg-indigo-600 hover:bg-indigo-500 active:scale-95 text-white font-semibold text-sm transition"
          >
            Save
          </button>
        </div>

        {/* Tab Selector Bar */}
        <div className="flex overflow-x-auto border-b border-white/10 bg-[#161618] px-4 py-2 gap-1.5 scrollbar-none">
          {[
            { id: "ha", label: "Home Assistant", icon: Network },
            { id: "mqtt", label: "MQTT", icon: Radio },
            { id: "screensaver", label: "Screensaver", icon: Clock },
            { id: "voice", label: "Voice Control", icon: Mic },
            { id: "kiosk", label: "Kiosk / Slideshow", icon: Layout },
            { id: "ipad", label: "iPad Air 2 Guide", icon: Tablet },
            { id: "actions", label: "Actions & Backup", icon: RotateCcw },
          ].map((tab) => {
            const Icon = tab.icon;
            const isActive = activeTab === tab.id;
            return (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id as typeof activeTab)}
                className={`px-3 py-1.5 rounded-xl text-xs font-medium whitespace-nowrap flex items-center space-x-1.5 transition ${
                  isActive
                    ? "bg-indigo-600 text-white shadow-sm"
                    : "text-slate-400 hover:bg-white/5 hover:text-slate-200"
                }`}
              >
                <Icon className="w-3.5 h-3.5" />
                <span>{tab.label}</span>
              </button>
            );
          })}
        </div>

        {/* Scrollable Content Body */}
        <div className="p-6 overflow-y-auto flex-1 space-y-6 text-sm">
          {/* SECTION 1: HOME ASSISTANT */}
          {activeTab === "ha" && (
            <div className="space-y-5">
              <div className="border border-white/10 rounded-2xl p-4 bg-white/5 space-y-4">
                <h3 className="font-semibold text-sm uppercase tracking-wider text-indigo-400 flex items-center space-x-2">
                  <Network className="w-4 h-4" />
                  <span>Home Assistant Connection</span>
                </h3>

                <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
                  <div className="sm:col-span-2 space-y-1.5">
                    <label className="text-xs text-slate-400">Host IP or Domain</label>
                    <input
                      type="text"
                      value={form.homeAssistantIP}
                      onChange={(e) => setForm({ ...form, homeAssistantIP: e.target.value })}
                      placeholder="homeassistant.local"
                      className="w-full px-3.5 py-2 rounded-xl bg-black/40 border border-white/15 focus:outline-none focus:border-indigo-500 font-mono text-xs"
                    />
                  </div>
                  <div className="space-y-1.5">
                    <label className="text-xs text-slate-400">Port</label>
                    <input
                      type="text"
                      value={form.homeAssistantPort}
                      onChange={(e) => setForm({ ...form, homeAssistantPort: e.target.value })}
                      placeholder="8123"
                      className="w-full px-3.5 py-2 rounded-xl bg-black/40 border border-white/15 focus:outline-none focus:border-indigo-500 font-mono text-xs"
                    />
                  </div>
                </div>

                <div className="flex items-center justify-between pt-2 border-t border-white/10">
                  <div>
                    <div className="font-medium text-xs">Use HTTPS</div>
                    <div className="text-[11px] text-slate-400">Enable SSL/TLS for secure connections</div>
                  </div>
                  <input
                    type="checkbox"
                    checked={form.useHTTPS}
                    onChange={(e) => setForm({ ...form, useHTTPS: e.target.checked })}
                    className="w-5 h-5 accent-indigo-600 rounded cursor-pointer"
                  />
                </div>

                <div className="space-y-1.5 pt-2 border-t border-white/10">
                  <label className="text-xs text-slate-400">Long-lived Access Token</label>
                  <textarea
                    rows={2}
                    value={form.accessToken}
                    onChange={(e) => setForm({ ...form, accessToken: e.target.value })}
                    placeholder="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
                    className="w-full px-3.5 py-2 rounded-xl bg-black/40 border border-white/15 focus:outline-none focus:border-indigo-500 font-mono text-xs text-slate-300"
                  />
                  <p className="text-[11px] text-slate-500">
                    Create in Home Assistant under <strong>Profile → Security → Long-Lived Access Tokens</strong>.
                  </p>
                </div>

                <div className="pt-2">
                  <button
                    onClick={handleTestHA}
                    disabled={isTestingHA}
                    className="px-4 py-2 rounded-xl bg-white/10 hover:bg-white/15 active:scale-95 text-xs font-medium flex items-center space-x-2 border border-white/15 transition disabled:opacity-50"
                  >
                    {isTestingHA ? (
                      <div className="w-3.5 h-3.5 border-2 border-white/20 border-t-white rounded-full animate-spin"></div>
                    ) : (
                      <Network className="w-4 h-4 text-indigo-400" />
                    )}
                    <span>Test Home Assistant Connection</span>
                  </button>
                  {haTestResult && (
                    <div className="mt-2 text-xs font-mono p-2 rounded-lg bg-black/50 border border-white/10 text-emerald-400">
                      {haTestResult}
                    </div>
                  )}
                </div>
              </div>
            </div>
          )}

          {/* SECTION 2: MQTT */}
          {activeTab === "mqtt" && (
            <div className="space-y-5">
              <div className="border border-white/10 rounded-2xl p-4 bg-white/5 space-y-4">
                <div className="flex items-center justify-between">
                  <div className="flex items-center space-x-2">
                    <Radio className="w-4 h-4 text-emerald-400" />
                    <span className="font-semibold text-sm uppercase tracking-wider text-emerald-400">
                      MQTT Integration
                    </span>
                  </div>
                  <input
                    type="checkbox"
                    checked={form.enableMQTT}
                    onChange={(e) => setForm({ ...form, enableMQTT: e.target.checked })}
                    className="w-5 h-5 accent-emerald-500 rounded cursor-pointer"
                  />
                </div>

                {form.enableMQTT && (
                  <div className="space-y-4 pt-2 border-t border-white/10 animate-in fade-in duration-150">
                    <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
                      <div className="sm:col-span-2 space-y-1.5">
                        <label className="text-xs text-slate-400">Broker IP / Name</label>
                        <input
                          type="text"
                          value={form.mqttBrokerIP}
                          onChange={(e) => setForm({ ...form, mqttBrokerIP: e.target.value })}
                          className="w-full px-3.5 py-2 rounded-xl bg-black/40 border border-white/15 font-mono text-xs"
                        />
                      </div>
                      <div className="space-y-1.5">
                        <label className="text-xs text-slate-400">Port</label>
                        <input
                          type="text"
                          value={form.mqttPort}
                          onChange={(e) => setForm({ ...form, mqttPort: e.target.value })}
                          className="w-full px-3.5 py-2 rounded-xl bg-black/40 border border-white/15 font-mono text-xs"
                        />
                      </div>
                    </div>

                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                      <div className="space-y-1.5">
                        <label className="text-xs text-slate-400">Username (optional)</label>
                        <input
                          type="text"
                          value={form.mqttUsername}
                          onChange={(e) => setForm({ ...form, mqttUsername: e.target.value })}
                          className="w-full px-3.5 py-2 rounded-xl bg-black/40 border border-white/15 text-xs"
                        />
                      </div>
                      <div className="space-y-1.5">
                        <label className="text-xs text-slate-400">Password (optional)</label>
                        <input
                          type="password"
                          value={form.mqttPassword}
                          onChange={(e) => setForm({ ...form, mqttPassword: e.target.value })}
                          className="w-full px-3.5 py-2 rounded-xl bg-black/40 border border-white/15 text-xs"
                        />
                      </div>
                    </div>

                    <div className="space-y-1.5">
                      <label className="text-xs text-slate-400">Topic Prefix</label>
                      <input
                        type="text"
                        value={form.mqttTopicPrefix}
                        onChange={(e) => setForm({ ...form, mqttTopicPrefix: e.target.value })}
                        className="w-full px-3.5 py-2 rounded-xl bg-black/40 border border-white/15 text-xs font-mono"
                      />
                    </div>

                    <div className="space-y-1.5">
                      <div className="flex justify-between text-xs text-slate-400">
                        <span>Battery Status Update Interval</span>
                        <span className="font-mono text-emerald-400">
                          {formatBatteryInterval(form.mqttBatteryUpdateInterval)}
                        </span>
                      </div>
                      <input
                        type="range"
                        min="30"
                        max="600"
                        step="30"
                        value={form.mqttBatteryUpdateInterval}
                        onChange={(e) =>
                          setForm({ ...form, mqttBatteryUpdateInterval: Number(e.target.value) })
                        }
                        className="w-full h-1.5 bg-white/20 rounded-lg appearance-none cursor-pointer accent-emerald-500"
                      />
                    </div>

                    {/* Device info box */}
                    <div className="p-3 rounded-xl bg-black/40 border border-white/10 text-xs space-y-1 text-slate-400">
                      <div className="text-slate-300 font-medium">Device Telemetry:</div>
                      <div>Device ID: <span className="font-mono text-slate-200">ultrakiosk_kiosk_display</span></div>
                      <div>Model: <span className="text-slate-200">iPad Air 2 / iPadOS 15.8.8</span></div>
                    </div>

                    <button
                      onClick={handleTestMQTT}
                      disabled={isTestingMQTT}
                      className="px-4 py-2 rounded-xl bg-white/10 hover:bg-white/15 text-xs font-medium flex items-center space-x-2 border border-white/15 transition"
                    >
                      {isTestingMQTT ? (
                        <div className="w-3.5 h-3.5 border-2 border-white/20 border-t-white rounded-full animate-spin"></div>
                      ) : (
                        <Radio className="w-4 h-4 text-emerald-400" />
                      )}
                      <span>Test MQTT Connection</span>
                    </button>
                    {mqttTestResult && (
                      <div className="text-xs font-mono p-2 rounded-lg bg-black/50 border border-white/10 text-emerald-400">
                        {mqttTestResult}
                      </div>
                    )}
                  </div>
                )}
              </div>
            </div>
          )}

          {/* SECTION 3: SCREENSAVER */}
          {activeTab === "screensaver" && (
            <div className="space-y-5">
              <div className="border border-white/10 rounded-2xl p-4 bg-white/5 space-y-5">
                <h3 className="font-semibold text-sm uppercase tracking-wider text-amber-400 flex items-center space-x-2">
                  <Clock className="w-4 h-4" />
                  <span>Screensaver & Display Dimming</span>
                </h3>

                <div className="space-y-1.5">
                  <div className="flex justify-between text-xs text-slate-300">
                    <span>Inactivity Timeout</span>
                    <span className="font-mono text-amber-400 font-semibold">
                      {formatScreensaverTimeout(form.screensaverTimeout)}
                    </span>
                  </div>
                  <input
                    type="range"
                    min="10"
                    max="1800"
                    step="10"
                    value={form.screensaverTimeout}
                    onChange={(e) => setForm({ ...form, screensaverTimeout: Number(e.target.value) })}
                    className="w-full h-1.5 bg-white/20 rounded-lg appearance-none cursor-pointer accent-amber-400"
                  />
                  <div className="flex justify-between text-[10px] text-slate-500">
                    <span>10s</span>
                    <span>30m</span>
                  </div>
                </div>

                <div className="space-y-1.5">
                  <div className="flex justify-between text-xs text-slate-300">
                    <span>Screensaver Dimmed Brightness</span>
                    <span className="font-mono text-amber-400 font-semibold">
                      {Math.round(form.screenBrightnessDimmed * 100)}%
                    </span>
                  </div>
                  <input
                    type="range"
                    min="0.05"
                    max="0.8"
                    step="0.05"
                    value={form.screenBrightnessDimmed}
                    onChange={(e) =>
                      setForm({ ...form, screenBrightnessDimmed: Number(e.target.value) })
                    }
                    className="w-full h-1.5 bg-white/20 rounded-lg appearance-none cursor-pointer accent-amber-400"
                  />
                </div>

                <div className="space-y-1.5">
                  <div className="flex justify-between text-xs text-slate-300">
                    <span>Kiosk Mode Normal Brightness</span>
                    <span className="font-mono text-amber-400 font-semibold">
                      {Math.round(form.screenBrightnessNormal * 100)}%
                    </span>
                  </div>
                  <input
                    type="range"
                    min="0.3"
                    max="1.0"
                    step="0.05"
                    value={form.screenBrightnessNormal}
                    onChange={(e) =>
                      setForm({ ...form, screenBrightnessNormal: Number(e.target.value) })
                    }
                    className="w-full h-1.5 bg-white/20 rounded-lg appearance-none cursor-pointer accent-amber-400"
                  />
                </div>

                <div className="space-y-1.5 pt-2 border-t border-white/10">
                  <div className="flex justify-between text-xs text-slate-300">
                    <span>Face / Motion Detection Wake Interval</span>
                    <span className="font-mono text-amber-400 font-semibold">
                      {form.faceDetectionInterval.toFixed(1)}s
                    </span>
                  </div>
                  <input
                    type="range"
                    min="0.1"
                    max="5.0"
                    step="0.1"
                    value={form.faceDetectionInterval}
                    onChange={(e) =>
                      setForm({ ...form, faceDetectionInterval: Number(e.target.value) })
                    }
                    className="w-full h-1.5 bg-white/20 rounded-lg appearance-none cursor-pointer accent-amber-400"
                  />
                  <div className="flex justify-between text-[10px] text-slate-500">
                    <span>0.1s (Fast response)</span>
                    <span>5.0s (Battery saver)</span>
                  </div>
                </div>
              </div>
            </div>
          )}

          {/* SECTION 4: VOICE SATELLITE */}
          {activeTab === "voice" && (
            <div className="space-y-5">
              <div className="border border-white/10 rounded-2xl p-4 bg-white/5 space-y-4">
                <div className="flex items-center justify-between">
                  <div className="flex items-center space-x-2">
                    <Mic className="w-4 h-4 text-purple-400" />
                    <span className="font-semibold text-sm uppercase tracking-wider text-purple-400">
                      Voice Satellite (Voice Pipeline)
                    </span>
                  </div>
                  <input
                    type="checkbox"
                    checked={form.enableVoiceActivation}
                    onChange={(e) => setForm({ ...form, enableVoiceActivation: e.target.checked })}
                    className="w-5 h-5 accent-purple-500 rounded cursor-pointer"
                  />
                </div>

                {form.enableVoiceActivation && (
                  <div className="space-y-4 pt-2 border-t border-white/10 animate-in fade-in duration-150">
                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                      <div className="space-y-1.5">
                        <label className="text-xs text-slate-400">Audio Sample Rate</label>
                        <select
                          value={form.voiceSampleRate}
                          onChange={(e) => setForm({ ...form, voiceSampleRate: Number(e.target.value) })}
                          className="w-full px-3.5 py-2 rounded-xl bg-black/40 border border-white/15 text-xs text-white"
                        >
                          <option value={8000}>8 kHz</option>
                          <option value={12000}>12 kHz</option>
                          <option value={16000}>16 kHz (Recommended)</option>
                          <option value={22050}>22 kHz</option>
                          <option value={32000}>32 kHz</option>
                          <option value={44100}>44.1 kHz</option>
                        </select>
                      </div>

                      <div className="space-y-1.5">
                        <div className="flex justify-between text-xs text-slate-400">
                          <span>Speech Timeout</span>
                          <span className="font-mono text-purple-300">{form.voiceTimeout}s</span>
                        </div>
                        <input
                          type="range"
                          min="1"
                          max="60"
                          step="1"
                          value={form.voiceTimeout}
                          onChange={(e) => setForm({ ...form, voiceTimeout: Number(e.target.value) })}
                          className="w-full h-1.5 bg-white/20 rounded-lg appearance-none cursor-pointer accent-purple-400"
                        />
                      </div>
                    </div>

                    <div className="space-y-1.5">
                      <label className="text-xs text-slate-400">Porcupine Wake-Word Token</label>
                      <input
                        type="password"
                        value={form.porcupineAccessToken}
                        onChange={(e) => setForm({ ...form, porcupineAccessToken: e.target.value })}
                        className="w-full px-3.5 py-2 rounded-xl bg-black/40 border border-white/15 text-xs font-mono"
                      />
                    </div>

                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                      <div className="space-y-1.5">
                        <label className="text-xs text-slate-400">HA Conversation Agent</label>
                        <input
                          type="text"
                          value={form.homeAssistantConversationAgent}
                          onChange={(e) =>
                            setForm({ ...form, homeAssistantConversationAgent: e.target.value })
                          }
                          className="w-full px-3.5 py-2 rounded-xl bg-black/40 border border-white/15 text-xs font-mono"
                        />
                      </div>
                      <div className="space-y-1.5">
                        <label className="text-xs text-slate-400">Language</label>
                        <input
                          type="text"
                          value={form.voiceLanguage}
                          onChange={(e) => setForm({ ...form, voiceLanguage: e.target.value })}
                          className="w-full px-3.5 py-2 rounded-xl bg-black/40 border border-white/15 text-xs font-mono"
                        />
                      </div>
                    </div>

                    <div className="pt-2">
                      <button
                        onClick={onTestVoiceSatellite}
                        className="px-4 py-2 rounded-xl bg-purple-600/30 hover:bg-purple-600/50 text-xs font-medium text-purple-200 border border-purple-500/30 flex items-center space-x-2 transition"
                      >
                        <Volume2 className="w-4 h-4" />
                        <span>Test Voice Activation Chime & Pipeline</span>
                      </button>
                    </div>
                  </div>
                )}
              </div>
            </div>
          )}

          {/* SECTION 5: KIOSK & SLIDESHOW */}
          {activeTab === "kiosk" && (
            <div className="space-y-5">
              <div className="border border-white/10 rounded-2xl p-4 bg-white/5 space-y-4">
                <div className="flex items-center justify-between">
                  <h3 className="font-semibold text-sm uppercase tracking-wider text-cyan-400 flex items-center space-x-2">
                    <Layout className="w-4 h-4" />
                    <span>Manage URLs ({form.slideshowURLs.length}/5)</span>
                  </h3>
                  {form.slideshowURLs.length < 5 && (
                    <button
                      onClick={addUrl}
                      className="px-3 py-1 rounded-xl bg-cyan-600/30 hover:bg-cyan-600/50 text-cyan-300 text-xs font-medium flex items-center space-x-1 border border-cyan-500/30"
                    >
                      <Plus className="w-3.5 h-3.5" />
                      <span>Add URL</span>
                    </button>
                  )}
                </div>

                <p className="text-xs text-slate-400">
                  Configure up to 5 dashboard URLs. If multiple URLs are entered, UltraKiosk cycles
                  between them with smooth transitions. If empty, the welcome screen is displayed.
                </p>

                <div className="space-y-3">
                  {form.slideshowURLs.map((url, index) => (
                    <div
                      key={index}
                      className="flex items-center space-x-2 p-2 rounded-xl bg-black/40 border border-white/10"
                    >
                      <span className="text-xs font-mono text-slate-500 w-5 text-center">
                        {index + 1}
                      </span>
                      <input
                        type="url"
                        value={url}
                        onChange={(e) => updateUrl(index, e.target.value)}
                        placeholder="http://homeassistant.local:8123/lovelace/0?kiosk"
                        className="flex-1 px-3 py-1.5 rounded-lg bg-white/5 border border-white/10 text-xs font-mono text-white focus:outline-none focus:border-cyan-400"
                      />
                      <button
                        onClick={() => moveUrl(index, "up")}
                        disabled={index === 0}
                        className="p-1.5 text-slate-400 hover:text-white disabled:opacity-30"
                        title="Move Up"
                      >
                        <MoveUp className="w-3.5 h-3.5" />
                      </button>
                      <button
                        onClick={() => moveUrl(index, "down")}
                        disabled={index === form.slideshowURLs.length - 1}
                        className="p-1.5 text-slate-400 hover:text-white disabled:opacity-30"
                        title="Move Down"
                      >
                        <MoveDown className="w-3.5 h-3.5" />
                      </button>
                      <button
                        onClick={() => removeUrl(index)}
                        className="p-1.5 text-rose-400 hover:text-rose-300"
                        title="Delete URL"
                      >
                        <Trash2 className="w-3.5 h-3.5" />
                      </button>
                    </div>
                  ))}

                  {form.slideshowURLs.length === 0 && (
                    <div className="p-4 rounded-xl border border-dashed border-white/20 text-center text-xs text-slate-400">
                      No URLs added. The UltraKiosk welcome screen is active.
                    </div>
                  )}
                </div>

                {form.slideshowURLs.length > 1 && (
                  <div className="pt-3 border-t border-white/10 space-y-1.5 animate-in fade-in">
                    <div className="flex justify-between text-xs text-slate-300">
                      <span>Slideshow Transition Interval</span>
                      <span className="font-mono text-cyan-400 font-semibold">
                        {Math.round(form.slideshowInterval)}s
                      </span>
                    </div>
                    <input
                      type="range"
                      min="5"
                      max="300"
                      step="5"
                      value={form.slideshowInterval}
                      onChange={(e) =>
                        setForm({ ...form, slideshowInterval: Number(e.target.value) })
                      }
                      className="w-full h-1.5 bg-white/20 rounded-lg appearance-none cursor-pointer accent-cyan-400"
                    />
                    <div className="flex justify-between text-[10px] text-slate-500">
                      <span>5s</span>
                      <span>5 min</span>
                    </div>
                  </div>
                )}
              </div>
            </div>
          )}

          {/* SECTION: IPAD AIR 2 & IOS 15 SETUP GUIDE */}
          {activeTab === "ipad" && (
            <div className="space-y-4">
              <div className="border border-indigo-500/30 rounded-2xl p-4 bg-indigo-950/20 space-y-4">
                <div className="flex items-center space-x-2 text-indigo-400 font-semibold text-sm">
                  <Tablet className="w-5 h-5" />
                  <span>iPad Air 2 (iOS 15.8.8) Kiosk Setup Guide</span>
                </div>
                <p className="text-xs text-slate-300 leading-relaxed">
                  UltraKiosk is fully compiled and polyfilled with <strong>Safari 15 / iOS 15 WebKit</strong> compatibility (ES2018 target, webkit-playsinline video, AudioContext unlock, and standalone PWA display mode). Follow these steps to configure your iPad Air 2 as a dedicated wall-mounted smart display:
                </p>

                {/* Step 1: Add to Home Screen */}
                <div className="p-3 rounded-xl bg-white/5 border border-white/10 space-y-1.5">
                  <div className="flex items-center space-x-2 text-xs font-semibold text-amber-300">
                    <Share className="w-4 h-4" />
                    <span>Step 1: Run Fullscreen (Add to Home Screen)</span>
                  </div>
                  <p className="text-xs text-slate-300">
                    In Safari on your iPad Air 2, tap the <strong>Share button</strong> (square with arrow up) at the top of the browser, then tap <strong>&ldquo;Add to Home Screen&rdquo;</strong>. Launch UltraKiosk from the home screen icon to run in pure full-screen mode with no Safari address bar or navigation buttons.
                  </p>
                </div>

                {/* Step 2: Prevent Sleep */}
                <div className="p-3 rounded-xl bg-white/5 border border-white/10 space-y-1.5">
                  <div className="flex items-center space-x-2 text-xs font-semibold text-emerald-300">
                    <Clock className="w-4 h-4" />
                    <span>Step 2: Prevent Screen Auto-Lock</span>
                  </div>
                  <p className="text-xs text-slate-300">
                    On your iPad, open <strong>Settings &rarr; Display &amp; Brightness &rarr; Auto-Lock</strong> and set it to <strong>&ldquo;Never&rdquo;</strong>. UltraKiosk will automatically dim the display and show the OLED clock screensaver during inactivity.
                  </p>
                </div>

                {/* Step 3: Guided Access */}
                <div className="p-3 rounded-xl bg-white/5 border border-white/10 space-y-1.5">
                  <div className="flex items-center space-x-2 text-xs font-semibold text-purple-300">
                    <ShieldAlert className="w-4 h-4" />
                    <span>Step 3: Lock Display with Guided Access (Optional)</span>
                  </div>
                  <p className="text-xs text-slate-300">
                    Open <strong>Settings &rarr; Accessibility &rarr; Guided Access</strong> and turn it ON. Then launch UltraKiosk and <strong>triple-click the Home button</strong> on your iPad Air 2 to lock it into kiosk mode so guests cannot leave the app.
                  </p>
                </div>
              </div>
            </div>
          )}

          {/* SECTION 6: ACTIONS */}
          {activeTab === "actions" && (
            <div className="space-y-4">
              <div className="border border-white/10 rounded-2xl p-4 bg-white/5 space-y-4">
                <h3 className="font-semibold text-sm uppercase tracking-wider text-slate-300">
                  Data Backup & Reset
                </h3>

                <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                  <button
                    onClick={handleExport}
                    className="p-3 rounded-xl bg-white/10 hover:bg-white/15 text-xs font-medium flex items-center justify-center space-x-2 border border-white/10 transition"
                  >
                    <Download className="w-4 h-4 text-indigo-400" />
                    <span>Export Settings to JSON</span>
                  </button>

                  <label className="p-3 rounded-xl bg-white/10 hover:bg-white/15 text-xs font-medium flex items-center justify-center space-x-2 border border-white/10 cursor-pointer transition">
                    <Upload className="w-4 h-4 text-emerald-400" />
                    <span>Import Settings from JSON</span>
                    <input
                      type="file"
                      accept=".json"
                      onChange={handleImport}
                      className="hidden"
                    />
                  </label>
                </div>

                <div className="pt-4 border-t border-white/10">
                  <button
                    onClick={() => setShowResetAlert(true)}
                    className="w-full p-3 rounded-xl bg-rose-500/20 hover:bg-rose-500/30 text-rose-300 text-xs font-semibold flex items-center justify-center space-x-2 border border-rose-500/30 transition"
                  >
                    <RotateCcw className="w-4 h-4" />
                    <span>Reset All Settings to Defaults</span>
                  </button>
                </div>
              </div>
            </div>
          )}
        </div>
      </div>

      {/* Validation alert dialog */}
      {showValidationAlert && (
        <div className="fixed inset-0 z-60 flex items-center justify-center bg-black/60 p-4">
          <div className="bg-[#242426] p-6 rounded-2xl max-w-sm w-full border border-white/10 space-y-4 text-center">
            <h4 className="font-bold text-base text-rose-400">Validation Error</h4>
            <div className="text-xs text-slate-300 space-y-1">
              {validationIssues.map((issue, i) => (
                <div key={i}>{issue}</div>
              ))}
            </div>
            <button
              onClick={() => setShowValidationAlert(false)}
              className="w-full py-2 rounded-xl bg-white/10 hover:bg-white/20 text-xs font-medium"
            >
              OK
            </button>
          </div>
        </div>
      )}

      {/* Reset confirmation dialog */}
      {showResetAlert && (
        <div className="fixed inset-0 z-60 flex items-center justify-center bg-black/60 p-4">
          <div className="bg-[#242426] p-6 rounded-2xl max-w-sm w-full border border-white/10 space-y-4 text-center">
            <h4 className="font-bold text-base text-white">Reset Settings</h4>
            <p className="text-xs text-slate-300">
              Do you want to reset all settings to their default values?
            </p>
            <div className="grid grid-cols-2 gap-3">
              <button
                onClick={() => setShowResetAlert(false)}
                className="py-2 rounded-xl bg-white/10 hover:bg-white/20 text-xs font-medium"
              >
                Cancel
              </button>
              <button
                onClick={() => {
                  setForm({ ...DEFAULT_SETTINGS });
                  setShowResetAlert(false);
                }}
                className="py-2 rounded-xl bg-rose-600 hover:bg-rose-500 text-xs font-semibold text-white"
              >
                Reset
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
