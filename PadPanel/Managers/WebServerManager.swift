import Foundation
import Network
import Combine
import UIKit
#if canImport(Darwin)
import Darwin
#endif

/// Lightweight zero-dependency embedded HTTP server for remote kiosk management.
/// Powered by Apple's Network.framework (iOS 12+ / iOS 15).
final class WebServerManager: ObservableObject {
    static let shared = WebServerManager()

    @Published var isRunning = false
    @Published var serverURL: String = ""
    @Published var lastError: String? = nil

    private var listener: NWListener?
    private var activePort: Int?
    private let queue = DispatchQueue(label: "padpanel.webserver.queue", qos: .userInitiated)
    private var cancellables = Set<AnyCancellable>()
    private let settings = SettingsManager.shared

    init() {
        setupObservers()
    }

    deinit {
        stop()
    }

    private func setupObservers() {
        // Watch enableWebServer and webServerPort, ignoring identical consecutive values
        Publishers.CombineLatest(settings.$enableWebServer, settings.$webServerPort)
            .removeDuplicates { prev, curr in
                return prev.0 == curr.0 && prev.1 == curr.1
            }
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled, port in
                guard let self = self else { return }
                if enabled {
                    if !self.isRunning || self.activePort != port {
                        self.restart(port: port)
                    }
                } else {
                    self.stop()
                }
            }
            .store(in: &cancellables)
    }

    func start() {
        guard settings.enableWebServer else { return }
        if isRunning && activePort == settings.webServerPort {
            return // Already running on desired port
        }
        restart(port: settings.webServerPort)
    }

    func restart(port: Int) {
        stop()
        guard settings.enableWebServer else { return }
        // Brief asynchronous deferral to allow Darwin network stack to release the socket
        queue.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.startListener(port: port)
        }
    }

    func stop() {
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        activePort = nil
        DispatchQueue.main.async {
            self.isRunning = false
            self.serverURL = ""
            self.lastError = nil
        }
    }

    private func startListener(port: Int) {
        let validPort = UInt16(min(max(port, 1024), 65535))
        guard let endpointPort = NWEndpoint.Port(rawValue: validPort) else {
            DispatchQueue.main.async {
                self.lastError = "Invalid port: \(port)"
                self.isRunning = false
                self.activePort = nil
            }
            return
        }

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            parameters.acceptLocalOnly = false

            let newListener = try NWListener(using: parameters, on: endpointPort)

            newListener.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        self.isRunning = true
                        self.activePort = Int(validPort)
                        self.lastError = nil
                        let ip = self.getWiFiAddress() ?? "localhost"
                        self.serverURL = "http://\(ip):\(validPort)"
                        AppLogger.app.info("Remote Web Server listening on \(self.serverURL)")
                    case .failed(let error):
                        self.isRunning = false
                        self.activePort = nil
                        self.lastError = error.localizedDescription
                        AppLogger.app.error("Remote Web Server failed: \(error.localizedDescription)")
                    case .cancelled:
                        self.isRunning = false
                        self.activePort = nil
                    default:
                        break
                    }
                }
            }

            newListener.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            newListener.start(queue: queue)
            self.listener = newListener

        } catch {
            DispatchQueue.main.async {
                self.lastError = error.localizedDescription
                self.isRunning = false
                self.activePort = nil
            }
            AppLogger.app.error("Could not start Web Server: \(error.localizedDescription)")
        }
    }

    // MARK: - Connection & HTTP Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveHTTPRequest(connection: connection, accumulatedData: Data())
    }

    private func receiveHTTPRequest(connection: NWConnection, accumulatedData: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else {
                connection.cancel()
                return
            }

            if let error = error {
                AppLogger.app.debug("Web server connection read error: \(error.localizedDescription)")
                connection.cancel()
                return
            }

            var currentData = accumulatedData
            if let data = data {
                currentData.append(data)
            }

            // Check if we have received complete HTTP headers (\r\n\r\n)
            let headerEndMarker = Data([0x0D, 0x0A, 0x0D, 0x0A])
            if let headerEndRange = currentData.range(of: headerEndMarker) {
                let headerData = currentData.subdata(in: 0..<headerEndRange.lowerBound)
                if let headerString = String(data: headerData, encoding: .utf8) {
                    var expectedContentLength = 0
                    for line in headerString.components(separatedBy: "\r\n") {
                        let lower = line.lowercased()
                        if lower.hasPrefix("content-length:") {
                            let parts = line.components(separatedBy: ":")
                            if parts.count >= 2, let len = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
                                expectedContentLength = len
                            }
                        }
                    }
                    let bodyReceivedLength = currentData.count - headerEndRange.upperBound
                    if bodyReceivedLength < expectedContentLength && !isComplete {
                        // More body data needed
                        self.receiveHTTPRequest(connection: connection, accumulatedData: currentData)
                        return
                    }
                }

                if let requestString = String(data: currentData, encoding: .utf8) {
                    self.processHTTPRequest(requestString: requestString, rawData: currentData, connection: connection)
                } else {
                    self.sendResponse(connection: connection, statusCode: 400, statusText: "Bad Request", contentType: "text/plain", body: "Invalid HTTP request")
                }
            } else if !isComplete {
                // More header data needed
                self.receiveHTTPRequest(connection: connection, accumulatedData: currentData)
            } else {
                connection.cancel()
            }
        }
    }

    private struct ParsedRequest {
        var method: String
        var path: String
        var headers: [String: String]
        var body: String
    }

    private func parseRequest(requestString: String) -> ParsedRequest? {
        let lines = requestString.components(separatedBy: "\r\n")
        guard let firstLine = lines.first, !firstLine.isEmpty else { return nil }

        let requestParts = firstLine.components(separatedBy: " ")
        guard requestParts.count >= 2 else { return nil }

        let method = requestParts[0].uppercased()
        let path = requestParts[1]

        var headers: [String: String] = [:]
        var bodyStartIndex = lines.count

        for (idx, line) in lines.enumerated() {
            if idx == 0 { continue }
            if line.isEmpty {
                bodyStartIndex = idx + 1
                break
            }
            if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces).lowercased()
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }

        let body = bodyStartIndex < lines.count ? lines[bodyStartIndex...].joined(separator: "\r\n") : ""
        return ParsedRequest(method: method, path: path, headers: headers, body: body)
    }

    private func checkAuthentication(request: ParsedRequest) -> Bool {
        let expectedPassword = settings.webServerPassword
        let expectedUsername = settings.webServerUsername
        if expectedPassword.isEmpty {
            return true
        }

        // Check query param e.g. /?password=xyz or /api/status?password=xyz&username=admin
        if let queryStart = request.path.firstIndex(of: "?") {
            let queryString = String(request.path[request.path.index(after: queryStart)...])
            var queryPass = ""
            var queryUser = ""
            for pair in queryString.components(separatedBy: "&") {
                let kv = pair.components(separatedBy: "=")
                if kv.count == 2 {
                    if kv[0] == "password" || kv[0] == "auth" { queryPass = kv[1] }
                    if kv[0] == "username" || kv[0] == "user" { queryUser = kv[1] }
                }
            }
            if queryPass == expectedPassword {
                if expectedUsername.isEmpty || queryUser.isEmpty || queryUser.lowercased() == expectedUsername.lowercased() {
                    return true
                }
            }
        }

        // Check Authorization: Basic base64(user:password)
        if let authHeader = request.headers["authorization"], authHeader.lowercased().hasPrefix("basic ") {
            let base64Token = String(authHeader.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            if let decodedData = Data(base64Encoded: base64Token),
               let credentials = String(data: decodedData, encoding: .utf8) {
                let parts = credentials.components(separatedBy: ":")
                if parts.count >= 2 {
                    let user = parts[0]
                    let pass = parts[1]
                    let isUserMatch = expectedUsername.isEmpty || user.lowercased() == expectedUsername.lowercased()
                    if isUserMatch && pass == expectedPassword {
                        return true
                    }
                } else if parts.count == 1 && parts[0] == expectedPassword {
                    return true
                }
            }
        }

        // Check custom header
        if let token = request.headers["x-auth-password"], token == expectedPassword {
            return true
        }

        return false
    }

    private func processHTTPRequest(requestString: String, rawData: Data, connection: NWConnection) {
        guard let request = parseRequest(requestString: requestString) else {
            sendResponse(connection: connection, statusCode: 400, statusText: "Bad Request", contentType: "text/plain", body: "Malformed HTTP request")
            return
        }

        // Clean path without query parameters
        let rawPath = request.path
        let cleanPath = rawPath.components(separatedBy: "?").first ?? "/"

        // Authenticate request
        if !checkAuthentication(request: request) {
            let authHeaders = ["WWW-Authenticate": "Basic realm=\"UltraKiosk Remote Admin\""]
            let body = """
            <!DOCTYPE html>
            <html>
            <head><meta charset="utf-8"><title>Unauthorized</title></head>
            <body style="font-family:sans-serif;text-align:center;padding:50px;background:#1a1a1a;color:#fff;">
                <h2>Authentication Required</h2>
                <p>Please enter the password configured in UltraKiosk settings.</p>
            </body>
            </html>
            """
            sendResponse(connection: connection, statusCode: 401, statusText: "Unauthorized", contentType: "text/html", headers: authHeaders, body: body)
            return
        }

        switch (request.method, cleanPath) {
        case ("GET", "/"), ("GET", "/index.html"):
            let html = generateDashboardHTML()
            sendResponse(connection: connection, statusCode: 200, statusText: "OK", contentType: "text/html; charset=utf-8", body: html)

        case ("GET", "/api/status"):
            let json = generateStatusJSON()
            sendResponse(connection: connection, statusCode: 200, statusText: "OK", contentType: "application/json", body: json)

        case ("POST", "/api/brightness"):
            handleBrightnessChange(request: request, connection: connection)

        case ("POST", "/api/settings"):
            handleSaveSettings(request: request, connection: connection)

        case ("POST", "/api/action"):
            handleAction(request: request, connection: connection)

        default:
            sendResponse(connection: connection, statusCode: 404, statusText: "Not Found", contentType: "text/plain", body: "Endpoint not found")
        }
    }

    private func handleBrightnessChange(request: ParsedRequest, connection: NWConnection) {
        guard let data = request.body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            sendResponse(connection: connection, statusCode: 400, statusText: "Bad Request", contentType: "application/json", body: "{\"error\":\"Invalid JSON\"}")
            return
        }

        var updatedNormal: Double? = nil
        var updatedDimmed: Double? = nil

        if let norm = json["screenBrightnessNormal"] {
            if let d = norm as? Double { updatedNormal = d }
            else if let s = norm as? String, let d = Double(s) { updatedNormal = d }
        } else if let val = json["brightness"] {
            if let d = val as? Double { updatedNormal = d }
            else if let s = val as? String, let d = Double(s) { updatedNormal = d }
        }

        if let dim = json["screenBrightnessDimmed"] {
            if let d = dim as? Double { updatedDimmed = d }
            else if let s = dim as? String, let d = Double(s) { updatedDimmed = d }
        }

        DispatchQueue.main.async {
            if let n = updatedNormal {
                self.settings.screenBrightnessNormal = n
                UIScreen.main.brightness = CGFloat(n)
            }
            if let d = updatedDimmed {
                self.settings.screenBrightnessDimmed = d
            }
            self.settings.saveSettings()
        }

        sendResponse(connection: connection, statusCode: 200, statusText: "OK", contentType: "application/json", body: "{\"success\":true,\"brightness\":\(updatedNormal ?? settings.screenBrightnessNormal)}")
    }

    private func handleAction(request: ParsedRequest, connection: NWConnection) {
        guard let data = request.body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let action = json["action"] as? String else {
            sendResponse(connection: connection, statusCode: 400, statusText: "Bad Request", contentType: "application/json", body: "{\"error\":\"Invalid action request\"}")
            return
        }

        DispatchQueue.main.async {
            switch action {
            case "screensaver":
                NotificationCenter.default.post(name: .mqttScreensaverActivated, object: nil)
            case "wakeup":
                NotificationCenter.default.post(name: .remoteWakeup, object: nil)
            case "reload":
                NotificationCenter.default.post(name: .reloadAllWebViews, object: nil)
            default:
                break
            }
        }

        sendResponse(connection: connection, statusCode: 200, statusText: "OK", contentType: "application/json", body: "{\"success\":true,\"action\":\"\(action)\"}")
    }

    private func handleSaveSettings(request: ParsedRequest, connection: NWConnection) {
        var dict: [String: Any] = [:]

        if let data = request.body.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            dict = json
        } else {
            // Form URL-encoded fallback
            for item in request.body.components(separatedBy: "&") {
                let kv = item.components(separatedBy: "=")
                if kv.count == 2 {
                    let key = kv[0].removingPercentEncoding ?? kv[0]
                    let value = kv[1].replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? kv[1]
                    dict[key] = value
                }
            }
        }

        DispatchQueue.main.async {
            self.applySettingsDictionary(dict)
            self.settings.saveSettings()
        }

        sendResponse(connection: connection, statusCode: 200, statusText: "OK", contentType: "application/json", body: "{\"success\":true,\"message\":\"Settings saved successfully\"}")
    }

    private func applySettingsDictionary(_ dict: [String: Any]) {
        if let mode = dict["screensaverMode"] as? String { settings.screensaverMode = mode }
        if let timeout = dict["screensaverTimeout"] {
            if let d = timeout as? Double { settings.screensaverTimeout = d }
            else if let s = timeout as? String, let d = Double(s) { settings.screensaverTimeout = d }
        }
        if let dim = dict["screenBrightnessDimmed"] {
            if let d = dim as? Double { settings.screenBrightnessDimmed = d }
            else if let s = dim as? String, let d = Double(s) { settings.screenBrightnessDimmed = d }
        }
        if let norm = dict["screenBrightnessNormal"] {
            if let d = norm as? Double { settings.screenBrightnessNormal = d }
            else if let s = norm as? String, let d = Double(s) { settings.screenBrightnessNormal = d }
            UIScreen.main.brightness = CGFloat(settings.screenBrightnessNormal)
        }
        if let user = dict["webServerUsername"] as? String {
            settings.webServerUsername = user
        }
        if let reqAuth = dict["requireDeviceAuth"] {
            if let b = reqAuth as? Bool { settings.requireDeviceAuth = b }
            else if let s = reqAuth as? String { settings.requireDeviceAuth = (s == "true" || s == "1" || s == "on") }
        }
        if let method = dict["wakeupMethod"] as? String { settings.wakeupMethod = method }
        if let sens = dict["motionSensitivity"] {
            if let d = sens as? Double { settings.motionSensitivity = d }
            else if let s = sens as? String, let d = Double(s) { settings.motionSensitivity = d }
        }
        if let interval = dict["faceDetectionInterval"] {
            if let d = interval as? Double { settings.faceDetectionInterval = d }
            else if let s = interval as? String, let d = Double(s) { settings.faceDetectionInterval = d }
        }
        if let dbg = dict["showDebugInfo"] {
            if let b = dbg as? Bool { settings.showDebugInfo = b }
            else if let s = dbg as? String { settings.showDebugInfo = (s == "true" || s == "1" || s == "on") }
        }
        if let ref = dict["enableAutoRefresh"] {
            if let b = ref as? Bool { settings.enableAutoRefresh = b }
            else if let s = ref as? String { settings.enableAutoRefresh = (s == "true" || s == "1" || s == "on") }
        }
        if let refInt = dict["autoRefreshInterval"] {
            if let d = refInt as? Double { settings.autoRefreshInterval = d }
            else if let s = refInt as? String, let d = Double(s) { settings.autoRefreshInterval = d }
        }
        if let urls = dict["slideshowURLs"] as? [String] {
            settings.slideshowURLs = urls
        } else if let urlsString = dict["slideshowURLs"] as? String {
            settings.slideshowURLs = urlsString.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        if let slideInt = dict["slideshowInterval"] {
            if let d = slideInt as? Double { settings.slideshowInterval = d }
            else if let s = slideInt as? String, let d = Double(s) { settings.slideshowInterval = d }
        }
        if let va = dict["enableVoiceActivation"] {
            if let b = va as? Bool { settings.enableVoiceActivation = b }
            else if let s = va as? String { settings.enableVoiceActivation = (s == "true" || s == "1" || s == "on") }
        }
        if let sr = dict["voiceSampleRate"] {
            if let i = sr as? Int { settings.voiceSampleRate = i }
            else if let s = sr as? String, let i = Int(s) { settings.voiceSampleRate = i }
        }
        if let vt = dict["voiceTimeout"] {
            if let i = vt as? Int { settings.voiceTimeout = i }
            else if let s = vt as? String, let i = Int(s) { settings.voiceTimeout = i }
        }
        if let pass = dict["webServerPassword"] as? String {
            settings.webServerPassword = pass
        }
        if let port = dict["webServerPort"] {
            let newPort: Int?
            if let i = port as? Int { newPort = i }
            else if let s = port as? String, let i = Int(s) { newPort = i }
            else { newPort = nil }
            if let p = newPort, p != settings.webServerPort {
                settings.webServerPort = p
            }
        }
    }

    private func sendResponse(connection: NWConnection, statusCode: Int, statusText: String, contentType: String, headers: [String: String] = [:], body: String) {
        let bodyData = body.data(using: .utf8) ?? Data()
        var headerLines = [
            "HTTP/1.1 \(statusCode) \(statusText)",
            "Content-Type: \(contentType)",
            "Content-Length: \(bodyData.count)",
            "Connection: close",
            "Access-Control-Allow-Origin: *"
        ]
        for (k, v) in headers {
            headerLines.append("\(k): \(v)")
        }
        let headerString = headerLines.joined(separator: "\r\n") + "\r\n\r\n"
        var fullData = headerString.data(using: .utf8) ?? Data()
        fullData.append(bodyData)

        connection.send(content: fullData, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - HTML Dashboard Generation

    private func generateStatusJSON() -> String {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let batteryLevel = UIDevice.current.batteryLevel >= 0 ? Int(UIDevice.current.batteryLevel * 100) : -1
        let isCharging = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full

        var dict: [String: Any] = settings.exportSettings()
        dict["battery_percent"] = batteryLevel
        dict["is_charging"] = isCharging
        dict["device_name"] = UIDevice.current.name
        dict["device_model"] = UIDevice.current.model
        dict["system_version"] = UIDevice.current.systemVersion

        if let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }

    private func generateDashboardHTML() -> String {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let battery = UIDevice.current.batteryLevel >= 0 ? "\(Int(UIDevice.current.batteryLevel * 100))%" : "Unknown"
        let isCharging = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full ? "Charging ⚡" : "Discharging"
        let urlsText = settings.slideshowURLs.joined(separator: "\n")

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>PadPanel Remote Admin</title>
            <style>
                :root {
                    --bg: #121418;
                    --card: #1c2027;
                    --border: #2e3542;
                    --text: #e6edf3;
                    --subtext: #8b949e;
                    --primary: #388bfd;
                    --primary-hover: #1f6feb;
                    --success: #238636;
                    --danger: #da3633;
                }
                * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; }
                body { background: var(--bg); color: var(--text); padding: 20px; line-height: 1.5; }
                .container { max-width: 800px; margin: 0 auto; }
                header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 24px; padding-bottom: 12px; border-bottom: 1px solid var(--border); }
                h1 { font-size: 24px; font-weight: 600; display: flex; align-items: center; gap: 8px; }
                .badge { background: #238636; color: #fff; font-size: 11px; padding: 2px 8px; border-radius: 12px; text-transform: uppercase; font-weight: bold; }
                .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 16px; margin-bottom: 24px; }
                .card { background: var(--card); border: 1px solid var(--border); border-radius: 10px; padding: 18px; }
                .card-title { font-size: 13px; text-transform: uppercase; letter-spacing: 0.5px; color: var(--subtext); margin-bottom: 8px; font-weight: 600; }
                .card-value { font-size: 20px; font-weight: bold; color: var(--text); }
                .actions { display: flex; gap: 10px; margin-bottom: 24px; flex-wrap: wrap; }
                button { background: var(--primary); color: #fff; border: none; padding: 10px 18px; border-radius: 6px; font-weight: 600; font-size: 14px; cursor: pointer; transition: 0.2s; }
                button:hover { background: var(--primary-hover); }
                button.secondary { background: #2d333b; border: 1px solid var(--border); }
                button.secondary:hover { background: #373e47; }
                button.success { background: var(--success); }
                section { background: var(--card); border: 1px solid var(--border); border-radius: 10px; padding: 20px; margin-bottom: 20px; }
                section h2 { font-size: 17px; margin-bottom: 16px; border-bottom: 1px solid var(--border); padding-bottom: 8px; }
                .form-group { margin-bottom: 16px; }
                label { display: block; font-size: 13px; font-weight: 500; margin-bottom: 6px; color: var(--text); }
                .hint { font-size: 12px; color: var(--subtext); margin-top: 4px; }
                input[type="text"], input[type="number"], input[type="password"], select, textarea {
                    width: 100%; background: #0d1117; border: 1px solid var(--border); border-radius: 6px; color: var(--text); padding: 8px 12px; font-size: 14px;
                }
                input[type="range"] { width: 100%; accent-color: var(--primary); }
                .checkbox-group { display: flex; align-items: center; gap: 8px; cursor: pointer; }
                .checkbox-group input { width: 16px; height: 16px; }
                textarea { resize: vertical; min-height: 80px; font-family: monospace; }
                #toast { display: none; position: fixed; bottom: 20px; right: 20px; background: #238636; color: #fff; padding: 12px 20px; border-radius: 6px; box-shadow: 0 4px 12px rgba(0,0,0,0.5); font-weight: 600; }
            </style>
        </head>
        <body>
            <div class="container">
                <header>
                    <h1>PadPanel <span class="badge">Online</span></h1>
                    <div style="font-size: 13px; color: var(--subtext);">\(UIDevice.current.name)</div>
                </header>

                <div class="grid">
                    <div class="card">
                        <div class="card-title">Battery</div>
                        <div class="card-value">\(battery) <span style="font-size: 13px; font-weight: normal; color: var(--subtext);">(\(isCharging))</span></div>
                    </div>
                    <div class="card">
                        <div class="card-title">Screensaver Mode</div>
                        <div class="card-value" style="text-transform: capitalize;">\(settings.screensaverMode)</div>
                    </div>
                    <div class="card">
                        <div class="card-title">Active URLs</div>
                        <div class="card-value">\(settings.effectiveURLs.count) configured</div>
                    </div>
                </div>

                <div class="actions">
                    <button class="secondary" onclick="sendAction('screensaver')">🌙 Trigger Screensaver</button>
                    <button class="secondary" onclick="sendAction('wakeup')">☀️ Wake Screen</button>
                    <button class="secondary" onclick="sendAction('reload')">🔄 Reload Browser</button>
                </div>

                <form id="settingsForm" onsubmit="saveSettings(event)">
                    <section>
                        <h2>Screensaver & Brightness</h2>
                        <div class="form-group">
                            <label>Screensaver Option</label>
                            <select name="screensaverMode">
                                <option value="clock" \(settings.screensaverMode == "clock" ? "selected" : "")>Clock & Sensors (Black screen with time & face/motion wake)</option>
                                <option value="dimming" \(settings.screensaverMode == "dimming" ? "selected" : "")>Dimming Only (Dims screen, tap/sensor restores brightness)</option>
                                <option value="urls" \(settings.screensaverMode == "urls" ? "selected" : "")>URLs Slideshow (Smoothly cycles URLs during screensaver)</option>
                                <option value="off" \(settings.screensaverMode == "off" ? "selected" : "")>Off (Disabled — no screensaver, no dimming, no camera)</option>
                            </select>
                        </div>
                        <div class="form-group">
                            <label>Inactivity Timeout (seconds)</label>
                            <input type="number" name="screensaverTimeout" value="\(Int(settings.screensaverTimeout))" min="10" max="3600">
                        </div>
                        <div class="form-group">
                            <label id="lblNormal">Screen Brightness - Normal (\(Int(settings.screenBrightnessNormal * 100))%)</label>
                            <input type="range" id="sliderNormal" name="screenBrightnessNormal" min="0.3" max="1.0" step="0.01" value="\(settings.screenBrightnessNormal)" oninput="liveUpdateBrightness('normal', this.value)">
                        </div>
                        <div class="form-group">
                            <label id="lblDimmed">Screen Brightness - Dimmed (\(Int(settings.screenBrightnessDimmed * 100))%)</label>
                            <input type="range" id="sliderDimmed" name="screenBrightnessDimmed" min="0.05" max="0.8" step="0.01" value="\(settings.screenBrightnessDimmed)" oninput="liveUpdateBrightness('dimmed', this.value)">
                        </div>
                    </section>

                    <section>
                        <h2>Device & WebUI Authentication</h2>
                        <div class="form-group">
                            <label class="checkbox-group">
                                <input type="checkbox" name="requireDeviceAuth" \(settings.requireDeviceAuth ? "checked" : "")>
                                <span>Require password to unlock on-device Settings</span>
                            </label>
                        </div>
                        <div class="form-group">
                            <label>Administrator Username</label>
                            <input type="text" name="webServerUsername" value="\(settings.webServerUsername)">
                        </div>
                        <div class="form-group">
                            <label>Administrator Password (leave blank for no password)</label>
                            <input type="password" name="webServerPassword" value="\(settings.webServerPassword)" placeholder="No password set">
                        </div>
                    </section>

                    <section>
                        <h2>Wakeup & Camera</h2>
                        <div class="form-group">
                            <label>Wakeup Method</label>
                            <select name="wakeupMethod">
                                <option value="face" \(settings.wakeupMethod == "face" ? "selected" : "")>Face Detection (Vision)</option>
                                <option value="motion" \(settings.wakeupMethod == "motion" ? "selected" : "")>Motion Detection (Camera Sensor)</option>
                            </select>
                        </div>
                        <div class="form-group">
                            <label>Motion Sensitivity (\(Int(settings.motionSensitivity * 100))% threshold)</label>
                            <input type="range" name="motionSensitivity" min="0.02" max="0.25" step="0.01" value="\(settings.motionSensitivity)">
                            <div class="hint">Lower threshold = more sensitive; higher = requires larger motion.</div>
                        </div>
                        <div class="form-group">
                            <label>Face Detection Interval (seconds)</label>
                            <input type="number" step="0.1" name="faceDetectionInterval" value="\(settings.faceDetectionInterval)" min="0.1" max="5.0">
                        </div>
                        <div class="form-group">
                            <label class="checkbox-group">
                                <input type="checkbox" name="showDebugInfo" \(settings.showDebugInfo ? "checked" : "")>
                                <span>Show camera debug info on screensaver</span>
                            </label>
                        </div>
                    </section>

                    <section>
                        <h2>Kiosk & Browser URLs</h2>
                        <div class="form-group">
                            <label>Slideshow / Kiosk URLs (one per line)</label>
                            <textarea name="slideshowURLs" rows="4">\(urlsText)</textarea>
                            <div class="hint">First URL is your primary dashboard. Additional URLs cycle in slideshow or URL screensaver mode.</div>
                        </div>
                        <div class="form-group">
                            <label>Slide Cycle Interval (seconds)</label>
                            <input type="number" name="slideshowInterval" value="\(Int(settings.slideshowInterval))" min="5" max="600">
                        </div>
                        <div class="form-group">
                            <label class="checkbox-group">
                                <input type="checkbox" name="enableAutoRefresh" \(settings.enableAutoRefresh ? "checked" : "")>
                                <span>Auto refresh page</span>
                            </label>
                        </div>
                        <div class="form-group">
                            <label>Auto Refresh Interval (seconds)</label>
                            <input type="number" name="autoRefreshInterval" value="\(Int(settings.autoRefreshInterval))" min="10" max="3600">
                        </div>
                    </section>

                    <section>
                        <h2>Remote Web Server & Password</h2>
                        <div class="form-group">
                            <label>Web Server Port</label>
                            <input type="number" name="webServerPort" value="\(settings.webServerPort)" min="1024" max="65535">
                        </div>
                        <div class="form-group">
                            <label>Web Server Password (leave blank for no password)</label>
                            <input type="password" name="webServerPassword" value="\(settings.webServerPassword)">
                        </div>
                    </section>

                    <div style="text-align: right; margin-top: 24px;">
                        <button type="submit" class="success" style="font-size: 16px; padding: 12px 28px;">💾 Save Settings</button>
                    </div>
                </form>
            </div>

            <div id="toast">Settings Saved!</div>

            <script>
                let brightnessDebounce = null;
                function liveUpdateBrightness(type, val) {
                    const num = parseFloat(val);
                    const pct = Math.round(num * 100);
                    if (type === 'normal') {
                        document.getElementById('lblNormal').innerText = 'Screen Brightness - Normal (' + pct + '%)';
                    } else {
                        document.getElementById('lblDimmed').innerText = 'Screen Brightness - Dimmed (' + pct + '%)';
                    }

                    clearTimeout(brightnessDebounce);
                    brightnessDebounce = setTimeout(async () => {
                        try {
                            const payload = {};
                            if (type === 'normal') {
                                payload['screenBrightnessNormal'] = num;
                            } else {
                                payload['screenBrightnessDimmed'] = num;
                            }
                            await fetch('/api/brightness', {
                                method: 'POST',
                                headers: { 'Content-Type': 'application/json' },
                                body: JSON.stringify(payload)
                            });
                        } catch(e) {
                            console.error('Failed to update live brightness', e);
                        }
                    }, 40);
                }

                function showToast(msg) {
                    const t = document.getElementById('toast');
                    t.innerText = msg;
                    t.style.display = 'block';
                    setTimeout(() => { t.style.display = 'none'; }, 3000);
                }

                async function sendAction(actionName) {
                    try {
                        const res = await fetch('/api/action', {
                            method: 'POST',
                            headers: { 'Content-Type': 'application/json' },
                            body: JSON.stringify({ action: actionName })
                        });
                        if (res.ok) showToast('Action sent: ' + actionName);
                    } catch (e) {
                        alert('Error sending action: ' + e);
                    }
                }

                async function saveSettings(e) {
                    e.preventDefault();
                    const form = document.getElementById('settingsForm');
                    const fd = new FormData(form);
                    const payload = {};
                    fd.forEach((val, key) => { payload[key] = val; });
                    payload['showDebugInfo'] = form.querySelector('[name=showDebugInfo]').checked;
                    payload['enableAutoRefresh'] = form.querySelector('[name=enableAutoRefresh]').checked;

                    try {
                        const res = await fetch('/api/settings', {
                            method: 'POST',
                            headers: { 'Content-Type': 'application/json' },
                            body: JSON.stringify(payload)
                        });
                        if (res.ok) {
                            showToast('Settings saved successfully!');
                        } else {
                            alert('Save failed: ' + res.statusText);
                        }
                    } catch (err) {
                        alert('Failed to save settings: ' + err);
                    }
                }
            </script>
        </body>
        </html>
        """
    }

    // MARK: - Local IP Helper
    private func getWiFiAddress() -> String? {
        #if canImport(Darwin)
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = ptr {
            defer { ptr = current.pointee.ifa_next }
            guard let ifaAddr = current.pointee.ifa_addr else { continue }
            if ifaAddr.pointee.sa_family == UInt8(AF_INET) {
                let name = String(cString: current.pointee.ifa_name)
                // Prefer en0 (standard Wi-Fi on iOS), or fallback to en1 or other non-loopback interface
                if name == "en0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(ifaAddr, socklen_t(ifaAddr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                        address = String(cString: hostname)
                        break
                    }
                } else if address == nil && name != "lo0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(ifaAddr, socklen_t(ifaAddr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                        address = String(cString: hostname)
                    }
                }
            }
        }
        freeifaddrs(firstAddr)
        return address
        #else
        return nil
        #endif
    }
}
