export interface UltraKioskSettings {
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

  // Screensaver
  screensaverTimeout: number; // seconds
  screenBrightnessDimmed: number; // 0.05 to 0.8
  screenBrightnessNormal: number; // 0.3 to 1.0
  faceDetectionInterval: number; // seconds

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
  slideshowURLs: string[];
  slideshowInterval: number; // seconds
}

export const DEFAULT_SETTINGS: UltraKioskSettings = {
  homeAssistantIP: "homeassistant.local",
  homeAssistantPort: "8123",
  accessToken: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiIwYTJmOTU1ZDYwNjY0YmI1YTc2NGU4ZDAyNTMwZTA1ZSIsImlhdCI6MTcxOTE0MTcxNiwiZXhwIjoyMDM0NTAxNzE2fQ.u2rLYy7Mc4VIQ9-x_25Ra2IRejvkXBsRX8lxvjBzPIM",
  useHTTPS: false,

  enableMQTT: true,
  mqttBrokerIP: "homeassistant.local",
  mqttPort: "1883",
  mqttUsername: "homeassistant",
  mqttPassword: "",
  mqttUseTLS: false,
  mqttTopicPrefix: "homeassistant",
  mqttBatteryUpdateInterval: 60.0,

  screensaverTimeout: 60.0,
  screenBrightnessDimmed: 0.2,
  screenBrightnessNormal: 0.7,
  faceDetectionInterval: 1.0,

  enableVoiceActivation: true,
  voiceSampleRate: 16000,
  voiceTimeout: 2,
  porcupineAccessToken: "YTvBtr2dk1wvG5ZeOqT5Gg8Ui2gMGy/qaeTLst0dPBBpxuJK2vkDqg==",
  voiceLanguage: "de",
  homeAssistantConversationAgent: "conversation.claude_conversation",
  homeAssistantConversationId: "ipad",

  kioskURL: "http://homeassistant.local:8123/anzeige-flur/0?kiosk",
  slideshowURLs: [],
  slideshowInterval: 30.0,
};

const STORAGE_KEY = "ultrakiosk_settings_v1";

export function loadSettingsFromStorage(): UltraKioskSettings {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return { ...DEFAULT_SETTINGS };
    const parsed = JSON.parse(raw);
    return {
      ...DEFAULT_SETTINGS,
      ...parsed,
      // Ensure slideshowURLs is always an array
      slideshowURLs: Array.isArray(parsed.slideshowURLs) ? parsed.slideshowURLs : [],
    };
  } catch (e) {
    console.error("Failed to load settings from storage:", e);
    return { ...DEFAULT_SETTINGS };
  }
}

export function saveSettingsToStorage(settings: UltraKioskSettings): void {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(settings));
    window.dispatchEvent(new CustomEvent("ultrakiosk:settings-changed", { detail: settings }));
  } catch (e) {
    console.error("Failed to save settings to storage:", e);
  }
}

export function validateSettings(settings: UltraKioskSettings): string[] {
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
