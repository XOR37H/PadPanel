import React, { useState } from "react";
import { UltraKioskSettings } from "../types/settings";
import {
  X,
  Radio,
  Send,
  CheckCircle,
  Sliders,
  ToggleLeft,
  ToggleRight,
  Layers,
  Power,
  Sun,
  RefreshCw,
  Cpu,
  Info,
} from "lucide-react";

interface MQTTInspectorModalProps {
  isOpen: boolean;
  onClose: () => void;
  settings: UltraKioskSettings;
  onUpdateSetting: (key: keyof UltraKioskSettings, value: any) => void;
  onTriggerAction: (action: "screensaver" | "wakeup" | "reload") => void;
  batteryLevel: number;
  isCharging: boolean;
  isScreensaverActive: boolean;
}

export const MQTTInspectorModal: React.FC<MQTTInspectorModalProps> = ({
  isOpen,
  onClose,
  settings,
  onUpdateSetting,
  onTriggerAction,
  batteryLevel,
  isCharging,
  isScreensaverActive,
}) => {
  const [lastActionLog, setLastActionLog] = useState<string | null>(null);

  if (!isOpen) return null;

  const deviceId = "ipad_kiosk_01";
  const prefix = settings.mqttTopicPrefix || "homeassistant";

  const logMqttEvent = (topic: string, payload: string) => {
    setLastActionLog(`[MQTT TX -> RX]: ${topic} -> "${payload}"`);
    setTimeout(() => setLastActionLog(null), 4000);
  };

  const handleCommand = (key: keyof UltraKioskSettings, value: any, topic: string) => {
    onUpdateSetting(key, value);
    logMqttEvent(topic, String(value));
  };

  const handleButtonPress = (action: "screensaver" | "wakeup" | "reload", topic: string) => {
    onTriggerAction(action);
    logMqttEvent(topic, "PRESS");
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-3 sm:p-6 bg-black/80 backdrop-blur-md">
      <div className="relative w-full max-w-3xl max-h-[90vh] bg-slate-900 border border-slate-700/80 rounded-2xl shadow-2xl flex flex-col overflow-hidden text-slate-100 font-sans">
        
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 bg-slate-950/90 border-b border-slate-800">
          <div className="flex items-center space-x-3">
            <div className="p-2 rounded-xl bg-emerald-500/10 border border-emerald-500/20">
              <Radio className="w-5 h-5 text-emerald-400 animate-pulse" />
            </div>
            <div>
              <h2 className="text-base font-bold text-white flex items-center space-x-2">
                <span>Home Assistant MQTT Entities & Tester</span>
                <span className="text-[10px] uppercase font-mono px-2 py-0.5 rounded-full bg-emerald-500/20 text-emerald-300 border border-emerald-500/30">
                  Active
                </span>
              </h2>
              <p className="text-xs text-slate-400 font-mono">
                Broker: {settings.mqttBrokerIP}:{settings.mqttPort} — Device: {deviceId}
              </p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="p-1.5 rounded-lg text-slate-400 hover:text-white hover:bg-slate-800 transition"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Live log banner */}
        {lastActionLog && (
          <div className="px-6 py-2 bg-indigo-950/60 border-b border-indigo-500/30 text-xs font-mono text-indigo-300 flex items-center space-x-2">
            <Send className="w-3.5 h-3.5 text-indigo-400" />
            <span>{lastActionLog}</span>
          </div>
        )}

        {/* Body */}
        <div className="flex-1 overflow-y-auto p-6 space-y-6">
          
          {/* Action Buttons */}
          <div className="p-4 rounded-xl bg-slate-950/60 border border-slate-800 space-y-3">
            <div className="text-xs font-semibold text-slate-300 flex items-center space-x-1.5">
              <Cpu className="w-4 h-4 text-indigo-400" />
              <span>MQTT Button Entities (Trigger over MQTT)</span>
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
              <button
                onClick={() => handleButtonPress("screensaver", `${prefix}/button/${deviceId}/screensaver/set`)}
                className="p-3 rounded-xl bg-slate-900 hover:bg-slate-800 border border-slate-700/60 flex items-center space-x-2.5 transition text-left"
              >
                <Power className="w-4 h-4 text-amber-400" />
                <div>
                  <div className="text-xs font-medium text-white">Screensaver Button</div>
                  <div className="text-[10px] text-slate-500 font-mono">button/{deviceId}/screensaver/set</div>
                </div>
              </button>

              <button
                onClick={() => handleButtonPress("wakeup", `${prefix}/button/${deviceId}/wakeup/set`)}
                className="p-3 rounded-xl bg-slate-900 hover:bg-slate-800 border border-slate-700/60 flex items-center space-x-2.5 transition text-left"
              >
                <Sun className="w-4 h-4 text-emerald-400" />
                <div>
                  <div className="text-xs font-medium text-white">Wake Display Button</div>
                  <div className="text-[10px] text-slate-500 font-mono">button/{deviceId}/wakeup/set</div>
                </div>
              </button>

              <button
                onClick={() => handleButtonPress("reload", `${prefix}/button/${deviceId}/reload/set`)}
                className="p-3 rounded-xl bg-slate-900 hover:bg-slate-800 border border-slate-700/60 flex items-center space-x-2.5 transition text-left"
              >
                <RefreshCw className="w-4 h-4 text-sky-400" />
                <div>
                  <div className="text-xs font-medium text-white">Reload WebView Button</div>
                  <div className="text-[10px] text-slate-500 font-mono">button/{deviceId}/reload/set</div>
                </div>
              </button>
            </div>
          </div>

          {/* Select & Switch Entities */}
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            {/* Screensaver Mode Select */}
            <div className="p-4 rounded-xl bg-slate-950/60 border border-slate-800 space-y-2">
              <div className="flex items-center justify-between">
                <span className="text-xs font-medium text-white">select.screensaver_mode</span>
                <span className="text-[10px] font-mono text-indigo-400">{settings.screensaverMode}</span>
              </div>
              <p className="text-[11px] text-slate-400 font-mono">
                Topic: {prefix}/select/{deviceId}/screensaverMode/set
              </p>
              <select
                value={settings.screensaverMode}
                onChange={(e) => handleCommand("screensaverMode", e.target.value, `${prefix}/select/${deviceId}/screensaverMode/set`)}
                className="w-full px-3 py-1.5 rounded-lg bg-slate-900 border border-slate-700 text-xs text-white"
              >
                <option value="clock">clock (Clock & Weather)</option>
                <option value="dimming">dimming (Dim Dashboard)</option>
                <option value="urls">urls (Cycle Slideshow)</option>
                <option value="off">off (Disabled)</option>
              </select>
            </div>

            {/* Wakeup Method Select */}
            <div className="p-4 rounded-xl bg-slate-950/60 border border-slate-800 space-y-2">
              <div className="flex items-center justify-between">
                <span className="text-xs font-medium text-white">select.wakeup_method</span>
                <span className="text-[10px] font-mono text-indigo-400">{settings.wakeupMethod}</span>
              </div>
              <p className="text-[11px] text-slate-400 font-mono">
                Topic: {prefix}/select/{deviceId}/wakeupMethod/set
              </p>
              <select
                value={settings.wakeupMethod}
                onChange={(e) => handleCommand("wakeupMethod", e.target.value, `${prefix}/select/${deviceId}/wakeupMethod/set`)}
                className="w-full px-3 py-1.5 rounded-lg bg-slate-900 border border-slate-700 text-xs text-white"
              >
                <option value="face">face (Face Detection)</option>
                <option value="motion">motion (Optical Motion)</option>
              </select>
            </div>

            {/* Motion Sensitivity Number */}
            <div className="p-4 rounded-xl bg-slate-950/60 border border-slate-800 space-y-2">
              <div className="flex items-center justify-between">
                <span className="text-xs font-medium text-white">number.motion_sensitivity</span>
                <span className="text-[10px] font-mono text-indigo-400">{settings.motionSensitivity}</span>
              </div>
              <p className="text-[11px] text-slate-400 font-mono">
                Topic: {prefix}/number/{deviceId}/motionSensitivity/set
              </p>
              <input
                type="range"
                min="0.02"
                max="0.25"
                step="0.01"
                value={settings.motionSensitivity}
                onChange={(e) => handleCommand("motionSensitivity", Number(e.target.value), `${prefix}/number/${deviceId}/motionSensitivity/set`)}
                className="w-full accent-indigo-500"
              />
            </div>

            {/* Camera Debug Switch */}
            <div className="p-4 rounded-xl bg-slate-950/60 border border-slate-800 space-y-2">
              <div className="flex items-center justify-between">
                <span className="text-xs font-medium text-white">switch.camera_debug_info</span>
                <span className="text-[10px] font-mono text-indigo-400">{settings.showDebugInfo ? "ON" : "OFF"}</span>
              </div>
              <p className="text-[11px] text-slate-400 font-mono">
                Topic: {prefix}/switch/{deviceId}/showDebugInfo/set
              </p>
              <button
                onClick={() => handleCommand("showDebugInfo", !settings.showDebugInfo, `${prefix}/switch/${deviceId}/showDebugInfo/set`)}
                className="px-3 py-1 rounded-lg bg-slate-900 hover:bg-slate-800 border border-slate-700 text-xs text-slate-200 flex items-center space-x-2"
              >
                {settings.showDebugInfo ? (
                  <ToggleRight className="w-4 h-4 text-emerald-400" />
                ) : (
                  <ToggleLeft className="w-4 h-4 text-slate-500" />
                )}
                <span>Toggle Switch: {settings.showDebugInfo ? "ON" : "OFF"}</span>
              </button>
            </div>
          </div>

          {/* Published Telemetry */}
          <div className="p-4 rounded-xl bg-slate-950/40 border border-slate-800 text-xs font-mono space-y-1 text-slate-400">
            <div className="text-slate-300 font-semibold mb-2">Live Published State Topics:</div>
            <div>• {prefix}/sensor/{deviceId}/battery/state &rarr; {batteryLevel}% ({isCharging ? "charging" : "unplugged"})</div>
            <div>• {prefix}/binary_sensor/{deviceId}/status &rarr; online</div>
            <div>• {prefix}/sensor/{deviceId}/app_info/state &rarr; active</div>
          </div>
        </div>
      </div>
    </div>
  );
};
