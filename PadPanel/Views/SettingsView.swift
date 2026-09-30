import SwiftUI
import CocoaMQTT

// MARK: - Settings View
struct SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var webServer = WebServerManager.shared
    @Environment(\.presentationMode) var presentationMode
    @State private var showingValidationAlert = false
    @State private var validationIssues: [String] = []
    @State private var showingResetAlert = false
    @State private var testConnectionResult = ""
    @State private var isTestingConnection = false
    
    var body: some View {
        NavigationView {
            Form {
                mainDashboardSection
                screensaverSection
                homeAssistantSection
                mqttSection
                deviceAuthSection
                webServerSection
                kioskSection
                actionsSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        // Reload settings to discard changes
                        settings.objectWillChange.send()
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveAndClose()
                    }
                    //.fontWeight(.semibold)
                    .font(.system(size: 17, weight: .semibold))
                }
            }
            .alert("Validation error", isPresented: $showingValidationAlert) {
                Button("OK") { }
            } message: {
                Text(validationIssues.joined(separator: "\n"))
            }
            .alert("Reset settings", isPresented: $showingResetAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    settings.resetToDefaults()
                }
            } message: {
                Text("Do you want to reset all settings to the default values?")
            }
        }
        .onAppear {
            UIScreen.main.brightness = CGFloat(settings.screenBrightnessNormal)
        }
    }
    
    private var mainDashboardSection: some View {
        Section(
            header: Text("Main Dashboard URL"),
            footer: Text("This is your primary kiosk dashboard displayed on the iPad screen.")
        ) {
            HStack {
                Image(systemName: "globe")
                    .foregroundColor(.blue)
                TextField("http://homeassistant.local:8123/...", text: $settings.mainDashboardURL)
                    .textFieldStyle(PlainTextFieldStyle())
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)
            }
            if !settings.mainDashboardURL.isEmpty {
                Button(action: {
                    NotificationCenter.default.post(name: .reloadAllWebViews, object: nil)
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Reload Dashboard")
                    }
                    .font(.caption)
                }
            }
        }
    }

    private var mqttSection: some View {
        Section("MQTT Integration") {
            Toggle("Enable MQTT", isOn: $settings.enableMQTT.animation())
            
            if settings.enableMQTT {
                HStack {
                    Text("Broker IP/Name")
                    Spacer()
                    TextField("192.168.1.100", text: $settings.mqttBrokerIP)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(maxWidth: 150)
                }
                
                HStack {
                    Text("Port")
                    Spacer()
                    TextField("1883", text: $settings.mqttPort)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(.numberPad)
                        .frame(maxWidth: 100)
                }
                
                Toggle("Use TLS/SSL", isOn: $settings.mqttUseTLS)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Username (optional)")
                    TextField("MQTT Username", text: $settings.mqttUsername)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Password (optional)")
                    SecureField("MQTT Password", text: $settings.mqttPassword)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Topic Prefix")
                    TextField("homeassistant", text: $settings.mqttTopicPrefix)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Device Info (automatically generated)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    if let mqttManager = getMQTTManager() {
                        let deviceInfo = mqttManager.getDeviceInfo()
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Device ID: \(deviceInfo["device_id"] ?? "N/A")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Device Name: \(deviceInfo["device_name"] ?? "N/A")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Model: \(deviceInfo["model_identifier"] ?? "N/A")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Battery Update Interval: \(settings.batteryUpdateIntervalFormatted)")
                    Slider(value: $settings.mqttBatteryUpdateInterval, in: 30...600, step: 30) {
                        Text("Interval")
                    } minimumValueLabel: {
                        Text("30s")
                    } maximumValueLabel: {
                        Text("10m")
                    }
                }
                
                Button(action: testMQTTConnection) {
                    HStack {
                        if isTestingConnection {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                        }
                        Text("Test MQTT connection")
                    }
                }
                .disabled(isTestingConnection)
                
                if !testConnectionResult.isEmpty {
                    Text(testConnectionResult)
                        .font(.caption)
                        .foregroundColor(testConnectionResult.contains("Erfolgreich") ? .green : .red)
                }
            }
        }
    }
    
    private var homeAssistantSection: some View {
        Section(
            header: Text("Home Assistant Integration"),
            footer: Text("Enables background REST API communication and native Assist voice control with your Home Assistant server.")
        ) {
            Toggle("Enable Home Assistant", isOn: $settings.enableHomeAssistant.animation())
            
            if settings.enableHomeAssistant {
                HStack {
                    Text("IP/Name")
                    Spacer()
                    TextField("192.168.1.100", text: $settings.homeAssistantIP)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .frame(maxWidth: 160)
                }
                
                HStack {
                    Text("Port")
                    Spacer()
                    TextField("8123", text: $settings.homeAssistantPort)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(.numberPad)
                        .frame(maxWidth: 100)
                }
                
                Toggle("Use HTTPS", isOn: $settings.useHTTPS)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Long-lived Access Token")
                    SecureField("Bearer Access Token", text: $settings.accessToken)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    Text("Create in Home Assistant under Profile → Security → Long-Lived Access Tokens")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Button(action: testConnection) {
                    HStack {
                        if isTestingConnection {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "network")
                        }
                        Text("Test connection")
                    }
                }
                .disabled(isTestingConnection)
                
                if !testConnectionResult.isEmpty {
                    Text(testConnectionResult)
                        .font(.caption)
                        .foregroundColor(testConnectionResult.contains("Success") ? .green : .red)
                }
                
                // Embedded Voice Control (Assist) Pipeline
                Toggle("Enable Voice Control (Assist)", isOn: $settings.enableVoiceActivation.animation())
                
                if settings.enableVoiceActivation {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sample rate: \(settings.voiceSampleRate) Hz")
                        let supportedSampleRates: [Int] = [8000, 12000, 16000, 22050, 32000, 44100]
                        Picker("Sample rate", selection: $settings.voiceSampleRate) {
                            ForEach(supportedSampleRates, id: \.self) { rate in
                                Text("\(rate / 1000) kHz").tag(rate)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Timeout: \(settings.voiceTimeout)s")
                        Slider(value: Binding(
                            get: { Double(settings.voiceTimeout) },
                            set: { settings.voiceTimeout = Int($0) }
                        ), in: 1...60, step: 1)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Porcupine Access Token")
                        SecureField("Picovoice Access Token", text: $settings.porcupineAccessToken)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        Text("Create a Porcupine AccessKey in the Picovoice web console")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    
    private var screensaverModeDescription: String {
        switch settings.screensaverMode {
        case "clock":
            return "Clock overlay with time, date, dimming, and face/motion sensor wakeup."
        case "dimming":
            return "Dimming only. Dims screen when inactive without overlay. Tap or sensors restore brightness."
        case "urls":
            return "Smoothly cycles through configured screensaver URLs while inactive. Tap returns to dashboard."
        case "off":
            return "Screensaver, dimming, and camera sensors are completely disabled."
        default:
            return ""
        }
    }
    
    private var screensaverSection: some View {
        Section("Screensaver") {
            Toggle("Enable Screensaver", isOn: Binding(
                get: { settings.screensaverMode != "off" },
                set: { isEnabled in
                    settings.screensaverMode = isEnabled ? "clock" : "off"
                }
            ).animation())
            
            if settings.screensaverMode != "off" {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Screensaver option")
                    Picker("Screensaver option", selection: $settings.screensaverMode) {
                        Text("Clock & Sensors").tag("clock")
                        Text("Dimming Only").tag("dimming")
                        Text("Cycle URLs").tag("urls")
                    }
                    .pickerStyle(.segmented)
                    
                    Text(screensaverModeDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if settings.screensaverMode == "urls" {
                    NavigationLink("Manage Cycle URLs (\(settings.slideshowURLs.count))") {
                        URLListEditor(
                            committedURLs: $settings.slideshowURLs,
                            committedInterval: $settings.slideshowInterval
                        )
                    }
                    Text(settings.slideshowURLs.isEmpty
                         ? "No cycle URLs configured — main dashboard will stay visible"
                         : "\(settings.slideshowURLs.count) URL(s) configured for screensaver")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Cycle interval: \(Int(settings.slideshowInterval))s")
                        Slider(value: $settings.slideshowInterval, in: 5...600, step: 5) {
                            Text("Interval")
                        } minimumValueLabel: {
                            Text("5s")
                        } maximumValueLabel: {
                            Text("10m")
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Inactivity timeout: \(settings.screensaverTimeoutFormatted)")
                    Slider(value: $settings.screensaverTimeout, in: 10...1800, step: 10) {
                        Text("Timeout")
                    } minimumValueLabel: {
                        Text("10s")
                    } maximumValueLabel: {
                        Text("30m")
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Screen brightness (dimmed): \(Int(settings.screenBrightnessDimmed * 100))%")
                    Slider(value: $settings.screenBrightnessDimmed, in: 0.05...0.8, step: 0.05)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Wakeup method")
                    Picker("Wakeup method", selection: $settings.wakeupMethod) {
                        Text("Face Detection").tag("face")
                        Text("Motion Detection").tag("motion")
                    }
                    .pickerStyle(.segmented)
                }

                if settings.wakeupMethod == "motion" {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(format: "Motion sensitivity: %.0f%% change", settings.motionSensitivity * 100))
                        Slider(value: $settings.motionSensitivity, in: 0.02...0.25, step: 0.01) {
                            Text("Motion Sensitivity")
                        } minimumValueLabel: {
                            Text("High (2%)")
                        } maximumValueLabel: {
                            Text("Low (25%)")
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(format: "Face detection interval: %.1fs", settings.faceDetectionInterval))
                        Slider(value: $settings.faceDetectionInterval, in: 0.1...5.0, step: 0.1) {
                            Text("Interval")
                        } minimumValueLabel: {
                            Text("0.1s")
                        } maximumValueLabel: {
                            Text("5s")
                        }
                    }
                }
                
                Toggle("Show camera debug info", isOn: $settings.showDebugInfo)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Screen brightness (normal): \(Int(settings.screenBrightnessNormal * 100))%")
                Slider(value: $settings.screenBrightnessNormal, in: 0.3...1.0, step: 0.05)
            }
        }
    }
    
    private var deviceAuthSection: some View {
        Section(
            header: Text("Device & WebUI Authentication"),
            footer: Text("These credentials protect on-device Kiosk Settings and provide HTTP Basic authentication for the Remote Web UI.")
        ) {
            Toggle("Require Password for Settings", isOn: $settings.requireDeviceAuth.animation())
            
            if settings.requireDeviceAuth {
                HStack {
                    Text("Username")
                    Spacer()
                    TextField("admin", text: $settings.webServerUsername)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .frame(maxWidth: 160)
                }
                
                HStack {
                    Text("Password")
                    Spacer()
                    SecureField("Required password", text: $settings.webServerPassword)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .frame(maxWidth: 160)
                }
            }
        }
    }
    
    private var webServerSection: some View {
        Section("Remote Web UI") {
            Toggle("Enable Remote Web UI", isOn: $settings.enableWebServer.animation())
            
            if settings.enableWebServer {
                if !webServer.serverURL.isEmpty {
                    HStack {
                        Text("Address")
                        Spacer()
                        Text(webServer.serverURL)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.blue)
                    }
                } else if let error = webServer.lastError {
                    Text("Error: \(error)")
                        .font(.caption)
                        .foregroundColor(.red)
                    } else {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text("Starting server...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack {
                    Text("Port")
                    Spacer()
                    TextField("8080", text: Binding(
                        get: { String(settings.webServerPort) },
                        set: { if let p = Int($0) { settings.webServerPort = p } }
                    ))
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(.numberPad)
                    .frame(maxWidth: 100)
                }
                
                HStack {
                    Text("Authentication")
                    Spacer()
                    if settings.webServerPassword.isEmpty {
                        Text("Open (No Password)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Protected (\(settings.webServerUsername))")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
                
                Text("Access this URL from any computer, phone, or browser on your local network to manage all settings and actions remotely.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var kioskSection: some View {
        Section(
            header: Text("Kiosk Page Refresh"),
            footer: Text("Periodically reloads the dashboard webpage to prevent memory bloat and keep real-time UI synchronized.")
        ) {
            Toggle("Auto refresh page", isOn: $settings.enableAutoRefresh.animation())
            
            if settings.enableAutoRefresh {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Refresh interval: \(settings.autoRefreshIntervalFormatted)")
                    Slider(value: $settings.autoRefreshInterval, in: 10...3600, step: 10) {
                        Text("Refresh Interval")
                    } minimumValueLabel: {
                        Text("10s")
                    } maximumValueLabel: {
                        Text("60m")
                    }
                }
            }
        }
    }
    
    private var actionsSection: some View {
        Section("Actions") {
            Button("Reset settings") {
                showingResetAlert = true
            }
            .foregroundColor(.red)
            
            Button("Export settings") {
                exportSettings()
            }
        }
    }
    
    // MARK: - Actions
    private func saveAndClose() {
        validationIssues = settings.validateSettings()
        
        if validationIssues.isEmpty {
            settings.saveSettings() // Save settings explicitly
            presentationMode.wrappedValue.dismiss()
        } else {
            showingValidationAlert = true
        }
    }
    
    private func getMQTTManager() -> MQTTManager? {
        // In a real implementation, this would be injected or accessed via environment
        // For now, create a temporary instance just to get device info
        return MQTTManager()
    }
    
    private func testMQTTConnection() {
        isTestingConnection = true
        testConnectionResult = ""
        
        // Simple MQTT connection test using CocoaMQTT
        guard let port = UInt16(settings.mqttPort) else {
            testConnectionResult = "❌ Invalid port"
            isTestingConnection = false
            return
        }
        
        let testClient = CocoaMQTT(clientID: "test_client", host: settings.mqttBrokerIP, port: port)
        testClient.username = settings.mqttUsername.isEmpty ? nil : settings.mqttUsername
        testClient.password = settings.mqttPassword.isEmpty ? nil : settings.mqttPassword
        testClient.enableSSL = settings.mqttUseTLS
        testClient.keepAlive = 5
        testClient.cleanSession = true
        
        var connectionResult: String?
        
        testClient.didConnectAck = { _, ack in
            if ack == .accept {
                connectionResult = "✅ MQTT connection successful"
                testClient.disconnect()
            } else {
                connectionResult = "❌ MQTT connection refused: \(ack)"
            }
        }
        
        if !testClient.connect() {
            testConnectionResult = "❌ MQTT Client could not be started"
            isTestingConnection = false
            return
        }
        
        // Wait for connection result
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            self.isTestingConnection = false
            self.testConnectionResult = connectionResult ?? "❌ Timeout during MQTT connection"
        }
    }
    
    private func testConnection() {
        isTestingConnection = true
        testConnectionResult = ""
        
        let url = URL(string: "\(settings.homeAssistantBaseURL)/api/")!
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(settings.accessToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isTestingConnection = false
                
                if let error = error {
                    testConnectionResult = "Error: \(error.localizedDescription)"
                } else if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        testConnectionResult = "✅ Connection successful"
                    } else {
                        testConnectionResult = "❌ HTTP \(httpResponse.statusCode)"
                    }
                } else {
                    testConnectionResult = "❌ Unknown error"
                }
            }
        }.resume()
    }
    
    private func exportSettings() {
        let settings = settings.exportSettings()
        if let data = try? JSONSerialization.data(withJSONObject: settings, options: .prettyPrinted),
           let jsonString = String(data: data, encoding: .utf8) {
            
            let activityViewController = UIActivityViewController(
                activityItems: [jsonString],
                applicationActivities: nil
            )
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                window.rootViewController?.present(activityViewController, animated: true)
            }
        }
    }
}

// MARK: - URL List Editor

private let maxURLCount = 5

/// Allows the user to add, remove, reorder, and edit slideshow URLs,
/// and to configure the transition interval when more than one URL is set.
/// Operates on a local copy; changes are committed only on Save.
struct URLListEditor: View {

    /// The committed values from SettingsManager — only written on Save.
    @Binding var committedURLs: [String]
    @Binding var committedInterval: Double

    /// Local working copies — discarded on Cancel.
    @State private var urls: [String]
    @State private var interval: Double

    @Environment(\.dismiss) private var dismiss

    init(committedURLs: Binding<[String]>, committedInterval: Binding<Double>) {
        _committedURLs = committedURLs
        _committedInterval = committedInterval
        _urls = State(initialValue: committedURLs.wrappedValue)
        _interval = State(initialValue: committedInterval.wrappedValue)
    }

    var body: some View {
        List {
            Section("URLs") {
                ForEach(Array(urls.enumerated()), id: \.offset) { i, _ in
                    TextField("https://your-dashboard.local", text: $urls[i])
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                .onMove { from, to in urls.move(fromOffsets: from, toOffset: to) }
                .onDelete { idx in urls.remove(atOffsets: idx) }

                if urls.count < maxURLCount {
                    Button {
                        urls.append("")
                    } label: {
                        Label("Add URL", systemImage: "plus.circle")
                    }
                } else {
                    Text("Maximum of \(maxURLCount) URLs reached")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if urls.count > 1 {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Transition interval: \(Int(interval)) s")
                        Slider(value: $interval, in: 5...300, step: 5) {
                            Text("Interval")
                        } minimumValueLabel: {
                            Text("5 s")
                        } maximumValueLabel: {
                            Text("5 min")
                        }
                    }
                } header: {
                    Text("Slideshow")
                } footer: {
                    Text("Time each slide is shown before cross-fading to the next.")
                }
            }
        }
        .navigationTitle("Slideshow URLs")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    committedURLs = urls
                    committedInterval = interval
                    dismiss()
                }
                .font(.system(size: 17, weight: .semibold))
            }
        }
    }
}

// MARK: - Notification Extension
extension Notification.Name {
    static let settingsChanged = Notification.Name("SettingsChanged")
    static let openSettings = Notification.Name("OpenSettings")
    /// Posted after settings are saved and the WKWebView cache has been cleared.
    /// Every KioskWebView reloads its content when it receives this notification.
    static let reloadAllWebViews = Notification.Name("PadPanel.reloadAllWebViews")
}
