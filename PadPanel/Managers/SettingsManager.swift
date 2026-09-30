
import SwiftUI
import Combine

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    // MARK: - User Defaults
    // The production singleton uses UserDefaults.standard.
    // Pass a custom suite in init(userDefaults:) to get an isolated store for tests.
    private let _userDefaults: UserDefaults
    private var userDefaults: UserDefaults { _userDefaults }
    
    // MARK: - Published Settings
    @Published var mainDashboardURL: String = ""
    @Published var enableHomeAssistant: Bool = false
    @Published var homeAssistantIP: String = "homeassistant.local"
    @Published var homeAssistantPort: String = "8123"
    @Published var accessToken: String = "eyJhbGciOiJIUzI1NiIsInR5cCI6IJmOTU1ZDYwNjY0YmI1YTc2NGU4ZDkpXVCJ9.eyJpc3MiOiIwYTAyNTMwZTA1ZSIsImlhdCI6MTcxOTE0MTcxNiwiZXhwIjoyMDM0NTAxNzE2fQ.u2rLYy7Mc4VIQ9-x_25Ra2IRejvkXBsRX8lxvjBzPIM"
    @Published var useHTTPS: Bool = false
    
    @Published var mqttBrokerIP: String = "homeassistant.local"
    @Published var mqttPort: String = "1883"
    @Published var mqttUsername: String = "homeassistant"
    @Published var mqttPassword: String = "iepoiph4ongiesah2zoZaahaiQuoush3oe4AiLa8bie9oochar3kiequoo3xohye"
    @Published var mqttUseTLS: Bool = false
    @Published var mqttTopicPrefix: String = "homeassistant"
    @Published var enableMQTT: Bool = false
    @Published var mqttBatteryUpdateInterval: Double = 60.0 // seconds
    
    @Published var screensaverTimeout: Double = 60.0 // 1 minute default
    @Published var screenBrightnessDimmed: Double = 0.2
    @Published var screenBrightnessNormal: Double = 0.7 // Changed from 1.0 to more reasonable 70%
    
    @Published var enableVoiceActivation: Bool = false
    @Published var kioskURL: String = "http://homeassistant.local:8123/anzeige-flur/0?kiosk"
    @Published var screensaverMode: String = "off" // "clock", "dimming", "urls", "off"
    @Published var faceDetectionInterval: Double = 1.0 // seconds between detections
    @Published var wakeupMethod: String = "face" // "face" or "motion"
    @Published var motionSensitivity: Double = 0.08 // 0.02 (high) to 0.25 (low)
    @Published var showDebugInfo: Bool = false
    @Published var enableAutoRefresh: Bool = false
    @Published var autoRefreshInterval: Double = 300.0 // seconds, default 5m
    @Published var slideshowURLs: [String] = []
    @Published var slideshowInterval: Double = 30.0
    
    // Remote Web Server & Device Authentication settings
    @Published var enableWebServer: Bool = true
    @Published var webServerPort: Int = 8080
    @Published var webServerUsername: String = "admin"
    @Published var webServerPassword: String = "PadPanel"
    @Published var requireDeviceAuth: Bool = true
    @Published var screenshotSecurityToken: String = SettingsManager.generateRandomSecurityToken()
    
    // Voice pipeline settings
    @Published var voiceSampleRate: Int = 16000
    @Published var voiceTimeout: Int = 2
    @Published var porcupineAccessToken: String = "YTvBtr2dk1wvG5ZeOqT5Gg8Ui2gMGy/qaeTLst0dPBBpxuJK2vkDqg=="
    @Published var voiceLanguage: String = "de"
    @Published var homeAssistantConversationAgent: String = "conversation.claude_conversation"
    @Published var homeAssistantConversationId: String = "ipad"
    
    // MARK: - UserDefaults Keys
    private enum Keys {
        static let mainDashboardURL = "mainDashboardURL"
        static let enableHomeAssistant = "enableHomeAssistant"
        static let homeAssistantIP = "homeAssistantIP"
        static let homeAssistantPort = "homeAssistantPort"
        static let accessToken = "accessToken"
        static let useHTTPS = "useHTTPS"
        static let mqttBrokerIP = "mqttBrokerIP"
        static let mqttPort = "mqttPort"
        static let mqttUsername = "mqttUsername"
        static let mqttPassword = "mqttPassword"
        static let mqttUseTLS = "mqttUseTLS"
        static let mqttTopicPrefix = "mqttTopicPrefix"
        static let enableMQTT = "enableMQTT"
        static let mqttBatteryUpdateInterval = "mqttBatteryUpdateInterval"
        static let screensaverTimeout = "screensaverTimeout"
        static let screensaverMode = "screensaverMode"
        static let screenBrightnessDimmed = "screenBrightnessDimmed"
        static let screenBrightnessNormal = "screenBrightnessNormal"
        static let enableVoiceActivation = "enableVoiceActivation"
        static let kioskURL = "kioskURL"
        static let faceDetectionInterval = "faceDetectionInterval"
        static let wakeupMethod = "wakeupMethod"
        static let motionSensitivity = "motionSensitivity"
        static let showDebugInfo = "showDebugInfo"
        static let enableAutoRefresh = "enableAutoRefresh"
        static let autoRefreshInterval = "autoRefreshInterval"
        static let enableWebServer = "enableWebServer"
        static let webServerPort = "webServerPort"
        static let webServerUsername = "webServerUsername"
        static let webServerPassword = "webServerPassword"
        static let requireDeviceAuth = "requireDeviceAuth"
        static let screenshotSecurityToken = "screenshotSecurityToken"
        static let voiceSampleRate = "voiceSampleRate"
        static let voiceTimeout = "voiceTimeout"
        static let porcupineAccessToken = "porcupineAccessToken"
        static let voiceLanguage = "voiceLanguage"
        static let homeAssistantConversationAgent = "homeAssistantConversationAgent"
        static let homeAssistantConversationId = "homeAssistantConversationId"
        static let slideshowURLs     = "slideshowURLs"     // JSON-encoded [String]
        static let slideshowInterval = "slideshowInterval"  // Double, seconds
    }
    
    /// Generates a random alphanumeric token in the format xxxx-xxxx-xxxx (0-9a-zA-Z)
    static func generateRandomSecurityToken() -> String {
        let chars = Array("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        func randomSegment(length: Int) -> String {
            return String((0..<length).map { _ in chars.randomElement() ?? "x" })
        }
        return "\(randomSegment(length: 4))-\(randomSegment(length: 4))-\(randomSegment(length: 4))"
    }
    
    /// Designated initializer. Use SettingsManager.shared in production code.
    /// Pass a custom UserDefaults suite in unit tests to get an isolated, cleanable store.
    init(userDefaults: UserDefaults = .standard) {
        _userDefaults = userDefaults
        loadSettings()
    }
    
    // MARK: - Computed Properties
    var homeAssistantBaseURL: String {
        let prot = useHTTPS ? "https" : "http"
        return "\(prot)://\(homeAssistantIP):\(homeAssistantPort)"
    }
    
    var homeAssistantWebSocketURL: String {
        let prot = useHTTPS ? "wss" : "ws"
        return "\(prot)://\(homeAssistantIP):\(homeAssistantPort)"
    }
    
    var mqttBrokerURL: String {
        let prot = mqttUseTLS ? "mqtts" : "mqtt"
        return "\(prot)://\(mqttBrokerIP):\(mqttPort)"
    }
    
    var screensaverTimeoutFormatted: String {
        let minutes = Int(screensaverTimeout / 60)
        let seconds = Int(screensaverTimeout.truncatingRemainder(dividingBy: 60))
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
    
    var batteryUpdateIntervalFormatted: String {
        if mqttBatteryUpdateInterval < 60 {
            return "\(Int(mqttBatteryUpdateInterval))s"
        } else {
            let minutes = Int(mqttBatteryUpdateInterval / 60)
            return "\(minutes)m"
        }
    }
    
    var autoRefreshIntervalFormatted: String {
        if autoRefreshInterval < 60 {
            return "\(Int(autoRefreshInterval))s"
        } else {
            let minutes = Int(autoRefreshInterval / 60)
            let remainder = Int(autoRefreshInterval.truncatingRemainder(dividingBy: 60))
            if remainder > 0 {
                return "\(minutes)m \(remainder)s"
            }
            return "\(minutes)m"
        }
    }
    
    // MARK: - Settings Management
    private func loadSettings() {
        let defaults = userDefaults
        
        if defaults.object(forKey: Keys.enableHomeAssistant) != nil {
            enableHomeAssistant = defaults.bool(forKey: Keys.enableHomeAssistant)
        } else {
            enableHomeAssistant = false
        }

        mainDashboardURL = defaults.string(forKey: Keys.mainDashboardURL) ?? defaults.string(forKey: Keys.kioskURL) ?? ""
        homeAssistantIP = defaults.string(forKey: Keys.homeAssistantIP) ?? "homeassistant.local"
        homeAssistantPort = defaults.string(forKey: Keys.homeAssistantPort) ?? "8123"
        accessToken = defaults.string(forKey: Keys.accessToken) ?? "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiIwYTJmOTU1ZDYwNjY0YmI1YTc2NGU4ZDAyNTMwZTA1ZSIsImlhdCI6MTcxOTE0MTcxNiwiZXhwIjoyMDM0NTAxNzE2fQ.u2rLYy7Mc4VIQ9-x_25Ra2IRejvkXBsRX8lxvjBzPIM"
        
        // Load boolean with proper default handling
        if defaults.object(forKey: Keys.useHTTPS) != nil {
            useHTTPS = defaults.bool(forKey: Keys.useHTTPS)
        } else {
            useHTTPS = false // Default value
        }
        
        // MQTT Settings
        mqttBrokerIP = defaults.string(forKey: Keys.mqttBrokerIP) ?? "homeassistant.local"
        mqttPort = defaults.string(forKey: Keys.mqttPort) ?? "1883"
        mqttUsername = defaults.string(forKey: Keys.mqttUsername) ?? "homeassistant"
        mqttPassword = defaults.string(forKey: Keys.mqttPassword) ?? "iepoiph4ongiesah2zoZae4AiLa8bie9oochaahaiQuoush3or3kiequoo3xohye"
        
        // Load boolean with proper default handling
        if defaults.object(forKey: Keys.mqttUseTLS) != nil {
            mqttUseTLS = defaults.bool(forKey: Keys.mqttUseTLS)
        } else {
            mqttUseTLS = false // Default value
        }
        
        mqttTopicPrefix = defaults.string(forKey: Keys.mqttTopicPrefix) ?? "homeassistant"
        
        // enableMQTT defaults to false
        if defaults.object(forKey: Keys.enableMQTT) != nil {
            enableMQTT = defaults.bool(forKey: Keys.enableMQTT)
        } else {
            enableMQTT = false // Default value: disabled
        }
        
        // Load double values with proper zero handling
        if let interval = defaults.object(forKey: Keys.mqttBatteryUpdateInterval) as? Double {
            mqttBatteryUpdateInterval = interval
        } else {
            mqttBatteryUpdateInterval = 60.0
        }
        
        if let timeout = defaults.object(forKey: Keys.screensaverTimeout) as? Double {
            screensaverTimeout = timeout
        } else {
            screensaverTimeout = 60.0
        }
        
        if let mode = defaults.string(forKey: Keys.screensaverMode) {
            screensaverMode = mode
        } else {
            screensaverMode = "off" // Default value: disabled
        }
        
        if let brightness = defaults.object(forKey: Keys.screenBrightnessDimmed) as? Double {
            screenBrightnessDimmed = brightness
        } else {
            screenBrightnessDimmed = 0.2
        }
        
        if let brightness = defaults.object(forKey: Keys.screenBrightnessNormal) as? Double {
            screenBrightnessNormal = brightness
        } else {
            screenBrightnessNormal = 0.7 // Default to 70%
        }
        
        // enableVoiceActivation defaults to false
        if defaults.object(forKey: Keys.enableVoiceActivation) != nil {
            enableVoiceActivation = defaults.bool(forKey: Keys.enableVoiceActivation)
        } else {
            enableVoiceActivation = false // Default value: disabled
        }
        
        kioskURL = defaults.string(forKey: Keys.kioskURL) ?? "http://homeassistant.local:8123/anzeige-flur/0?kiosk"
        
        if let interval = defaults.object(forKey: Keys.faceDetectionInterval) as? Double {
            faceDetectionInterval = interval
        } else {
            faceDetectionInterval = 1.0
        }
        
        wakeupMethod = defaults.string(forKey: Keys.wakeupMethod) ?? "face"
        if let sensitivity = defaults.object(forKey: Keys.motionSensitivity) as? Double {
            motionSensitivity = sensitivity
        } else {
            motionSensitivity = 0.08
        }
        
        if defaults.object(forKey: Keys.showDebugInfo) != nil {
            showDebugInfo = defaults.bool(forKey: Keys.showDebugInfo)
        } else {
            showDebugInfo = false // Default value: disabled
        }
        
        if defaults.object(forKey: Keys.enableAutoRefresh) != nil {
            enableAutoRefresh = defaults.bool(forKey: Keys.enableAutoRefresh)
        } else {
            enableAutoRefresh = false // Default value: disabled
        }
        
        if let interval = defaults.object(forKey: Keys.autoRefreshInterval) as? Double {
            autoRefreshInterval = interval
        } else {
            autoRefreshInterval = 300.0
        }
        
        if defaults.object(forKey: Keys.enableWebServer) != nil {
            enableWebServer = defaults.bool(forKey: Keys.enableWebServer)
        } else {
            enableWebServer = true // Default value: enabled by default
        }
        
        if let port = defaults.object(forKey: Keys.webServerPort) as? Int, port >= 1024, port <= 65535 {
            webServerPort = port
        } else {
            webServerPort = 8080
        }
        
        webServerUsername = defaults.string(forKey: Keys.webServerUsername) ?? "admin"
        webServerPassword = defaults.string(forKey: Keys.webServerPassword) ?? "PadPanel"
        if let auth = defaults.object(forKey: Keys.requireDeviceAuth) as? Bool {
            requireDeviceAuth = auth
        } else {
            requireDeviceAuth = true
        }
        
        if let token = defaults.string(forKey: Keys.screenshotSecurityToken), !token.isEmpty {
            screenshotSecurityToken = token
        } else {
            screenshotSecurityToken = SettingsManager.generateRandomSecurityToken()
            defaults.set(screenshotSecurityToken, forKey: Keys.screenshotSecurityToken)
        }
        
        // Voice pipeline settings
        if let sr = defaults.object(forKey: Keys.voiceSampleRate) as? Int {
            voiceSampleRate = sr
        } else {
            voiceSampleRate = 16000
        }
        
        if let to = defaults.object(forKey: Keys.voiceTimeout) as? Int {
            voiceTimeout = to
        } else {
            voiceTimeout = 2
        }
        
        porcupineAccessToken = defaults
            .string(forKey: Keys.porcupineAccessToken) ?? "YTvBtr2dk1wvG5ZeOqT5Gg8Ui2gMGy/qaeTLst0dPBBpxuJK2vkDqg=="

        voiceLanguage = defaults
            .string(forKey: Keys.voiceLanguage) ?? "de"

        homeAssistantConversationAgent = defaults
            .string(forKey: Keys.homeAssistantConversationAgent) ?? "conversation.claude_conversation"

        homeAssistantConversationId = defaults
            .string(forKey: Keys.homeAssistantConversationId) ?? "ipad"

        // Slideshow transition interval
        if let interval = defaults.object(forKey: Keys.slideshowInterval) as? Double {
            slideshowInterval = interval
        } else {
            slideshowInterval = 30.0
        }

        // Slideshow URL list — one-time migration from legacy kioskURL.
        // Read directly from UserDefaults (not self.kioskURL) to avoid picking up
        // the hardcoded fallback value on fresh installs.
        if let data = defaults.data(forKey: Keys.slideshowURLs),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            slideshowURLs = decoded
        } else if let storedURL = defaults.string(forKey: Keys.kioskURL), !storedURL.isEmpty {
            // Migrate an explicitly saved single URL to the new list format
            slideshowURLs = [storedURL]
        } else {
            // Fresh install or empty kioskURL → welcome screen mode
            slideshowURLs = []
        }
    }
    
    // MARK: - Public Save Method
    /// Saves all settings to UserDefaults. Call this explicitly when settings should be persisted.
    func saveSettings() {
        let defaults = userDefaults
        
        defaults.set(mainDashboardURL, forKey: Keys.mainDashboardURL)
        defaults.set(mainDashboardURL, forKey: Keys.kioskURL)
        defaults.set(enableHomeAssistant, forKey: Keys.enableHomeAssistant)
        defaults.set(homeAssistantIP, forKey: Keys.homeAssistantIP)
        defaults.set(homeAssistantPort, forKey: Keys.homeAssistantPort)
        defaults.set(accessToken, forKey: Keys.accessToken)
        defaults.set(useHTTPS, forKey: Keys.useHTTPS)
        
        // MQTT Settings
        defaults.set(mqttBrokerIP, forKey: Keys.mqttBrokerIP)
        defaults.set(mqttPort, forKey: Keys.mqttPort)
        defaults.set(mqttUsername, forKey: Keys.mqttUsername)
        defaults.set(mqttPassword, forKey: Keys.mqttPassword)
        defaults.set(mqttUseTLS, forKey: Keys.mqttUseTLS)
        defaults.set(mqttTopicPrefix, forKey: Keys.mqttTopicPrefix)
        defaults.set(enableMQTT, forKey: Keys.enableMQTT)
        defaults.set(mqttBatteryUpdateInterval, forKey: Keys.mqttBatteryUpdateInterval)
        
        defaults.set(screensaverTimeout, forKey: Keys.screensaverTimeout)
        defaults.set(screensaverMode, forKey: Keys.screensaverMode)
        defaults.set(screenBrightnessDimmed, forKey: Keys.screenBrightnessDimmed)
        defaults.set(screenBrightnessNormal, forKey: Keys.screenBrightnessNormal)
        defaults.set(enableVoiceActivation, forKey: Keys.enableVoiceActivation)
        defaults.set(kioskURL, forKey: Keys.kioskURL)
        defaults.set(faceDetectionInterval, forKey: Keys.faceDetectionInterval)
        defaults.set(wakeupMethod, forKey: Keys.wakeupMethod)
        defaults.set(motionSensitivity, forKey: Keys.motionSensitivity)
        defaults.set(showDebugInfo, forKey: Keys.showDebugInfo)
        defaults.set(enableAutoRefresh, forKey: Keys.enableAutoRefresh)
        defaults.set(autoRefreshInterval, forKey: Keys.autoRefreshInterval)
        defaults.set(enableWebServer, forKey: Keys.enableWebServer)
        defaults.set(webServerPort, forKey: Keys.webServerPort)
        defaults.set(webServerUsername, forKey: Keys.webServerUsername)
        defaults.set(webServerPassword, forKey: Keys.webServerPassword)
        defaults.set(requireDeviceAuth, forKey: Keys.requireDeviceAuth)
        defaults.set(screenshotSecurityToken, forKey: Keys.screenshotSecurityToken)
        
        // Voice pipeline settings
        defaults.set(voiceSampleRate, forKey: Keys.voiceSampleRate)
        defaults.set(voiceTimeout, forKey: Keys.voiceTimeout)
        defaults.set(porcupineAccessToken, forKey: Keys.porcupineAccessToken)
        defaults.set(homeAssistantConversationAgent, forKey: Keys.homeAssistantConversationAgent)
        defaults.set(homeAssistantConversationId, forKey: Keys.homeAssistantConversationId)
        defaults.set(voiceLanguage, forKey: Keys.voiceLanguage)

        defaults.set(slideshowInterval, forKey: Keys.slideshowInterval)
        if let data = try? JSONEncoder().encode(slideshowURLs) {
            defaults.set(data, forKey: Keys.slideshowURLs)
        }

        // Notify observers that settings have changed
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
    }
    
    // MARK: - Validation
    func validateSettings() -> [String] {
        var issues: [String] = []
        
        // Validate port
        if Int(homeAssistantPort) == nil || Int(homeAssistantPort)! < 1 || Int(homeAssistantPort)! > 65535 {
            issues.append("Invalid port for Home Assistant")
        }
        
        // Validate access token
        if accessToken.isEmpty {
            issues.append("Access Token is required")
        }
        
        // Validate MQTT settings if enabled
        if enableMQTT {
            if Int(mqttPort) == nil || Int(mqttPort)! < 1 || Int(mqttPort)! > 65535 {
                issues.append("Invalid MQTT port")
            }
        }
        
        // Validate timeout
        if screensaverTimeout < 10 {
            issues.append("Screensaver timeout should be at least 10 seconds")
        }
        
        // Validate face detection interval
        if faceDetectionInterval < 0.1 {
            issues.append("Face detection interval should be at least 0.1 seconds")
        }
        
        return issues
    }
    
    private func isValidIPAddress(_ ip: String) -> Bool {
        let components = ip.components(separatedBy: ".")
        guard components.count == 4 else { return false }
        
        for component in components {
            guard let num = Int(component), num >= 0 && num <= 255 else {
                return false
            }
        }
        return true
    }
    
    // MARK: - Export/Import
    func exportSettings() -> [String: Any] {
        return [
            "mainDashboardURL": mainDashboardURL,
            "enableHomeAssistant": enableHomeAssistant,
            "homeAssistantIP": homeAssistantIP,
            "homeAssistantPort": homeAssistantPort,
            "accessToken": accessToken,
            "useHTTPS": useHTTPS,
            "mqttBrokerIP": mqttBrokerIP,
            "mqttPort": mqttPort,
            "mqttUsername": mqttUsername,
            "mqttPassword": mqttPassword,
            "mqttUseTLS": mqttUseTLS,
            "mqttTopicPrefix": mqttTopicPrefix,
            "enableMQTT": enableMQTT,
            "mqttBatteryUpdateInterval": mqttBatteryUpdateInterval,
            "screensaverTimeout": screensaverTimeout,
            "screensaverMode": screensaverMode,
            "screenBrightnessDimmed": screenBrightnessDimmed,
            "screenBrightnessNormal": screenBrightnessNormal,
            "enableVoiceActivation": enableVoiceActivation,
            "faceDetectionInterval": faceDetectionInterval,
            "wakeupMethod": wakeupMethod,
            "motionSensitivity": motionSensitivity,
            "showDebugInfo": showDebugInfo,
            "enableAutoRefresh": enableAutoRefresh,
            "autoRefreshInterval": autoRefreshInterval,
            "enableWebServer": enableWebServer,
            "webServerPort": webServerPort,
            "webServerUsername": webServerUsername,
            "webServerPassword": webServerPassword,
            "requireDeviceAuth": requireDeviceAuth,
            "screenshotSecurityToken": screenshotSecurityToken,
            "voiceSampleRate": voiceSampleRate,
            "voiceTimeout": voiceTimeout,
            "porcupineAccessToken": porcupineAccessToken,
            "homeAssistantConversationAgent": homeAssistantConversationAgent,
            "homeAssistantConversationId": homeAssistantConversationId,
            "voiceLanguage": voiceLanguage,
            "slideshowURLs": slideshowURLs,
            "slideshowInterval": slideshowInterval
        ]
    }
    
    func importSettings(_ settings: [String: Any]) {
        if let main = settings["mainDashboardURL"] as? String { mainDashboardURL = main }
        if let ha = settings["enableHomeAssistant"] {
            if let b = ha as? Bool { enableHomeAssistant = b }
            else if let s = ha as? String { enableHomeAssistant = (s == "true" || s == "1" || s == "on") }
        }
        if let ip = settings["homeAssistantIP"] as? String { homeAssistantIP = ip }
        if let port = settings["homeAssistantPort"] as? String { homeAssistantPort = port }
        if let token = settings["accessToken"] as? String { accessToken = token }
        if let https = settings["useHTTPS"] {
            if let b = https as? Bool { useHTTPS = b }
            else if let s = https as? String { useHTTPS = (s == "true" || s == "1") }
        }
        
        // MQTT Settings
        if let broker = settings["mqttBrokerIP"] as? String { mqttBrokerIP = broker }
        if let port = settings["mqttPort"] as? String { mqttPort = port }
        if let user = settings["mqttUsername"] as? String { mqttUsername = user }
        if let pass = settings["mqttPassword"] as? String { mqttPassword = pass }
        if let tls = settings["mqttUseTLS"] {
            if let b = tls as? Bool { mqttUseTLS = b }
            else if let s = tls as? String { mqttUseTLS = (s == "true" || s == "1") }
        }
        if let prefix = settings["mqttTopicPrefix"] as? String { mqttTopicPrefix = prefix }
        if let mqtt = settings["enableMQTT"] {
            if let b = mqtt as? Bool { enableMQTT = b }
            else if let s = mqtt as? String { enableMQTT = (s == "true" || s == "1" || s == "on") }
        }
        if let interval = settings["mqttBatteryUpdateInterval"] {
            if let d = interval as? Double { mqttBatteryUpdateInterval = d }
            else if let s = interval as? String, let d = Double(s) { mqttBatteryUpdateInterval = d }
        }
        
        if let timeout = settings["screensaverTimeout"] {
            if let d = timeout as? Double { screensaverTimeout = d }
            else if let s = timeout as? String, let d = Double(s) { screensaverTimeout = d }
        }
        if let mode = settings["screensaverMode"] as? String { screensaverMode = mode }
        if let dimmed = settings["screenBrightnessDimmed"] {
            if let d = dimmed as? Double { screenBrightnessDimmed = d }
            else if let s = dimmed as? String, let d = Double(s) { screenBrightnessDimmed = d }
        }
        if let normal = settings["screenBrightnessNormal"] {
            if let d = normal as? Double { screenBrightnessNormal = d }
            else if let s = normal as? String, let d = Double(s) { screenBrightnessNormal = d }
        }
        if let voice = settings["enableVoiceActivation"] {
            if let b = voice as? Bool { enableVoiceActivation = b }
            else if let s = voice as? String { enableVoiceActivation = (s == "true" || s == "1" || s == "on") }
        }
        if let interval = settings["faceDetectionInterval"] {
            if let d = interval as? Double { faceDetectionInterval = d }
            else if let s = interval as? String, let d = Double(s) { faceDetectionInterval = d }
        }
        if let wakeup = settings["wakeupMethod"] as? String { wakeupMethod = wakeup }
        if let sens = settings["motionSensitivity"] {
            if let d = sens as? Double { motionSensitivity = d }
            else if let s = sens as? String, let d = Double(s) { motionSensitivity = d }
        }
        if let dbg = settings["showDebugInfo"] {
            if let b = dbg as? Bool { showDebugInfo = b }
            else if let s = dbg as? String { showDebugInfo = (s == "true" || s == "1") }
        }
        if let ref = settings["enableAutoRefresh"] {
            if let b = ref as? Bool { enableAutoRefresh = b }
            else if let s = ref as? String { enableAutoRefresh = (s == "true" || s == "1" || s == "on") }
        }
        if let refInt = settings["autoRefreshInterval"] {
            if let d = refInt as? Double { autoRefreshInterval = d }
            else if let s = refInt as? String, let d = Double(s) { autoRefreshInterval = d }
        }
        if let ws = settings["enableWebServer"] {
            if let b = ws as? Bool { enableWebServer = b }
            else if let s = ws as? String { enableWebServer = (s == "true" || s == "1" || s == "on") }
        }
        if let port = settings["webServerPort"] {
            if let i = port as? Int { webServerPort = i }
            else if let s = port as? String, let i = Int(s) { webServerPort = i }
        }
        if let user = settings["webServerUsername"] as? String { webServerUsername = user }
        if let pass = settings["webServerPassword"] as? String { webServerPassword = pass }
        if let auth = settings["requireDeviceAuth"] {
            if let b = auth as? Bool { requireDeviceAuth = b }
            else if let s = auth as? String { requireDeviceAuth = (s == "true" || s == "1") }
        }
        if let token = settings["screenshotSecurityToken"] as? String, !token.isEmpty {
            screenshotSecurityToken = token
        }

        if let convId = settings["homeAssistantConversationId"] as? String { homeAssistantConversationId = convId }
        if let agent = settings["homeAssistantConversationAgent"] as? String { homeAssistantConversationAgent = agent }
        if let lang = settings["voiceLanguage"] as? String { voiceLanguage = lang }
        if let token = settings["porcupineAccessToken"] as? String { porcupineAccessToken = token }

        if let v = settings["voiceSampleRate"] {
            if let i = v as? Int { voiceSampleRate = i }
            else if let s = v as? String, let i = Int(s) { voiceSampleRate = i }
        }
        if let v = settings["voiceTimeout"] {
            if let i = v as? Int { voiceTimeout = i }
            else if let s = v as? String, let i = Int(s) { voiceTimeout = i }
        }

        if let urls = settings["slideshowURLs"] as? [String] {
            slideshowURLs = urls
        } else if let urlsString = settings["slideshowURLs"] as? String {
            if let data = urlsString.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([String].self, from: data) {
                slideshowURLs = decoded
            } else {
                slideshowURLs = urlsString.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            }
        }

        if let interval = settings["slideshowInterval"] {
            if let d = interval as? Double { slideshowInterval = d }
            else if let s = interval as? String, let d = Double(s) { slideshowInterval = d }
        }
    }

    /// Generates a structured, human-readable configuration file for padpanel-settings.conf.
    func exportConfigFileString() -> String {
        let formatter = ISO8601DateFormatter()
        let now = formatter.string(from: Date())
        let urlsJson = (try? String(data: JSONEncoder().encode(slideshowURLs), encoding: .utf8)) ?? "[]"

        return """
        # ====================================================================
        # PadPanel Configuration File: padpanel-settings.conf
        # Exported: \(now)
        # ====================================================================

        [Dashboard]
        mainDashboardURL = \(mainDashboardURL)
        enableAutoRefresh = \(enableAutoRefresh)
        autoRefreshInterval = \(autoRefreshInterval)

        [HomeAssistant]
        enableHomeAssistant = \(enableHomeAssistant)
        homeAssistantIP = \(homeAssistantIP)
        homeAssistantPort = \(homeAssistantPort)
        useHTTPS = \(useHTTPS)
        accessToken = \(accessToken)
        homeAssistantConversationAgent = \(homeAssistantConversationAgent)
        homeAssistantConversationId = \(homeAssistantConversationId)

        [VoiceControl]
        enableVoiceActivation = \(enableVoiceActivation)
        voiceSampleRate = \(voiceSampleRate)
        voiceTimeout = \(voiceTimeout)
        voiceLanguage = \(voiceLanguage)
        porcupineAccessToken = \(porcupineAccessToken)

        [Screensaver]
        screensaverMode = \(screensaverMode)
        screensaverTimeout = \(screensaverTimeout)
        screenBrightnessNormal = \(screenBrightnessNormal)
        screenBrightnessDimmed = \(screenBrightnessDimmed)
        wakeupMethod = \(wakeupMethod)
        motionSensitivity = \(motionSensitivity)
        faceDetectionInterval = \(faceDetectionInterval)
        showDebugInfo = \(showDebugInfo)
        slideshowURLs = \(urlsJson)
        slideshowInterval = \(slideshowInterval)

        [MQTT]
        enableMQTT = \(enableMQTT)
        mqttBrokerIP = \(mqttBrokerIP)
        mqttPort = \(mqttPort)
        mqttUsername = \(mqttUsername)
        mqttPassword = \(mqttPassword)
        mqttUseTLS = \(mqttUseTLS)
        mqttTopicPrefix = \(mqttTopicPrefix)
        mqttBatteryUpdateInterval = \(mqttBatteryUpdateInterval)

        [WebServer_and_Security]
        enableWebServer = \(enableWebServer)
        webServerPort = \(webServerPort)
        webServerUsername = \(webServerUsername)
        webServerPassword = \(webServerPassword)
        requireDeviceAuth = \(requireDeviceAuth)
        screenshotSecurityToken = \(screenshotSecurityToken)
        """
    }

    /// Parses and applies configuration from padpanel-settings.conf plain text (or JSON).
    @discardableResult
    func importConfigFileString(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // Try JSON parsing first (if the uploaded file happens to be JSON)
        if trimmed.hasPrefix("{") && trimmed.hasSuffix("}"),
           let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            importSettings(json)
            saveSettings()
            return true
        }

        // Parse key-value lines
        var dict: [String: Any] = [:]
        for rawLine in trimmed.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("//") || line.hasPrefix(";") || (line.hasPrefix("[") && line.hasSuffix("]")) {
                continue
            }
            guard let equalIdx = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<equalIdx]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: equalIdx)...]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }

            if key == "slideshowURLs" {
                if let data = value.data(using: .utf8),
                   let list = try? JSONDecoder().decode([String].self, from: data) {
                    dict[key] = list
                } else {
                    dict[key] = value
                }
            } else if value.lowercased() == "true" || value.lowercased() == "false" {
                dict[key] = (value.lowercased() == "true")
            } else if let intVal = Int(value) {
                dict[key] = intVal
            } else if let doubleVal = Double(value) {
                dict[key] = doubleVal
            } else {
                dict[key] = value
            }
        }

        if !dict.isEmpty {
            importSettings(dict)
            saveSettings()
            return true
        }
        return false
    }
    
    // MARK: - Screenshot Token
    func regenerateScreenshotToken() {
        screenshotSecurityToken = SettingsManager.generateRandomSecurityToken()
        saveSettings()
    }
    
    // MARK: - Reset
    func resetToDefaults() {
        mainDashboardURL = ""
        enableHomeAssistant = false
        homeAssistantIP = "homeassistant.local"
        homeAssistantPort = "8123"
        accessToken = ""
        useHTTPS = false
        
        mqttBrokerIP = "homeassistant.local"
        mqttPort = "1883"
        mqttUsername = ""
        mqttPassword = ""
        mqttUseTLS = false
        mqttTopicPrefix = "homeassistant"
        enableMQTT = false
        mqttBatteryUpdateInterval = 60.0
        
        screensaverTimeout = 60.0
        screensaverMode = "off"
        screenBrightnessDimmed = 0.2
        screenBrightnessNormal = 0.7
        enableVoiceActivation = false
        kioskURL = ""
        faceDetectionInterval = 1.0
        wakeupMethod = "face"
        motionSensitivity = 0.08
        showDebugInfo = false
        enableAutoRefresh = false
        autoRefreshInterval = 300.0
        enableWebServer = true
        webServerPort = 8080
        webServerUsername = "admin"
        webServerPassword = "PadPanel"
        requireDeviceAuth = true
        
        // Voice pipeline defaults
        voiceSampleRate = 16000
        voiceTimeout = 2
        
        voiceLanguage = "de"
        homeAssistantConversationId = "ipad"
        homeAssistantConversationAgent = "conversation.claude_conversation"

        slideshowURLs = []
        slideshowInterval = 30.0
    }

    // MARK: - Computed Properties

    /// Returns the active URLs to load into WebViews.
    /// Index 0 is the main dashboard URL; subsequent indices are screensaver cycle URLs.
    var effectiveURLs: [String] {
        var list: [String] = []
        let trimmedMain = mainDashboardURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedMain.isEmpty {
            list.append(trimmedMain)
        }
        for url in slideshowURLs {
            let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !list.contains(trimmed) {
                list.append(trimmed)
            }
        }
        return list
    }
}
