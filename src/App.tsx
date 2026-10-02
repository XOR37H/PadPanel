import React, { useState } from "react";
import {
  Tablet,
  Cpu,
  Layers,
  Server,
  Lock,
  Sun,
  Camera,
  Radio,
  Download,
  Terminal,
  Code,
  CheckCircle2,
  ExternalLink,
  ChevronRight,
  ShieldCheck,
  Zap,
  Globe,
  Monitor,
  Copy,
  Check,
  Sliders,
  Play,
  RotateCw,
  Moon,
  Clock,
  Sparkles
} from "lucide-react";

export function App() {
  const [activeTab, setActiveTab] = useState<"overview" | "xcode" | "api" | "swift" | "webui">("overview");
  const [copiedSnippet, setCopiedSnippet] = useState<string | null>(null);

  // REST API simulator state
  const [testBrightness, setTestBrightness] = useState<number>(85);
  const [testAction, setTestAction] = useState<string>("wakeup");
  const [apiLog, setApiLog] = useState<string | null>(null);

  const copyToClipboard = (text: string, id: string) => {
    navigator.clipboard.writeText(text);
    setCopiedSnippet(id);
    setTimeout(() => setCopiedSnippet(null), 2000);
  };

  const simulateApiCall = (endpoint: string, method: string, payload?: object) => {
    const formatted = JSON.stringify(
      {
        timestamp: new Date().toLocaleTimeString(),
        request: { method, endpoint, payload: payload || null },
        simulatedResponse: { success: true, status: 200, message: "OK on physical iPad hardware" }
      },
      null,
      2
    );
    setApiLog(formatted);
  };

  return (
    <div className="min-h-screen bg-[#080d1a] text-slate-100 flex flex-col selection:bg-cyan-500 selection:text-black">
      {/* Top Banner: Native Swift Truth */}
      <header className="border-b border-slate-800/80 bg-[#0d1527]/90 backdrop-blur-md sticky top-0 z-50">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-3.5 flex flex-wrap items-center justify-between gap-4">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-cyan-500 to-blue-600 flex items-center justify-center shadow-lg shadow-cyan-500/20">
              <Tablet className="w-5 h-5 text-white" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <span className="font-bold text-lg tracking-tight text-white">PadPanel</span>
                <span className="px-2 py-0.5 rounded-full text-xs font-semibold bg-emerald-500/20 text-emerald-400 border border-emerald-500/30">
                  Native Swift (iOS 15 / A8X)
                </span>
              </div>
              <p className="text-xs text-slate-400">Sole Source of Truth: <code className="text-cyan-300">/PadPanel</code></p>
            </div>
          </div>

          {/* Navigation tabs */}
          <nav className="flex items-center gap-1.5 p-1 bg-slate-900/90 rounded-xl border border-slate-800">
            <button
              onClick={() => setActiveTab("overview")}
              className={`px-3.5 py-1.5 rounded-lg text-xs font-medium transition-all ${
                activeTab === "overview"
                  ? "bg-cyan-500 text-slate-950 font-semibold shadow-md shadow-cyan-500/25"
                  : "text-slate-300 hover:text-white hover:bg-slate-800/60"
              }`}
            >
              Overview & Features
            </button>
            <button
              onClick={() => setActiveTab("xcode")}
              className={`px-3.5 py-1.5 rounded-lg text-xs font-medium transition-all ${
                activeTab === "xcode"
                  ? "bg-cyan-500 text-slate-950 font-semibold shadow-md shadow-cyan-500/25"
                  : "text-slate-300 hover:text-white hover:bg-slate-800/60"
              }`}
            >
              Xcode Build Guide
            </button>
            <button
              onClick={() => setActiveTab("api")}
              className={`px-3.5 py-1.5 rounded-lg text-xs font-medium transition-all ${
                activeTab === "api"
                  ? "bg-cyan-500 text-slate-950 font-semibold shadow-md shadow-cyan-500/25"
                  : "text-slate-300 hover:text-white hover:bg-slate-800/60"
              }`}
            >
              REST API Reference
            </button>
            <button
              onClick={() => setActiveTab("swift")}
              className={`px-3.5 py-1.5 rounded-lg text-xs font-medium transition-all ${
                activeTab === "swift"
                  ? "bg-cyan-500 text-slate-950 font-semibold shadow-md shadow-cyan-500/25"
                  : "text-slate-300 hover:text-white hover:bg-slate-800/60"
              }`}
            >
              Swift Code Tree
            </button>
          </nav>

          <div className="flex items-center gap-2">
            <a
              href="https://github.com"
              target="_blank"
              rel="noreferrer"
              className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium bg-slate-800 hover:bg-slate-700 text-slate-200 border border-slate-700 transition"
            >
              <Download className="w-3.5 h-3.5 text-cyan-400" />
              Releases
            </a>
          </div>
        </div>
      </header>

      {/* Main Container */}
      <main className="flex-1 max-w-7xl w-full mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-8">
        {/* Architecture Notice Banner */}
        <div className="bg-gradient-to-r from-blue-950/40 via-cyan-950/20 to-slate-900 border border-cyan-500/30 rounded-2xl p-5 shadow-xl relative overflow-hidden">
          <div className="absolute right-0 top-0 w-96 h-96 bg-cyan-500/5 rounded-full blur-3xl pointer-events-none" />
          <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 relative z-10">
            <div className="space-y-1">
              <div className="flex items-center gap-2">
                <ShieldCheck className="w-5 h-5 text-cyan-400" />
                <h2 className="text-base font-bold text-white tracking-tight">
                  Single Source of Truth: Native Swift & SwiftUI
                </h2>
              </div>
              <p className="text-xs text-slate-300 max-w-3xl leading-relaxed">
                PadPanel is written in <strong className="text-white">100% Native Swift</strong> for Apple iOS 15 (optimized for legacy iPad Air 2 / A8X).
                To prevent discrepancies between web simulators and physical hardware, all production views, settings, and hardware controls reside directly in <code className="text-cyan-300 px-1.5 py-0.5 rounded bg-slate-900 border border-slate-700">/PadPanel/</code>.
              </p>
            </div>
            <div className="flex items-center gap-2 shrink-0">
              <div className="px-3 py-1.5 rounded-lg bg-slate-900/90 border border-slate-700 text-xs text-slate-300 flex items-center gap-2">
                <span className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse"></span>
                Port 8080 Web Server Embedded
              </div>
            </div>
          </div>
        </div>

        {/* TAB 1: OVERVIEW & FEATURES */}
        {activeTab === "overview" && (
          <div className="space-y-8">
            {/* Feature Cards Grid */}
            <div>
              <h3 className="text-sm font-semibold uppercase tracking-wider text-cyan-400 mb-4 flex items-center gap-2">
                <Zap className="w-4 h-4" /> Core Capabilities & Hardware Integrations
              </h3>

              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                {/* Kiosk Mode */}
                <div className="bg-slate-900/60 border border-slate-800 rounded-xl p-5 hover:border-slate-700 transition">
                  <div className="w-9 h-9 rounded-lg bg-blue-500/10 border border-blue-500/20 flex items-center justify-center text-blue-400 mb-3">
                    <Monitor className="w-5 h-5" />
                  </div>
                  <h4 className="font-semibold text-white text-sm mb-1.5">Fullscreen Kiosk & Slideshow</h4>
                  <p className="text-xs text-slate-400 leading-relaxed">
                    Full-screen kiosk display of Home Assistant dashboards with smooth multi-URL cross-fades, configurable interval cycling, and auto-refresh.
                  </p>
                </div>

                {/* Device Authentication */}
                <div className="bg-slate-900/60 border border-slate-800 rounded-xl p-5 hover:border-slate-700 transition">
                  <div className="w-9 h-9 rounded-lg bg-emerald-500/10 border border-emerald-500/20 flex items-center justify-center text-emerald-400 mb-3">
                    <Lock className="w-5 h-5" />
                  </div>
                  <h4 className="font-semibold text-white text-sm mb-1.5">Device Auth & Kiosk Lock</h4>
                  <p className="text-xs text-slate-400 leading-relaxed">
                    On-device Kiosk Settings Lock with triple-tap gesture protection and HTTP Basic Auth for remote WebUI access.
                  </p>
                </div>

                {/* Hardware Brightness */}
                <div className="bg-slate-900/60 border border-slate-800 rounded-xl p-5 hover:border-slate-700 transition">
                  <div className="w-9 h-9 rounded-lg bg-amber-500/10 border border-amber-500/20 flex items-center justify-center text-amber-400 mb-3">
                    <Sun className="w-5 h-5" />
                  </div>
                  <h4 className="font-semibold text-white text-sm mb-1.5">Real-Time Screen Brightness</h4>
                  <p className="text-xs text-slate-400 leading-relaxed">
                    Live hardware display brightness adjustment via <code className="text-amber-300 font-mono">UIScreen.main.brightness</code> with dedicated low-latency <code className="text-amber-300 font-mono">/api/brightness</code> endpoint.
                  </p>
                </div>

                {/* Vision & Motion Detection */}
                <div className="bg-slate-900/60 border border-slate-800 rounded-xl p-5 hover:border-slate-700 transition">
                  <div className="w-9 h-9 rounded-lg bg-purple-500/10 border border-purple-500/20 flex items-center justify-center text-purple-400 mb-3">
                    <Camera className="w-5 h-5" />
                  </div>
                  <h4 className="font-semibold text-white text-sm mb-1.5">Vision & Motion Wake</h4>
                  <p className="text-xs text-slate-400 leading-relaxed">
                    Apple Vision framework face detection and camera frame delta motion sensing to automatically wake the display upon approaching the iPad.
                  </p>
                </div>

                {/* Screensaver Modes */}
                <div className="bg-slate-900/60 border border-slate-800 rounded-xl p-5 hover:border-slate-700 transition">
                  <div className="w-9 h-9 rounded-lg bg-indigo-500/10 border border-indigo-500/20 flex items-center justify-center text-indigo-400 mb-3">
                    <Clock className="w-5 h-5" />
                  </div>
                  <h4 className="font-semibold text-white text-sm mb-1.5">Versatile Screensavers</h4>
                  <p className="text-xs text-slate-400 leading-relaxed">
                    Choose between minimal OLED-friendly Clock & date, In-place screen dimming, periodic Photo Frame image refresh, or disable completely.
                  </p>
                </div>

                {/* Remote Web Server */}
                <div className="bg-slate-900/60 border border-slate-800 rounded-xl p-5 hover:border-slate-700 transition">
                  <div className="w-9 h-9 rounded-lg bg-cyan-500/10 border border-cyan-500/20 flex items-center justify-center text-cyan-400 mb-3">
                    <Server className="w-5 h-5" />
                  </div>
                  <h4 className="font-semibold text-white text-sm mb-1.5">Built-in HTTP Web Server</h4>
                  <p className="text-xs text-slate-400 leading-relaxed">
                    Lightweight Network.framework HTTP server running on port 8080 for remote browser management from any phone or PC on your LAN.
                  </p>
                </div>
              </div>
            </div>

            {/* Legacy iPad Compatibility Info */}
            <div className="bg-slate-900/40 border border-slate-800 rounded-xl p-6">
              <h4 className="text-sm font-semibold text-white mb-3 flex items-center gap-2">
                <Cpu className="w-4 h-4 text-cyan-400" /> Target Hardware Specifications
              </h4>
              <div className="grid grid-cols-1 md:grid-cols-3 gap-4 text-xs text-slate-300">
                <div className="p-3 bg-slate-950/60 rounded-lg border border-slate-800/80">
                  <span className="text-slate-500 block mb-1">Architecture</span>
                  <strong className="text-white text-sm">arm64 (Apple A8X / A9 / A10)</strong>
                </div>
                <div className="p-3 bg-slate-950/60 rounded-lg border border-slate-800/80">
                  <span className="text-slate-500 block mb-1">Target Operating System</span>
                  <strong className="text-white text-sm">iOS 15.0 – iOS 15.8.x (iPad Air 2)</strong>
                </div>
                <div className="p-3 bg-slate-950/60 rounded-lg border border-slate-800/80">
                  <span className="text-slate-500 block mb-1">SwiftUI & UIKit</span>
                  <strong className="text-white text-sm">Pure Swift 5.7+ / SwiftUI 3.0</strong>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* TAB 2: XCODE BUILD GUIDE */}
        {activeTab === "xcode" && (
          <div className="space-y-6">
            <div className="bg-slate-900/60 border border-slate-800 rounded-xl p-6 space-y-4">
              <h3 className="text-base font-semibold text-white flex items-center gap-2">
                <Terminal className="w-5 h-5 text-cyan-400" /> Compiling & Deploying to Your Physical iPad
              </h3>
              <p className="text-xs text-slate-300 leading-relaxed">
                Follow these steps in Apple Xcode on your Mac to compile and deploy PadPanel directly onto your iPad Air 2 or any iOS 15+ device.
              </p>

              <ol className="space-y-4 text-xs text-slate-300 list-decimal list-inside">
                <li className="p-3 bg-slate-950/80 rounded-lg border border-slate-800">
                  <strong className="text-white">Open the Project in Xcode:</strong>
                  <p className="mt-1 text-slate-400">
                    Open the <code className="text-cyan-300">PadPanel.xcodeproj</code> file in Xcode 14, 15, or 16.
                  </p>
                </li>

                <li className="p-3 bg-slate-950/80 rounded-lg border border-slate-800">
                  <strong className="text-white">Configure Signing & Capabilities:</strong>
                  <p className="mt-1 text-slate-400">
                    In Xcode's Project Settings &gt; <strong>Signing & Capabilities</strong>, select your Apple Developer Team (free personal teams are supported). Set a unique Bundle Identifier if prompted.
                  </p>
                </li>

                <li className="p-3 bg-slate-950/80 rounded-lg border border-slate-800">
                  <strong className="text-white">Connect iPad & Select Target:</strong>
                  <p className="mt-1 text-slate-400">
                    Connect your iPad via Lightning cable. In Xcode's top device selector, choose your connected iPad.
                  </p>
                </li>

                <li className="p-3 bg-slate-950/80 rounded-lg border border-slate-800">
                  <strong className="text-white">Build and Run:</strong>
                  <p className="mt-1 text-slate-400">
                    Press <kbd className="px-1.5 py-0.5 bg-slate-800 border border-slate-700 rounded text-cyan-300 font-mono">Cmd + R</kbd> to build and install the app on the iPad.
                  </p>
                </li>

                <li className="p-3 bg-slate-950/80 rounded-lg border border-slate-800">
                  <strong className="text-white">Trust Developer Certificate (First Run):</strong>
                  <p className="mt-1 text-slate-400">
                    On the iPad, go to <em>Settings &gt; General &gt; VPN & Device Management</em> and trust your developer profile.
                  </p>
                </li>
              </ol>
            </div>
          </div>
        )}

        {/* TAB 3: REST API REFERENCE */}
        {activeTab === "api" && (
          <div className="space-y-6">
            <div className="bg-slate-900/60 border border-slate-800 rounded-xl p-6 space-y-4">
              <div>
                <h3 className="text-base font-semibold text-white flex items-center gap-2">
                  <Server className="w-5 h-5 text-cyan-400" /> Embedded HTTP Server REST API
                </h3>
                <p className="text-xs text-slate-400 mt-1">
                  When enabled, PadPanel hosts a local HTTP server on port <code className="text-cyan-300 font-mono">8080</code> (<code className="text-slate-300">http://&lt;ipad-ip&gt;:8080</code>).
                </p>
              </div>

              {/* Endpoints Table */}
              <div className="space-y-3">
                {/* GET /api/status */}
                <div className="p-4 bg-slate-950/80 rounded-lg border border-slate-800 flex flex-col md:flex-row md:items-center justify-between gap-3">
                  <div>
                    <div className="flex items-center gap-2 font-mono text-xs">
                      <span className="px-2 py-0.5 rounded bg-blue-500/20 text-blue-400 font-bold">GET</span>
                      <span className="text-white font-semibold">/api/status</span>
                    </div>
                    <p className="text-xs text-slate-400 mt-1">Returns live device battery, charging state, screensaver state, and active URLs.</p>
                  </div>
                  <button
                    onClick={() => simulateApiCall("/api/status", "GET")}
                    className="px-3 py-1.5 bg-slate-800 hover:bg-slate-700 text-cyan-300 text-xs rounded border border-slate-700 shrink-0 flex items-center gap-1.5"
                  >
                    <Play className="w-3 h-3" /> Test Payload
                  </button>
                </div>

                {/* POST /api/brightness */}
                <div className="p-4 bg-slate-950/80 rounded-lg border border-slate-800 space-y-3">
                  <div className="flex flex-col md:flex-row md:items-center justify-between gap-3">
                    <div>
                      <div className="flex items-center gap-2 font-mono text-xs">
                        <span className="px-2 py-0.5 rounded bg-emerald-500/20 text-emerald-400 font-bold">POST</span>
                        <span className="text-white font-semibold">/api/brightness</span>
                      </div>
                      <p className="text-xs text-slate-400 mt-1">Instantly adjusts the physical iPad screen brightness in real-time.</p>
                    </div>
                    <div className="flex items-center gap-3">
                      <div className="flex items-center gap-2 text-xs">
                        <span className="text-slate-400">{testBrightness}%</span>
                        <input
                          type="range"
                          min="10"
                          max="100"
                          value={testBrightness}
                          onChange={(e) => setTestBrightness(Number(e.target.value))}
                          className="w-24 accent-cyan-400"
                        />
                      </div>
                      <button
                        onClick={() => simulateApiCall("/api/brightness", "POST", { screenBrightnessNormal: testBrightness / 100 })}
                        className="px-3 py-1.5 bg-slate-800 hover:bg-slate-700 text-cyan-300 text-xs rounded border border-slate-700 shrink-0 flex items-center gap-1.5"
                      >
                        <Play className="w-3 h-3" /> Test API
                      </button>
                    </div>
                  </div>
                </div>

                {/* POST /api/action */}
                <div className="p-4 bg-slate-950/80 rounded-lg border border-slate-800 flex flex-col md:flex-row md:items-center justify-between gap-3">
                  <div>
                    <div className="flex items-center gap-2 font-mono text-xs">
                      <span className="px-2 py-0.5 rounded bg-amber-500/20 text-amber-400 font-bold">POST</span>
                      <span className="text-white font-semibold">/api/action</span>
                    </div>
                    <p className="text-xs text-slate-400 mt-1">Dispatches remote actions: <code className="text-cyan-300">screensaver</code>, <code className="text-cyan-300">sleep</code>, <code className="text-cyan-300">wakeup</code>, <code className="text-cyan-300">reload</code>.</p>
                  </div>
                  <div className="flex items-center gap-2">
                    <select
                      value={testAction}
                      onChange={(e) => setTestAction(e.target.value)}
                      className="bg-slate-900 border border-slate-700 text-xs rounded px-2 py-1 text-slate-200"
                    >
                      <option value="wakeup">wakeup</option>
                      <option value="sleep">sleep</option>
                      <option value="screensaver">screensaver</option>
                      <option value="reload">reload</option>
                    </select>
                    <button
                      onClick={() => simulateApiCall("/api/action", "POST", { action: testAction })}
                      className="px-3 py-1.5 bg-slate-800 hover:bg-slate-700 text-cyan-300 text-xs rounded border border-slate-700 shrink-0 flex items-center gap-1.5"
                    >
                      <Play className="w-3 h-3" /> Send Action
                    </button>
                  </div>
                </div>

                {/* POST /api/settings */}
                <div className="p-4 bg-slate-950/80 rounded-lg border border-slate-800 flex flex-col md:flex-row md:items-center justify-between gap-3">
                  <div>
                    <div className="flex items-center gap-2 font-mono text-xs">
                      <span className="px-2 py-0.5 rounded bg-purple-500/20 text-purple-400 font-bold">POST</span>
                      <span className="text-white font-semibold">/api/settings</span>
                    </div>
                    <p className="text-xs text-slate-400 mt-1">Updates full or partial settings dictionary and persists to UserDefaults.</p>
                  </div>
                  <button
                    onClick={() => simulateApiCall("/api/settings", "POST", { screensaverMode: "clock", requireDeviceAuth: true })}
                    className="px-3 py-1.5 bg-slate-800 hover:bg-slate-700 text-cyan-300 text-xs rounded border border-slate-700 shrink-0 flex items-center gap-1.5"
                  >
                    <Play className="w-3 h-3" /> Test Payload
                  </button>
                </div>
              </div>

              {/* Simulated Output Log */}
              {apiLog && (
                <div className="mt-4 p-4 bg-slate-950 rounded-lg border border-slate-800 font-mono text-xs text-emerald-400">
                  <div className="flex items-center justify-between mb-2 text-slate-400 font-sans">
                    <span>API Response Preview:</span>
                    <button onClick={() => setApiLog(null)} className="text-slate-500 hover:text-slate-300">Clear</button>
                  </div>
                  <pre className="overflow-x-auto">{apiLog}</pre>
                </div>
              )}
            </div>
          </div>
        )}

        {/* TAB 4: SWIFT CODE TREE */}
        {activeTab === "swift" && (
          <div className="space-y-6">
            <div className="bg-slate-900/60 border border-slate-800 rounded-xl p-6 space-y-4">
              <h3 className="text-base font-semibold text-white flex items-center gap-2">
                <Code className="w-5 h-5 text-cyan-400" /> Native Swift Source Tree Directory
              </h3>
              <p className="text-xs text-slate-300">
                All application logic for the iPad is contained inside the <code className="text-cyan-300">/PadPanel/</code> folder:
              </p>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-3 text-xs">
                <div className="p-3.5 bg-slate-950/80 rounded-lg border border-slate-800">
                  <div className="font-mono text-cyan-300 font-semibold mb-1">PadPanelApp.swift</div>
                  <p className="text-slate-400">Application lifecycle entry point, initialization of managers and settings.</p>
                </div>

                <div className="p-3.5 bg-slate-950/80 rounded-lg border border-slate-800">
                  <div className="font-mono text-cyan-300 font-semibold mb-1">ContentView.swift</div>
                  <p className="text-slate-400">Main kiosk view stack, triple-tap unlock gesture handler, and screensaver overlay.</p>
                </div>

                <div className="p-3.5 bg-slate-950/80 rounded-lg border border-slate-800">
                  <div className="font-mono text-cyan-300 font-semibold mb-1">Views/SettingsView.swift</div>
                  <p className="text-slate-400">Native iOS 15 SwiftUI Form for all on-device configurations & Device Auth.</p>
                </div>

                <div className="p-3.5 bg-slate-950/80 rounded-lg border border-slate-800">
                  <div className="font-mono text-cyan-300 font-semibold mb-1">Managers/WebServerManager.swift</div>
                  <p className="text-slate-400">Embedded HTTP server (port 8080), REST endpoints, and WebUI dashboard HTML.</p>
                </div>

                <div className="p-3.5 bg-slate-950/80 rounded-lg border border-slate-800">
                  <div className="font-mono text-cyan-300 font-semibold mb-1">Managers/BrightnessManager.swift</div>
                  <p className="text-slate-400">Direct hardware screen brightness controller using UIKit UIScreen APIs.</p>
                </div>

                <div className="p-3.5 bg-slate-950/80 rounded-lg border border-slate-800">
                  <div className="font-mono text-cyan-300 font-semibold mb-1">Managers/FaceDetectionManager.swift</div>
                  <p className="text-slate-400">Apple Vision framework face detection and camera frame delta motion wake.</p>
                </div>

                <div className="p-3.5 bg-slate-950/80 rounded-lg border border-slate-800">
                  <div className="font-mono text-cyan-300 font-semibold mb-1">Managers/SettingsManager.swift</div>
                  <p className="text-slate-400">UserDefaults persistence, reactive Combine publishers, and default values.</p>
                </div>

                <div className="p-3.5 bg-slate-950/80 rounded-lg border border-slate-800">
                  <div className="font-mono text-cyan-300 font-semibold mb-1">Managers/MQTTManager.swift</div>
                  <p className="text-slate-400">Bi-directional Home Assistant MQTT integration via CocoaMQTT.</p>
                </div>
              </div>
            </div>
          </div>
        )}
      </main>

      {/* Footer */}
      <footer className="border-t border-slate-800/80 bg-[#0a0f1d] py-5 mt-auto text-center text-xs text-slate-500">
        <div className="max-w-7xl mx-auto px-4 flex flex-col sm:flex-row items-center justify-between gap-2">
          <span>PadPanel — Native iOS Kiosk Dashboard for Legacy Hardware</span>
          <span className="text-slate-400 font-mono text-[11px]">Sole Source of Truth: Swift / SwiftUI</span>
        </div>
      </footer>
    </div>
  );
}
export default App;
