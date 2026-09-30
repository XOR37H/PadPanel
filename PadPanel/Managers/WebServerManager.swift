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
                        let ip = WebServerManager.getWiFiAddress() ?? "localhost"
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
        // Allow unauthenticated access to the secret-token screenshot endpoint
        let cleanPath = request.path.components(separatedBy: "?").first ?? "/"
        let token = settings.screenshotSecurityToken
        if !token.isEmpty && (cleanPath == "/\(token)/screenshot" || cleanPath == "/\(token)/screenshot.jpg" || cleanPath == "/\(token)/screenshot.jpeg") {
            return true
        }

        // If authentication is disabled or password is empty, allow access
        if !settings.requireDeviceAuth || settings.webServerPassword.isEmpty {
            return true
        }

        let expectedPassword = settings.webServerPassword
        let expectedUsername = settings.webServerUsername

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

        let token = settings.screenshotSecurityToken
        let isScreenshotPath = !token.isEmpty && (
            cleanPath == "/\(token)/screenshot" ||
            cleanPath == "/\(token)/screenshot.jpg" ||
            cleanPath == "/\(token)/screenshot.jpeg"
        )

        if request.method == "GET" && isScreenshotPath {
            handleScreenshot(connection: connection)
            return
        }

        switch (request.method, cleanPath) {
        case ("GET", "/"), ("GET", "/index.html"):
            let html = generateDashboardHTML()
            sendResponse(connection: connection, statusCode: 200, statusText: "OK", contentType: "text/html; charset=utf-8", body: html)

        case ("GET", "/api/status"):
            let json = generateStatusJSON()
            sendResponse(connection: connection, statusCode: 200, statusText: "OK", contentType: "application/json", body: json)

        case ("GET", "/api/settings/export"), ("GET", "/api/export"), ("GET", "/padpanel-settings.conf"):
            handleExportSettings(connection: connection)

        case ("POST", "/api/settings/import"), ("POST", "/api/import"):
            handleImportSettings(request: request, connection: connection)

        case ("POST", "/api/regenerate-token"):
            DispatchQueue.main.async {
                self.settings.regenerateScreenshotToken()
            }
            let newToken = settings.screenshotSecurityToken
            sendResponse(connection: connection, statusCode: 200, statusText: "OK", contentType: "application/json", body: "{\"success\":true,\"token\":\"\(newToken)\"}")

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

    private func handleScreenshot(connection: NWConnection) {
        DispatchQueue.main.async {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let window = scenes.flatMap { $0.windows }.first(where: { $0.isKeyWindow })
                ?? scenes.flatMap { $0.windows }.first
                ?? UIApplication.shared.windows.first

            guard let targetWindow = window else {
                self.sendResponse(connection: connection, statusCode: 500, statusText: "Internal Server Error", contentType: "text/plain", body: "Window not accessible")
                return
            }

            let bounds = targetWindow.bounds
            guard bounds.width > 0 && bounds.height > 0 else {
                self.sendResponse(connection: connection, statusCode: 500, statusText: "Internal Server Error", contentType: "text/plain", body: "Window bounds invalid")
                return
            }

            let format = UIGraphicsImageRendererFormat()
            format.scale = min(UIScreen.main.scale, 2.0)
            format.opaque = true

            let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)
            let image = renderer.image { _ in
                targetWindow.drawHierarchy(in: bounds, afterScreenUpdates: false)
            }

            guard let jpegData = image.jpegData(compressionQuality: 0.85) else {
                self.sendResponse(connection: connection, statusCode: 500, statusText: "Internal Server Error", contentType: "text/plain", body: "JPEG compression failed")
                return
            }

            let headers = [
                "Content-Disposition": "inline; filename=\"screenshot.jpg\"",
                "Cache-Control": "no-cache, no-store, must-revalidate",
                "Pragma": "no-cache",
                "Expires": "0"
            ]

            self.sendDataResponse(connection: connection, statusCode: 200, statusText: "OK", contentType: "image/jpeg", headers: headers, data: jpegData)
        }
    }

    private func handleExportSettings(connection: NWConnection) {
        let confContent = settings.exportConfigFileString()
        let headers = [
            "Content-Disposition": "attachment; filename=\"padpanel-settings.conf\"",
            "Cache-Control": "no-cache, no-store, must-revalidate"
        ]
        sendResponse(connection: connection, statusCode: 200, statusText: "OK", contentType: "text/plain; charset=utf-8", headers: headers, body: confContent)
    }

    private func handleImportSettings(request: ParsedRequest, connection: NWConnection) {
        var content = request.body

        // Handle JSON wrapper { "config": "..." } or raw settings JSON
        if let data = request.body.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let cfg = json["config"] as? String {
                content = cfg
            } else {
                DispatchQueue.main.async {
                    self.settings.importSettings(json)
                    self.settings.saveSettings()
                    NotificationCenter.default.post(name: .reloadAllWebViews, object: nil)
                }
                sendResponse(connection: connection, statusCode: 200, statusText: "OK", contentType: "application/json", body: "{\"success\":true,\"message\":\"Configuration imported and saved successfully\"}")
                return
            }
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            sendResponse(connection: connection, statusCode: 400, statusText: "Bad Request", contentType: "application/json", body: "{\"error\":\"Configuration file content is empty\"}")
            return
        }

        DispatchQueue.main.async {
            let success = self.settings.importConfigFileString(trimmed)
            if success {
                NotificationCenter.default.post(name: .reloadAllWebViews, object: nil)
            }
        }

        sendResponse(connection: connection, statusCode: 200, statusText: "OK", contentType: "application/json", body: "{\"success\":true,\"message\":\"padpanel-settings.conf imported and applied successfully\"}")
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
        if let main = dict["mainDashboardURL"] as? String {
            settings.mainDashboardURL = main
        }
        if let ha = dict["enableHomeAssistant"] {
            if let b = ha as? Bool { settings.enableHomeAssistant = b }
            else if let s = ha as? String { settings.enableHomeAssistant = (s == "true" || s == "1" || s == "on") }
        }
        if let haIP = dict["homeAssistantIP"] as? String { settings.homeAssistantIP = haIP }
        if let haPort = dict["homeAssistantPort"] as? String { settings.homeAssistantPort = haPort }
        if let token = dict["accessToken"] as? String { settings.accessToken = token }
        if let mode = dict["screensaverMode"] as? String { settings.screensaverMode = mode }
        if let timeout = dict["screensaverTimeout"] {
            if let d = timeout as? Double { settings.screensaverTimeout = d }
            else if let s = timeout as? String, let d = Double(s) { settings.screensaverTimeout = d }
        }
        if let dim = dict["screenBrightnessDimmed"] {
            if let d = dim as? Double { settings.screenBrightnessDimmed = d }
            else if let s = dim as? String, let d = Double(s) { settings.screenBrightnessDimmed = d }
        }
        if let eds = dict["enableDeepSleep"] {
            if let b = eds as? Bool { settings.enableDeepSleep = b }
            else if let s = eds as? String { settings.enableDeepSleep = (s == "true" || s == "1" || s == "on") }
        }
        if let dst = dict["deepSleepTimeout"] {
            if let d = dst as? Double { settings.deepSleepTimeout = d }
            else if let s = dst as? String, let d = Double(s) { settings.deepSleepTimeout = d }
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
        if let token = dict["porcupineAccessToken"] as? String {
            settings.porcupineAccessToken = token
        }
        if let mqtt = dict["enableMQTT"] {
            if let b = mqtt as? Bool { settings.enableMQTT = b }
            else if let s = mqtt as? String { settings.enableMQTT = (s == "true" || s == "1" || s == "on") }
        }
        if let broker = dict["mqttBrokerIP"] as? String { settings.mqttBrokerIP = broker }
        if let port = dict["mqttPort"] as? String { settings.mqttPort = port }
        if let user = dict["mqttUsername"] as? String { settings.mqttUsername = user }
        if let pass = dict["mqttPassword"] as? String { settings.mqttPassword = pass }
        if let prefix = dict["mqttTopicPrefix"] as? String { settings.mqttTopicPrefix = prefix }
        if let tls = dict["mqttUseTLS"] {
            if let b = tls as? Bool { settings.mqttUseTLS = b }
            else if let s = tls as? String { settings.mqttUseTLS = (s == "true" || s == "1" || s == "on") }
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

    private func sendDataResponse(connection: NWConnection, statusCode: Int, statusText: String, contentType: String, headers: [String: String] = [:], data: Data) {
        var headerLines = [
            "HTTP/1.1 \(statusCode) \(statusText)",
            "Content-Type: \(contentType)",
            "Content-Length: \(data.count)",
            "Connection: close",
            "Access-Control-Allow-Origin: *"
        ]
        for (k, v) in headers {
            headerLines.append("\(k): \(v)")
        }
        let headerString = headerLines.joined(separator: "\r\n") + "\r\n\r\n"
        var fullData = headerString.data(using: .utf8) ?? Data()
        fullData.append(data)

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
        let batteryPct = UIDevice.current.batteryLevel >= 0 ? "\(Int(UIDevice.current.batteryLevel * 100))%" : "Unknown"
        let isCharging = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full
        let chargingText = isCharging ? "Charging" : "Discharging"
        let urlsText = settings.slideshowURLs.joined(separator: "\n")
        let hostIP = WebServerManager.getWiFiAddress() ?? "localhost"
        let screenshotURL = "http://\(hostIP):\(settings.webServerPort)/\(settings.screenshotSecurityToken)/screenshot"

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>PadPanel Administration</title>
            <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Material+Symbols+Outlined:opsz,wght,FILL,GRAD@20..48,100..700,0..1,-50..200" />
            <style>
                :root {
                    --bg: #0d1117;
                    --card: #161b22;
                    --card-muted: #13171d;
                    --border: #30363d;
                    --border-focus: #58a6ff;
                    --text: #f0f6fc;
                    --subtext: #8b949e;
                    --primary: #238636;
                    --primary-hover: #2ea043;
                    --btn-secondary: #21262d;
                    --btn-secondary-hover: #30363d;
                    --accent: #58a6ff;
                }
                * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; }
                body { background: var(--bg); color: var(--text); padding: 24px 16px; line-height: 1.5; -webkit-font-smoothing: antialiased; }
                .container { max-width: 860px; margin: 0 auto; }
                
                .material-symbols-outlined {
                    font-variation-settings: 'FILL' 0, 'wght' 400, 'GRAD' 0, 'opsz' 20;
                    font-size: 18px;
                    line-height: 1;
                    vertical-align: middle;
                    display: inline-block;
                }

                header {
                    display: flex;
                    justify-content: space-between;
                    align-items: center;
                    margin-bottom: 24px;
                    padding-bottom: 16px;
                    border-bottom: 1px solid var(--border);
                }
                .brand { display: flex; align-items: center; gap: 12px; }
                .brand-title { font-size: 20px; font-weight: 600; letter-spacing: -0.2px; }
                .status-badge {
                    background: #1f3b2b;
                    color: #3fb950;
                    border: 1px solid #238636;
                    font-size: 11px;
                    padding: 2px 8px;
                    border-radius: 12px;
                    font-weight: 600;
                    text-transform: uppercase;
                    letter-spacing: 0.5px;
                }
                .device-info { font-size: 13px; color: var(--subtext); }

                .grid {
                    display: grid;
                    grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
                    gap: 12px;
                    margin-bottom: 24px;
                }
                .stat-card {
                    background: var(--card);
                    border: 1px solid var(--border);
                    border-radius: 8px;
                    padding: 14px 16px;
                }
                .stat-title {
                    font-size: 12px;
                    font-weight: 500;
                    color: var(--subtext);
                    text-transform: uppercase;
                    letter-spacing: 0.5px;
                    margin-bottom: 6px;
                    display: flex;
                    align-items: center;
                    gap: 6px;
                }
                .stat-value {
                    font-size: 18px;
                    font-weight: 600;
                    color: var(--text);
                }

                .actions {
                    display: flex;
                    gap: 10px;
                    margin-bottom: 24px;
                    flex-wrap: wrap;
                }

                button, .btn {
                    background: var(--primary);
                    color: #fff;
                    border: 1px solid transparent;
                    padding: 8px 16px;
                    border-radius: 6px;
                    font-weight: 500;
                    font-size: 13px;
                    cursor: pointer;
                    display: inline-flex;
                    align-items: center;
                    justify-content: center;
                    gap: 6px;
                    text-decoration: none;
                    transition: background 0.15s ease, border-color 0.15s ease;
                }
                button:hover, .btn:hover { background: var(--primary-hover); }

                button.secondary, .btn.secondary {
                    background: var(--btn-secondary);
                    color: var(--text);
                    border: 1px solid var(--border);
                }
                button.secondary:hover, .btn.secondary:hover {
                    background: var(--btn-secondary-hover);
                    border-color: #8b949e;
                }

                .card-section {
                    background: var(--card);
                    border: 1px solid var(--border);
                    border-radius: 8px;
                    padding: 20px 22px;
                    margin-bottom: 20px;
                }
                .section-header {
                    display: flex;
                    justify-content: space-between;
                    align-items: center;
                    margin-bottom: 16px;
                    padding-bottom: 10px;
                    border-bottom: 1px solid var(--border);
                }
                .section-title {
                    font-size: 15px;
                    font-weight: 600;
                    color: var(--text);
                    display: flex;
                    align-items: center;
                    gap: 8px;
                }

                .form-group { margin-bottom: 16px; }
                .form-group:last-child { margin-bottom: 0; }
                .form-row {
                    display: grid;
                    grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
                    gap: 14px;
                    margin-bottom: 16px;
                }
                
                label {
                    display: block;
                    font-size: 13px;
                    font-weight: 500;
                    margin-bottom: 6px;
                    color: var(--text);
                }
                .hint {
                    font-size: 12px;
                    color: var(--subtext);
                    margin-top: 4px;
                }

                input[type="text"],
                input[type="number"],
                input[type="password"],
                select,
                textarea {
                    width: 100%;
                    background: #090d13;
                    border: 1px solid var(--border);
                    border-radius: 6px;
                    color: var(--text);
                    padding: 8px 12px;
                    font-size: 13px;
                    font-family: inherit;
                    transition: border-color 0.15s ease;
                }
                input[type="text"]:focus,
                input[type="number"]:focus,
                input[type="password"]:focus,
                select:focus,
                textarea:focus {
                    outline: none;
                    border-color: var(--border-focus);
                }
                input[type="range"] {
                    width: 100%;
                    accent-color: var(--accent);
                }
                
                .checkbox-group {
                    display: flex;
                    align-items: center;
                    gap: 8px;
                    cursor: pointer;
                    user-select: none;
                }
                .checkbox-group input[type="checkbox"] {
                    width: 16px;
                    height: 16px;
                    accent-color: var(--primary);
                    cursor: pointer;
                }
                
                textarea {
                    resize: vertical;
                    min-height: 70px;
                    font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
                    font-size: 12px;
                }

                .input-with-button {
                    display: flex;
                    gap: 8px;
                    align-items: center;
                    flex-wrap: wrap;
                }
                .code-input {
                    font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace !important;
                    color: var(--accent) !important;
                }

                .save-bar {
                    display: flex;
                    justify-content: flex-end;
                    padding-top: 8px;
                    margin-top: 12px;
                }

                #toast {
                    display: none;
                    position: fixed;
                    bottom: 24px;
                    right: 24px;
                    background: #1f3b2b;
                    color: #3fb950;
                    border: 1px solid #238636;
                    padding: 12px 20px;
                    border-radius: 6px;
                    box-shadow: 0 8px 24px rgba(0,0,0,0.6);
                    font-weight: 500;
                    font-size: 13px;
                    z-index: 1000;
                    display: flex;
                    align-items: center;
                    gap: 8px;
                }
            </style>
        </head>
        <body>
            <div class="container">
                <header>
                    <div class="brand">
                        <span class="brand-title">PadPanel</span>
                        <span class="status-badge">Connected</span>
                    </div>
                    <div class="device-info">\(UIDevice.current.name) &bull; \(hostIP):\(settings.webServerPort)</div>
                </header>

                <div class="grid">
                    <div class="stat-card">
                        <div class="stat-title"><span class="material-symbols-outlined">battery_std</span> Battery</div>
                        <div class="stat-value">\(batteryPct) <span style="font-size: 12px; font-weight: normal; color: var(--subtext);">(\(chargingText))</span></div>
                    </div>
                    <div class="stat-card">
                        <div class="stat-title"><span class="material-symbols-outlined">screen_lock_portrait</span> Screensaver</div>
                        <div class="stat-value" style="text-transform: capitalize;">\(settings.screensaverMode)</div>
                    </div>
                    <div class="stat-card">
                        <div class="stat-title"><span class="material-symbols-outlined">tab</span> Active URLs</div>
                        <div class="stat-value">\(settings.effectiveURLs.count) configured</div>
                    </div>
                </div>

                <div class="actions">
                    <button type="button" class="secondary" onclick="sendAction('screensaver')">
                        <span class="material-symbols-outlined">bedtime</span> Trigger Screensaver
                    </button>
                    <button type="button" class="secondary" onclick="sendAction('wakeup')">
                        <span class="material-symbols-outlined">light_mode</span> Wake Screen
                    </button>
                    <button type="button" class="secondary" onclick="sendAction('reload')">
                        <span class="material-symbols-outlined">refresh</span> Reload WebViews
                    </button>
                </div>

                <div class="card-section">
                    <div class="section-header">
                        <div class="section-title">
                            <span class="material-symbols-outlined">photo_camera</span> Screenshot Endpoint
                        </div>
                        <button type="button" class="secondary" onclick="regenerateToken()" style="font-size: 12px; padding: 4px 10px;">
                            <span class="material-symbols-outlined" style="font-size: 15px;">autorenew</span> Regenerate Token
                        </button>
                    </div>
                    <p class="hint" style="margin-bottom: 12px;">
                        Direct JPEG screenshot endpoint for Home Assistant Generic Camera entities or dashboard snapshots. Request is authenticated by the unique secret token in the URL.
                    </p>
                    <div class="input-with-button">
                        <input type="text" id="screenshotUrlInput" class="code-input" value="\(screenshotURL)" readonly style="flex: 1; min-width: 260px; cursor: pointer;" onclick="this.select()">
                        <button type="button" class="secondary" onclick="copyScreenshotUrl()">
                            <span class="material-symbols-outlined">content_copy</span> Copy URL
                        </button>
                        <a href="\(screenshotURL)" target="_blank" class="btn secondary">
                            <span class="material-symbols-outlined">open_in_new</span> View Snapshot
                        </a>
                    </div>
                </div>

                <div class="card-section">
                    <div class="section-header">
                        <div class="section-title">
                            <span class="material-symbols-outlined">settings_backup_restore</span> Backup & Restore
                        </div>
                        <a href="/api/settings/export" download="padpanel-settings.conf" class="btn secondary" style="font-size: 12px; padding: 4px 12px;">
                            <span class="material-symbols-outlined" style="font-size: 15px;">download</span> Download padpanel-settings.conf
                        </a>
                    </div>
                    <p class="hint" style="margin-bottom: 12px;">
                        Download your configuration as a plain-text <code>padpanel-settings.conf</code> file, or upload a previously saved file to restore all settings.
                    </p>
                    <div class="input-with-button">
                        <input type="file" id="configFileUpload" accept=".conf,.txt,.json" style="max-width: 340px; font-size: 12px; padding: 6px;">
                        <button type="button" class="secondary" onclick="importConfigFile()">
                            <span class="material-symbols-outlined">upload</span> Restore & Apply
                        </button>
                    </div>
                </div>

                <form id="settingsForm" onsubmit="saveSettings(event)">
                    <div class="card-section">
                        <div class="section-header">
                            <div class="section-title">
                                <span class="material-symbols-outlined">dashboard</span> Main Dashboard & Refresh
                            </div>
                        </div>
                        <div class="form-group">
                            <label>Main Dashboard URL</label>
                            <input type="text" name="mainDashboardURL" class="code-input" value="\(settings.mainDashboardURL)" placeholder="http://homeassistant.local:8123/...">
                            <div class="hint">Primary full-screen dashboard shown when the iPad is awake.</div>
                        </div>
                        <div class="form-group" style="margin-top: 14px;">
                            <label class="checkbox-group">
                                <input type="checkbox" name="enableAutoRefresh" \(settings.enableAutoRefresh ? "checked" : "")>
                                <span>Auto refresh dashboard page</span>
                            </label>
                        </div>
                        <div class="form-group">
                            <label>Auto Refresh Interval (seconds)</label>
                            <input type="number" name="autoRefreshInterval" value="\(Int(settings.autoRefreshInterval))" min="10" max="3600">
                        </div>
                    </div>

                    <div class="card-section">
                        <div class="section-header">
                            <div class="section-title">
                                <span class="material-symbols-outlined">brightness_medium</span> Screensaver & Display
                            </div>
                        </div>
                        <div class="form-group">
                            <label>Screensaver Option</label>
                            <select name="screensaverMode">
                                <option value="clock" \(settings.screensaverMode == "clock" ? "selected" : "")>Clock & Sensors (Black screen with time & face/motion wake)</option>
                                <option value="dimming" \(settings.screensaverMode == "dimming" ? "selected" : "")>Dimming Only (Dims screen, tap/sensor restores brightness)</option>
                                <option value="urls" \(settings.screensaverMode == "urls" ? "selected" : "")>URLs Slideshow (Smoothly cycles URLs during screensaver)</option>
                                <option value="off" \(settings.screensaverMode == "off" ? "selected" : "")>Off (Disabled — no screensaver, no dimming)</option>
                            </select>
                        </div>
                        <div class="form-group">
                            <label>Inactivity Timeout (seconds)</label>
                            <input type="number" name="screensaverTimeout" value="\(Int(settings.screensaverTimeout))" min="10" max="3600">
                        </div>
                        <div class="form-row">
                            <div class="form-group">
                                <label id="lblNormal">Normal Brightness (\(Int(settings.screenBrightnessNormal * 100))%)</label>
                                <input type="range" id="sliderNormal" name="screenBrightnessNormal" min="0.3" max="1.0" step="0.01" value="\(settings.screenBrightnessNormal)" oninput="liveUpdateBrightness('normal', this.value)">
                            </div>
                            <div class="form-group">
                                <label id="lblDimmed">Dimmed Brightness (\(Int(settings.screenBrightnessDimmed * 100))%)</label>
                                <input type="range" id="sliderDimmed" name="screenBrightnessDimmed" min="0.05" max="0.8" step="0.01" value="\(settings.screenBrightnessDimmed)" oninput="liveUpdateBrightness('dimmed', this.value)">
                            </div>
                        </div>
                    </div>

                    <div class="card-section">
                        <div class="section-header">
                            <div class="section-title">
                                <span class="material-symbols-outlined">bedtime</span> Deep Sleep (Power Saving)
                            </div>
                        </div>
                        <div class="form-group">
                            <label class="checkbox-group">
                                <input type="checkbox" name="enableDeepSleep" \(settings.enableDeepSleep ? "checked" : "")>
                                <span>Enable Deep Sleep</span>
                            </label>
                            <div class="hint">Completely turns off the camera sensor, blacks out the screen to minimum brightness, and halts background rendering after extended inactivity to maximize battery life. Tap the screen to wake instantly.</div>
                        </div>
                        <div class="form-group" style="margin-top: 14px;">
                            <label>No Activity Timeout (seconds: 1800s = 30m, 3600s = 1h, 14400s = 4h)</label>
                            <input type="number" name="deepSleepTimeout" value="\(Int(settings.deepSleepTimeout))" min="1800" max="14400" step="300">
                        </div>
                    </div>

                    <div class="card-section">
                        <div class="section-header">
                            <div class="section-title">
                                <span class="material-symbols-outlined">videocam</span> Wakeup & Camera Detection
                            </div>
                        </div>
                        <div class="form-group">
                            <label>Wakeup Method</label>
                            <select name="wakeupMethod">
                                <option value="face" \(settings.wakeupMethod == "face" ? "selected" : "")>Face Detection (Vision)</option>
                                <option value="motion" \(settings.wakeupMethod == "motion" ? "selected" : "")>Motion Detection (Camera Sensor)</option>
                            </select>
                        </div>
                        <div class="form-row">
                            <div class="form-group">
                                <label>Motion Sensitivity (\(Int(settings.motionSensitivity * 100))% threshold)</label>
                                <input type="range" name="motionSensitivity" min="0.02" max="0.25" step="0.01" value="\(settings.motionSensitivity)">
                            </div>
                            <div class="form-group">
                                <label>Face Detection Interval (seconds)</label>
                                <input type="number" step="0.1" name="faceDetectionInterval" value="\(settings.faceDetectionInterval)" min="0.1" max="5.0">
                            </div>
                        </div>
                        <div class="form-group">
                            <label class="checkbox-group">
                                <input type="checkbox" name="showDebugInfo" \(settings.showDebugInfo ? "checked" : "")>
                                <span>Show camera debug info on screensaver</span>
                            </label>
                        </div>
                    </div>

                    <div class="card-section">
                        <div class="section-header">
                            <div class="section-title">
                                <span class="material-symbols-outlined">auto_stories</span> Slideshow URLs
                            </div>
                        </div>
                        <div class="form-group">
                            <label>Slideshow URLs (one per line)</label>
                            <textarea name="slideshowURLs" rows="4">\(urlsText)</textarea>
                            <div class="hint">Secondary URLs cycled during slideshow screensaver mode.</div>
                        </div>
                        <div class="form-group">
                            <label>Slideshow Cycle Interval (seconds)</label>
                            <input type="number" name="slideshowInterval" value="\(Int(settings.slideshowInterval))" min="5" max="600">
                        </div>
                    </div>

                    <div class="card-section">
                        <div class="section-header">
                            <div class="section-title">
                                <span class="material-symbols-outlined">security</span> Device & WebUI Authentication
                            </div>
                        </div>
                        <div class="form-group">
                            <label class="checkbox-group">
                                <input type="checkbox" name="requireDeviceAuth" \(settings.requireDeviceAuth ? "checked" : "")>
                                <span>Require Authentication for Settings & WebUI</span>
                            </label>
                            <div class="hint">When enabled, the administrator credentials below protect on-device Kiosk Settings and HTTP access to this Remote WebUI.</div>
                        </div>
                        <div class="form-row" style="margin-top: 14px;">
                            <div class="form-group">
                                <label>Administrator Username</label>
                                <input type="text" name="webServerUsername" value="\(settings.webServerUsername)">
                            </div>
                            <div class="form-group">
                                <label>Administrator Password</label>
                                <input type="password" name="webServerPassword" value="\(settings.webServerPassword)" placeholder="Enter password">
                            </div>
                        </div>
                    </div>

                    <div class="card-section">
                        <div class="section-header">
                            <div class="section-title">
                                <span class="material-symbols-outlined">lan</span> Remote Web UI
                            </div>
                        </div>
                        <div class="form-group">
                            <label class="checkbox-group">
                                <input type="checkbox" name="enableWebServer" \(settings.enableWebServer ? "checked" : "")>
                                <span>Enable Remote Web UI Server</span>
                            </label>
                        </div>
                        <div class="form-group">
                            <label>Web Server Port</label>
                            <input type="number" name="webServerPort" value="\(settings.webServerPort)" min="1024" max="65535">
                            <div class="hint">Default port is 8080. Accessible at <code>http://\(hostIP):\(settings.webServerPort)</code></div>
                        </div>
                    </div>

                    <div class="card-section">
                        <div class="section-header">
                            <div class="section-title">
                                <span class="material-symbols-outlined">home</span> Home Assistant Integration
                            </div>
                        </div>
                        <div class="form-group">
                            <label class="checkbox-group">
                                <input type="checkbox" name="enableHomeAssistant" \(settings.enableHomeAssistant ? "checked" : "")>
                                <span>Enable Home Assistant API integration</span>
                            </label>
                        </div>
                        <div class="form-row">
                            <div class="form-group">
                                <label>Home Assistant Host / IP</label>
                                <input type="text" name="homeAssistantIP" value="\(settings.homeAssistantIP)" placeholder="homeassistant.local">
                            </div>
                            <div class="form-group">
                                <label>Port</label>
                                <input type="text" name="homeAssistantPort" value="\(settings.homeAssistantPort)" placeholder="8123">
                            </div>
                        </div>
                        <div class="form-group">
                            <label>Long-Lived Access Token</label>
                            <input type="password" name="accessToken" class="code-input" value="\(settings.accessToken)" placeholder="Bearer token">
                        </div>
                        <div class="form-group">
                            <label class="checkbox-group">
                                <input type="checkbox" name="useHTTPS" \(settings.useHTTPS ? "checked" : "")>
                                <span>Use HTTPS / WSS</span>
                            </label>
                        </div>
                    </div>

                    <div class="card-section">
                        <div class="section-header">
                            <div class="section-title">
                                <span class="material-symbols-outlined">sensors</span> MQTT Integration
                            </div>
                        </div>
                        <div class="form-group">
                            <label class="checkbox-group">
                                <input type="checkbox" name="enableMQTT" \(settings.enableMQTT ? "checked" : "")>
                                <span>Enable MQTT broker connection</span>
                            </label>
                        </div>
                        <div class="form-row">
                            <div class="form-group">
                                <label>Broker Host / IP</label>
                                <input type="text" name="mqttBrokerIP" value="\(settings.mqttBrokerIP)" placeholder="192.168.1.100">
                            </div>
                            <div class="form-group">
                                <label>Port</label>
                                <input type="text" name="mqttPort" value="\(settings.mqttPort)" placeholder="1883">
                            </div>
                        </div>
                        <div class="form-row">
                            <div class="form-group">
                                <label>Username (optional)</label>
                                <input type="text" name="mqttUsername" value="\(settings.mqttUsername)">
                            </div>
                            <div class="form-group">
                                <label>Password (optional)</label>
                                <input type="password" name="mqttPassword" value="\(settings.mqttPassword)">
                            </div>
                        </div>
                        <div class="form-row">
                            <div class="form-group">
                                <label>Topic Prefix</label>
                                <input type="text" name="mqttTopicPrefix" value="\(settings.mqttTopicPrefix)" placeholder="homeassistant">
                            </div>
                            <div class="form-group">
                                <label>Battery Report Interval (seconds)</label>
                                <input type="number" name="mqttBatteryUpdateInterval" value="\(Int(settings.mqttBatteryUpdateInterval))" min="10" max="3600">
                            </div>
                        </div>
                        <div class="form-group">
                            <label class="checkbox-group">
                                <input type="checkbox" name="mqttUseTLS" \(settings.mqttUseTLS ? "checked" : "")>
                                <span>Use TLS/SSL connection</span>
                            </label>
                        </div>
                    </div>

                    <div class="save-bar">
                        <button type="submit" style="font-size: 14px; padding: 10px 24px;">
                            <span class="material-symbols-outlined">save</span> Save Changes
                        </button>
                    </div>
                </form>
            </div>

            <div id="toast" style="display:none;">
                <span class="material-symbols-outlined">check_circle</span>
                <span id="toastMessage">Settings saved successfully</span>
            </div>

            <script>
                let brightnessDebounce = null;
                function liveUpdateBrightness(type, val) {
                    const num = parseFloat(val);
                    const pct = Math.round(num * 100);
                    if (type === 'normal') {
                        document.getElementById('lblNormal').innerText = 'Normal Brightness (' + pct + '%)';
                    } else {
                        document.getElementById('lblDimmed').innerText = 'Dimmed Brightness (' + pct + '%)';
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
                            console.error('Failed to update brightness', e);
                        }
                    }, 40);
                }

                function showToast(msg) {
                    const t = document.getElementById('toast');
                    const msgEl = document.getElementById('toastMessage');
                    if (msgEl) msgEl.innerText = msg;
                    t.style.display = 'flex';
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

                function copyScreenshotUrl() {
                    const input = document.getElementById('screenshotUrlInput');
                    input.select();
                    if (navigator.clipboard && navigator.clipboard.writeText) {
                        navigator.clipboard.writeText(input.value).then(() => {
                            showToast('Screenshot URL copied to clipboard');
                        }).catch(() => {
                            document.execCommand('copy');
                            showToast('Screenshot URL copied');
                        });
                    } else {
                        document.execCommand('copy');
                        showToast('Screenshot URL copied');
                    }
                }

                async function regenerateToken() {
                    if (!confirm('Regenerate screenshot secret token?\\nAny external links or Home Assistant camera configurations using the old URL will need to be updated.')) return;
                    try {
                        const res = await fetch('/api/regenerate-token', { method: 'POST' });
                        if (res.ok) {
                            showToast('Secret token regenerated');
                            setTimeout(() => { window.location.reload(); }, 600);
                        } else {
                            alert('Failed to regenerate token');
                        }
                    } catch (e) {
                        alert('Error regenerating token: ' + e);
                    }
                }

                async function importConfigFile() {
                    const input = document.getElementById('configFileUpload');
                    if (!input.files || input.files.length === 0) {
                        alert('Please select a padpanel-settings.conf file first.');
                        return;
                    }
                    const file = input.files[0];
                    const reader = new FileReader();
                    reader.onload = async function(e) {
                        const content = e.target.result;
                        try {
                            const res = await fetch('/api/settings/import', {
                                method: 'POST',
                                headers: { 'Content-Type': 'text/plain; charset=utf-8' },
                                body: content
                            });
                            if (res.ok) {
                                showToast('Configuration imported successfully');
                                setTimeout(() => { window.location.reload(); }, 1000);
                            } else {
                                const err = await res.text();
                                alert('Import failed: ' + err);
                            }
                        } catch (err) {
                            alert('Network error while importing configuration: ' + err);
                        }
                    };
                    reader.readAsText(file);
                }

                async function saveSettings(e) {
                    e.preventDefault();
                    const form = document.getElementById('settingsForm');
                    const fd = new FormData(form);
                    const payload = {};
                    fd.forEach((val, key) => { payload[key] = val; });
                    
                    // Boolean checkboxes
                    const checkboxes = [
                        'showDebugInfo', 'enableAutoRefresh', 'requireDeviceAuth', 'enableWebServer',
                        'enableHomeAssistant', 'useHTTPS', 'enableMQTT', 'mqttUseTLS'
                    ];
                    checkboxes.forEach(name => {
                        const el = form.querySelector('[name=' + name + ']');
                        if (el) payload[name] = el.checked;
                    });

                    try {
                        const res = await fetch('/api/settings', {
                            method: 'POST',
                            headers: { 'Content-Type': 'application/json' },
                            body: JSON.stringify(payload)
                        });
                        if (res.ok) {
                            showToast('Settings saved successfully');
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
    static func getWiFiAddress() -> String? {
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
