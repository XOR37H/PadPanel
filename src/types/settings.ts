export type ScreensaverMode = "clock" | "photoFrame" | "dimming" | "off";
export type WakeupMethod = "face" | "motion";

export interface PadPanelSettings {
  // Device & WebUI Authentication (Ubiquitous)
  deviceAdminUsername: string; // default "admin"
  deviceAdminPassword: string; // default ""
  requireDeviceAuth: boolean; // Protect on-device kiosk settings (triple tap)

  // Home Assistant
  homeAssistantIP: string;
  homeAssistantPort: string;
  accessToken: string;
  useHTTPS: boolean;

  // MQTT
  enableMQTT: boolean;
  mqttBrokerIP: string;
  mqttPort: string;
  mqttUsername: string;
  mqttPassword: string;
  mqttUseTLS: boolean;
  mqttTopicPrefix: string;
  mqttBatteryUpdateInterval: number; // seconds

  // Screensaver & Display
  screensaverTimeout: number; // seconds
  screensaverMode: ScreensaverMode; // "clock", "photoFrame", "dimming", "off"
  screenBrightnessDimmed: number; // 0.05 to 0.8
  screenBrightnessNormal: number; // 0.3 to 1.0

  // Deep Sleep
  enableDeepSleep: boolean;
  deepSleepTimeout: number; // seconds (default 1800)

  // Photo Frame
  photoFrameURL: string;
  photoFrameInterval: number; // seconds (default 60)

  // Face & Motion Detection Wakeup
  faceDetectionInterval: number; // seconds
  wakeupMethod: WakeupMethod; // "face" or "motion"
  motionSensitivity: number; // 0.02 (high) to 0.25 (low), default 0.08
  showDebugInfo: boolean; // overlay camera & motion debug telemetry

  // Auto Refresh
  enableAutoRefresh: boolean;
  autoRefreshInterval: number; // seconds, default 300 (5m)

  // Remote Web Server / WebUI
  enableWebServer: boolean;
  webServerPort: number; // default 8080
  webServerPassword: string; // mirrors deviceAdminPassword
  webServerUsername: string; // mirrors deviceAdminUsername

  // Voice Satellite
  enableVoiceActivation: boolean;
  voiceSampleRate: number;
  voiceTimeout: number; // seconds
  porcupineAccessToken: string;
  voiceLanguage: string;
  homeAssistantConversationAgent: string;
  homeAssistantConversationId: string;

  // Kiosk / Slideshow
  kioskURL: string;
  enableSlideshow: boolean;
  slideshowURLs: string[];
  slideshowInterval: number; // seconds
}

export type UltraKioskSettings = PadPanelSettings;

export const DEFAULT_SETTINGS: PadPanelSettings = {
  // Device & WebUI Authentication
  deviceAdminUsername: "admin",
  deviceAdminPassword: "",
  requireDeviceAuth: false,

  // Home Assistant
  homeAssistantIP: "homeassistant.local",
  homeAssistantPort: "8123",
  accessToken: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiIwYTJmOTU1ZDYwNjY0YmI1YTc2NGU4ZDAyNTMwZTA1ZSIsImlhdCI6MTcxOTE0MTcxNiwiZXhwIjoyMDM0NTAxNzE2fQ.u2rLYy7Mc4VIQ9-x_25Ra2IRejvkXBsRX8lxvjBzPIM",
  useHTTPS: false,

  // MQTT
  enableMQTT: false,
  mqttBrokerIP: "homeassistant.local",
  mqttPort: "1883",
  mqttUsername: "homeassistant",
  mqttPassword: "iepoiph4ongiesah2zoZae4AiLa8bie9oochaahaiQuoush3or3kiequoo3xohye",
  mqttUseTLS: false,
  mqttTopicPrefix: "homeassistant",
  mqttBatteryUpdateInterval: 60.0,

  // Screensaver & Display
  screensaverTimeout: 60.0,
  screensaverMode: "clock",
  screenBrightnessDimmed: 0.2,
  screenBrightnessNormal: 0.7,

  // Deep Sleep
  enableDeepSleep: false,
  deepSleepTimeout: 1800.0,

  // Photo Frame
  photoFrameURL: "",
  photoFrameInterval: 60.0,

  // Face & Motion Detection Wakeup
  faceDetectionInterval: 1.0,
  wakeupMethod: "face",
  motionSensitivity: 0.08,
  showDebugInfo: false,

  // Auto Refresh
  enableAutoRefresh: false,
  autoRefreshInterval: 300.0,

  // Remote Web Server / WebUI
  enableWebServer: false,
  webServerPort: 8080,
  webServerPassword: "",
  webServerUsername: "admin",

  // Voice Satellite
  enableVoiceActivation: false,
  voiceSampleRate: 16000,
  voiceTimeout: 2,
  porcupineAccessToken: "YTvBtr2dk1wvG5ZeOqT5Gg8Ui2gMGy/qaeTLst0dPBBpxuJK2vkDqg==",
  voiceLanguage: "de",
  homeAssistantConversationAgent: "conversation.claude_conversation",
  homeAssistantConversationId: "ipad",

  // Kiosk / Slideshow
  kioskURL: "http://homeassistant.local:8123/anzeige-flur/0?kiosk",
  enableSlideshow: false,
  slideshowURLs: [],
  slideshowInterval: 30.0,
};

const STORAGE_KEY = "padpanel_settings_v2";
const LEGACY_STORAGE_KEY = "ultrakiosk_settings_v1";

export function loadSettingsFromStorage(): PadPanelSettings {
  try {
    const raw = localStorage.getItem(STORAGE_KEY) || localStorage.getItem(LEGACY_STORAGE_KEY);
    if (!raw) return { ...DEFAULT_SETTINGS };
    const parsed = JSON.parse(raw);
    
    // Normalize authentication fields if legacy
    const adminUser = parsed.deviceAdminUsername || parsed.webServerUsername || DEFAULT_SETTINGS.deviceAdminUsername;
    const adminPass = parsed.deviceAdminPassword ?? parsed.webServerPassword ?? DEFAULT_SETTINGS.deviceAdminPassword;
    const reqAuth = parsed.requireDeviceAuth ?? (adminPass.length > 0);

    // Normalize screensaverMode (if user previously had "urls", migrate to "photoFrame" or "clock")
    let sMode: ScreensaverMode = parsed.screensaverMode;
    let sEnableSlideshow = parsed.enableSlideshow ?? false;
    if ((sMode as string) === "urls") {
      sMode = "clock";
      sEnableSlideshow = true;
    } else if (!["clock", "photoFrame", "dimming", "off"].includes(sMode)) {
      sMode = "clock";
    }

    return {
      ...DEFAULT_SETTINGS,
      ...parsed,
      screensaverMode: sMode,
      enableSlideshow: sEnableSlideshow,
      deviceAdminUsername: adminUser,
      deviceAdminPassword: adminPass,
      webServerUsername: adminUser,
      webServerPassword: adminPass,
      requireDeviceAuth: reqAuth,
      enableDeepSleep: parsed.enableDeepSleep ?? DEFAULT_SETTINGS.enableDeepSleep,
      deepSleepTimeout: parsed.deepSleepTimeout ?? DEFAULT_SETTINGS.deepSleepTimeout,
      photoFrameURL: parsed.photoFrameURL ?? DEFAULT_SETTINGS.photoFrameURL,
      photoFrameInterval: parsed.photoFrameInterval ?? DEFAULT_SETTINGS.photoFrameInterval,
      // Ensure slideshowURLs is always an array
      slideshowURLs: Array.isArray(parsed.slideshowURLs) ? parsed.slideshowURLs : [],
    };
  } catch (e) {
    console.error("Failed to load settings from storage:", e);
    return { ...DEFAULT_SETTINGS };
  }
}

export function saveSettingsToStorage(settings: PadPanelSettings): void {
  try {
    // Keep username and password fields synchronized
    const normalized: PadPanelSettings = {
      ...settings,
      webServerUsername: settings.deviceAdminUsername,
      webServerPassword: settings.deviceAdminPassword,
    };
    localStorage.setItem(STORAGE_KEY, JSON.stringify(normalized));
    window.dispatchEvent(new CustomEvent("padpanel:settings-changed", { detail: normalized }));
  } catch (e) {
    console.error("Failed to save settings to storage:", e);
  }
}

export function validateSettings(settings: PadPanelSettings): string[] {
  const issues: string[] = [];

  const haPort = parseInt(settings.homeAssistantPort, 10);
  if (isNaN(haPort) || haPort < 1 || haPort > 65535) {
    issues.push("Invalid port for Home Assistant (1-65535)");
  }

  if (!settings.accessToken.trim()) {
    issues.push("Access Token is required for Home Assistant");
  }

  if (settings.enableMQTT) {
    const mqttPort = parseInt(settings.mqttPort, 10);
    if (isNaN(mqttPort) || mqttPort < 1 || mqttPort > 65535) {
      issues.push("Invalid MQTT port (1-65535)");
    }
  }

  if (settings.screensaverTimeout < 10) {
    issues.push("Screensaver timeout should be at least 10 seconds");
  }

  if (settings.faceDetectionInterval < 0.1) {
    issues.push("Face detection interval should be at least 0.1 seconds");
  }

  if (settings.enableWebServer) {
    if (isNaN(settings.webServerPort) || settings.webServerPort < 1024 || settings.webServerPort > 65535) {
      issues.push("Web Server port must be between 1024 and 65535");
    }
  }

  return issues;
}

export function formatScreensaverTimeout(seconds: number): string {
  const mins = Math.floor(seconds / 60);
  const secs = Math.floor(seconds % 60);
  return `${mins}:${secs.toString().padStart(2, "0")}`;
}

export function formatBatteryInterval(seconds: number): string {
  if (seconds < 60) {
    return `${Math.round(seconds)}s`;
  }
  return `${Math.round(seconds / 60)}m`;
}
