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
    private var activeSessions = Set<String>()

    func clearAllSessions() {
        queue.async {
            self.activeSessions.removeAll()
            AppLogger.app.info("All WebUI active sessions invalidated")
        }
    }

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

        // 1. Check session cookie: padpanel_session=<token>
        if let cookieHeader = request.headers["cookie"] {
            for cookie in cookieHeader.components(separatedBy: ";") {
                let parts = cookie.trimmingCharacters(in: .whitespaces).components(separatedBy: "=")
                if parts.count >= 2 && parts[0] == "padpanel_session" {
                    let sessionVal = parts[1]
                    if activeSessions.contains(sessionVal) {
                        return true
                    }
                }
            }
        }

        let expectedPassword = settings.webServerPassword
        let expectedUsername = settings.webServerUsername

        // 2. Check query param e.g. /?password=xyz or /api/status?password=xyz&username=admin
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

        // 3. Check Authorization: Basic base64(user:password) for API/automation compatibility
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

        // 4. Check custom header
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

        // Handle Logout
        if cleanPath == "/logout" || cleanPath == "/api/logout" {
            handleLogout(request: request, connection: connection)
            return
        }

        // Handle Login Submission
        if cleanPath == "/login" && request.method == "POST" {
            handleLoginSubmit(request: request, connection: connection)
            return
        }

        // Handle Login Page GET
        if cleanPath == "/login" && request.method == "GET" {
            if checkAuthentication(request: request) {
                sendRedirect(connection: connection, location: "/")
            } else {
                let html = generateLoginHTML()
                sendResponse(connection: connection, statusCode: 200, statusText: "OK", contentType: "text/html; charset=utf-8", body: html)
            }
            return
        }

        // Authenticate request
        if !checkAuthentication(request: request) {
            // For API endpoints, return 401 JSON without WWW-Authenticate Basic header
            if cleanPath.hasPrefix("/api/") || cleanPath == "/padpanel-settings.conf" {
                sendResponse(connection: connection, statusCode: 401, statusText: "Unauthorized", contentType: "application/json", body: "{\"error\":\"Authentication required\",\"authenticated\":false}")
                return
            }
            // For browser web pages, redirect to the Web Login Portal
            sendRedirect(connection: connection, location: "/login")
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

    private func handleLoginSubmit(request: ParsedRequest, connection: NWConnection) {
        var user = ""
        var pass = ""

        if let data = request.body.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let u = json["username"] as? String { user = u }
            if let p = json["password"] as? String { pass = p }
        } else {
            let form = parseFormData(request.body)
            user = form["username"] ?? ""
            pass = form["password"] ?? ""
        }

        let expectedPassword = settings.webServerPassword
        let expectedUsername = settings.webServerUsername.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let inputUser = user.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let isUserValid = expectedUsername.isEmpty || inputUser == expectedUsername || (expectedUsername == "admin" && inputUser.isEmpty)
        let isPassValid = pass == expectedPassword

        if isUserValid && isPassValid {
            let sessionToken = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            self.activeSessions.insert(sessionToken)
            let cookieHeader = "padpanel_session=\(sessionToken); Path=/; HttpOnly; SameSite=Lax; Max-Age=2592000"
            let headers = [
                "Set-Cookie": cookieHeader,
                "Location": "/"
            ]
            sendResponse(connection: connection, statusCode: 302, statusText: "Found", contentType: "text/plain", headers: headers, body: "Redirecting...")
        } else {
            let html = generateLoginHTML(errorMessage: "Invalid username or password. Please try again.")
            sendResponse(connection: connection, statusCode: 401, statusText: "Unauthorized", contentType: "text/html; charset=utf-8", body: html)
        }
    }

    private func handleLogout(request: ParsedRequest, connection: NWConnection) {
        if let cookieHeader = request.headers["cookie"] {
            for cookie in cookieHeader.components(separatedBy: ";") {
                let parts = cookie.trimmingCharacters(in: .whitespaces).components(separatedBy: "=")
                if parts.count >= 2 && parts[0] == "padpanel_session" {
                    let sessionVal = parts[1]
                    self.activeSessions.remove(sessionVal)
                }
            }
        }
        let headers = [
            "Set-Cookie": "padpanel_session=; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Max-Age=0",
            "Location": "/login"
        ]
        sendResponse(connection: connection, statusCode: 302, statusText: "Found", contentType: "text/plain", headers: headers, body: "Logged out")
    }

    private func sendRedirect(connection: NWConnection, location: String) {
        let headers = ["Location": location]
        sendResponse(connection: connection, statusCode: 302, statusText: "Found", contentType: "text/plain", headers: headers, body: "Redirecting to \(location)...")
    }

    private func parseFormData(_ body: String) -> [String: String] {
        var params: [String: String] = [:]
        for item in body.components(separatedBy: "&") {
            let kv = item.components(separatedBy: "=")
            if kv.count >= 2 {
                let key = kv[0].removingPercentEncoding ?? kv[0]
                let value = kv[1].replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? kv[1]
                params[key] = value
            }
        }
        return params
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
        let logoutButtonHTML = (settings.requireDeviceAuth && !settings.webServerPassword.isEmpty) ?
            """
            <a href="/logout" class="btn secondary" style="padding: 5px 12px; font-size: 12px; text-decoration: none;">
                <span class="material-symbols-outlined">logout</span> Log Out
            </a>
            """ : ""

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
                    <div style="display: flex; align-items: center; gap: 10px; flex-wrap: wrap;">
                        <div class="device-info">\(UIDevice.current.name) &bull; \(hostIP):\(settings.webServerPort)</div>
                        \(logoutButtonHTML)
                        <button type="button" class="btn secondary" style="padding: 5px 12px; font-size: 12px;" onclick="closeKioskSettings()">
                            <span class="material-symbols-outlined">close</span> Close
                        </button>
                    </div>
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

                function closeKioskSettings() {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.padpanel) {
                        window.webkit.messageHandlers.padpanel.postMessage('closeSettings');
                    } else {
                        window.close();
                    }
                }
            </script>
        </body>
        </html>
        """
    }

    // MARK: - HTML Login Portal Generation
    private func generateLoginHTML(errorMessage: String? = nil) -> String {
        let errorHTML: String
        if let err = errorMessage {
            errorHTML = """
            <div class="error-banner">
                <span class="material-symbols-outlined">error</span>
                <span>\(err)</span>
            </div>
            """
        } else {
            errorHTML = ""
        }

        let defaultUser = settings.webServerUsername.isEmpty ? "admin" : settings.webServerUsername

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <title>PadPanel Login</title>
            <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Material+Symbols+Outlined:opsz,wght,FILL,GRAD@20..48,100..700,0..1,-50..200" />
            <style>
                :root {
                    --bg: #090c10;
                    --card-bg: rgba(22, 27, 34, 0.95);
                    --border: rgba(255, 255, 255, 0.12);
                    --text: #f0f6fc;
                    --subtext: #8b949e;
                    --primary: #238636;
                    --primary-hover: #2ea043;
                    --error-bg: rgba(218, 54, 51, 0.15);
                    --error-border: #da3633;
                    --error-text: #f85149;
                }
                * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; }
                body {
                    background: var(--bg);
                    background-image: radial-gradient(circle at 50% 25%, #161d27 0%, #090c10 80%);
                    color: var(--text);
                    min-height: 100vh;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    padding: 20px;
                    -webkit-font-smoothing: antialiased;
                }
                .login-card {
                    width: 100%;
                    max-width: 390px;
                    background: var(--card-bg);
                    border: 1.5px solid var(--border);
                    border-radius: 24px;
                    padding: 36px 30px;
                    box-shadow: 0 24px 60px rgba(0, 0, 0, 0.6);
                    backdrop-filter: blur(16px);
                    -webkit-backdrop-filter: blur(16px);
                }
                .logo-wrapper {
                    display: flex;
                    justify-content: center;
                    margin-bottom: 20px;
                }
                .logo-box {
                    width: 100px;
                    height: 65px;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    filter: drop-shadow(0 4px 12px rgba(0, 0, 0, 0.5));
                }
                .logo-box svg {
                    width: 100%;
                    height: 100%;
                }
                .title {
                    text-align: center;
                    font-size: 22px;
                    font-weight: 700;
                    letter-spacing: -0.3px;
                    margin-bottom: 4px;
                }
                .subtitle {
                    text-align: center;
                    font-size: 13px;
                    color: var(--subtext);
                    margin-bottom: 24px;
                }
                .error-banner {
                    background: var(--error-bg);
                    border: 1px solid var(--error-border);
                    color: var(--error-text);
                    padding: 10px 14px;
                    border-radius: 8px;
                    font-size: 13px;
                    margin-bottom: 20px;
                    display: flex;
                    align-items: center;
                    gap: 8px;
                }
                .material-symbols-outlined {
                    font-variation-settings: 'FILL' 0, 'wght' 400, 'GRAD' 0, 'opsz' 20;
                    font-size: 18px;
                    line-height: 1;
                }
                .form-group {
                    margin-bottom: 18px;
                }
                label {
                    display: block;
                    font-size: 13px;
                    font-weight: 500;
                    color: var(--text);
                    margin-bottom: 8px;
                }
                input[type="text"],
                input[type="password"] {
                    width: 100%;
                    background: #0d1117;
                    border: 1px solid var(--border);
                    border-radius: 8px;
                    color: var(--text);
                    padding: 10px 14px;
                    font-size: 14px;
                    font-family: inherit;
                    transition: border-color 0.15s ease, box-shadow 0.15s ease;
                }
                input[type="text"]:focus,
                input[type="password"]:focus {
                    outline: none;
                    border-color: #58a6ff;
                    box-shadow: 0 0 0 3px rgba(88, 166, 255, 0.2);
                }
                .btn {
                    width: 100%;
                    background: var(--primary);
                    color: #fff;
                    border: none;
                    padding: 11px 16px;
                    border-radius: 8px;
                    font-weight: 600;
                    font-size: 14px;
                    cursor: pointer;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    gap: 8px;
                    margin-top: 24px;
                    transition: background 0.15s ease;
                }
                .btn:hover { background: var(--primary-hover); }
                .footer {
                    margin-top: 24px;
                    text-align: center;
                    font-size: 12px;
                    color: var(--subtext);
                }
            </style>
        </head>
        <body>
            <div class="login-card">
                <div class="logo-wrapper">
                    <div class="logo-box">
                        <svg viewBox="0 0 104.56332 63.0821" version="1.1" xmlns="http://www.w3.org/2000/svg">
                          <g transform="translate(-51.942993,-85.074217)">
                            <path fill="#FFFFFF" d="m 51.942998,147.99764 c 0,-0.20164 1.102126,-4.76156 3.041504,-12.58389 l 0.4828,-1.94733 h 5.201682 c 5.548592,0 5.670443,0.008 6.551814,0.42485 1.887841,0.8931 2.316401,2.84033 1.307594,5.94127 -0.438533,1.34799 -1.753671,2.73592 -3.117567,3.29012 -1.040496,0.4228 -1.654903,0.48252 -5.077469,0.49353 l -3.176663,0.0102 -0.105707,0.21166 c -0.05814,0.11642 -0.204557,0.64982 -0.325374,1.18534 -0.120817,0.53551 -0.338944,1.45944 -0.484727,2.05316 l -0.265061,1.0795 h -2.016413 c -1.913781,0 -2.016413,-0.008 -2.016413,-0.15844 z m 11.90175,-8.01453 c 0.557501,-0.28528 0.809123,-0.63637 1.017785,-1.42011 0.233598,-0.8774 0.120547,-1.39793 -0.352349,-1.62233 -0.238239,-0.11306 -0.681508,-0.12901 -3.054303,-0.10992 l -2.775619,0.0223 -0.392471,1.67089 c -0.215859,0.91898 -0.370479,1.69287 -0.343599,1.71975 0.02688,0.0269 1.252658,0.037 2.723951,0.0224 l 2.67508,-0.0264 z m 5.178436,8.08085 c -0.831964,-0.19601 -1.384063,-0.71978 -1.629353,-1.54577 -0.164939,-0.5554 -0.157806,-0.94969 0.03399,-1.87897 0.34037,-1.64914 1.255291,-2.783 2.613522,-3.23894 0.330855,-0.11106 1.018268,-0.14301 3.914988,-0.18195 l 3.513667,-0.0473 v -0.42083 c 0,-0.36389 -0.02864,-0.43532 -0.211667,-0.52792 -0.160938,-0.0814 -1.099794,-0.10738 -3.917446,-0.10833 l -3.70578,-10e-4 0.04705,-0.1905 c 0.02588,-0.10477 0.169478,-0.74295 0.319113,-1.41817 l 0.272063,-1.22766 0.381,-0.0579 c 0.20955,-0.0319 2.258237,-0.0405 4.552638,-0.0193 3.879609,0.0359 4.202627,0.0502 4.614333,0.20438 0.592238,0.22174 0.989738,0.56513 1.28811,1.11275 0.204823,0.37593 0.253025,0.57762 0.281989,1.1799 0.03289,0.68395 -0.01305,0.92915 -0.785188,4.191 -0.470995,1.98968 -0.883905,3.55465 -0.969953,3.67621 -0.08241,0.11641 -0.275788,0.29739 -0.429734,0.40216 l -0.279903,0.1905 -4.792313,-0.008 c -2.635772,-0.005 -4.935779,-0.0423 -5.111127,-0.0836 z m 7.385338,-2.93631 c 0.239053,-0.19357 0.491627,-1.28062 0.322492,-1.38796 -0.05922,-0.0376 -1.117332,-0.0681 -2.351349,-0.0678 -2.019906,5e-4 -2.278871,0.0165 -2.596669,0.16084 -0.414953,0.1884 -0.535997,0.37847 -0.535997,0.84163 0,0.59344 0.04259,0.60304 2.676459,0.60304 2.073774,0 2.318314,-0.0147 2.485064,-0.14977 z m 6.861144,2.90755 c -0.580884,-0.16121 -0.879482,-0.34456 -1.253947,-0.76997 -0.691441,-0.78552 -0.790417,-1.84665 -0.352265,-3.77663 0.839661,-3.69854 1.077795,-4.37072 1.826479,-5.15564 0.596471,-0.62534 1.309788,-0.98921 2.150399,-1.09694 0.34925,-0.0447 1.78286,-0.0825 3.1858,-0.084 2.033377,-0.002 2.570007,-0.0258 2.645488,-0.11671 0.05208,-0.0628 0.191785,-0.54852 0.310459,-1.0795 0.118674,-0.53097 0.289064,-1.25115 0.378645,-1.6004 0.08958,-0.34925 0.203658,-0.79693 0.253505,-0.99484 l 0.09063,-0.35983 h 1.870552 1.870551 l -0.04735,0.3175 c -0.02604,0.17463 -0.202455,0.98425 -0.392025,1.79917 -0.189571,0.81491 -0.519475,2.24366 -0.733121,3.175 -0.213646,0.93133 -0.520687,2.26483 -0.682314,2.96333 -0.161627,0.6985 -0.421886,1.8415 -0.578353,2.54 -0.448209,2.00089 -0.975877,4.2073 -1.025313,4.28729 -0.07532,0.12187 -9.069205,0.0767 -9.517818,-0.0478 z m 6.294417,-3.03396 c 0.145233,-0.1062 0.210053,-0.33056 0.715174,-2.47549 0.40921,-1.73765 0.468201,-2.05086 0.413246,-2.19407 -0.04478,-0.11668 -0.284498,-0.13426 -1.830467,-0.13426 -2.453311,0 -2.585284,0.0642 -2.961089,1.44116 -0.232311,0.85117 -0.514615,2.24647 -0.514615,2.54351 0,0.3694 0.180919,0.68463 0.463615,0.8078 0.356187,0.15519 3.504266,0.16481 3.714136,0.0113 z m 4.910763,3.00668 c 0.02232,-0.0815 0.161675,-0.68157 0.309667,-1.3335 0.270511,-1.19165 0.427708,-1.85596 1.893296,-8.001 0.438692,-1.83939 0.902333,-3.79201 1.030313,-4.33917 l 0.232692,-0.99483 h 4.756206 c 3.0401,0 4.93748,0.033 5.2586,0.0915 1.08623,0.19777 2.10077,0.89107 2.55727,1.74754 0.48093,0.90232 0.53096,1.89497 0.174,3.45266 -0.54841,2.39315 -2.03627,3.95826 -4.31465,4.53867 -0.64128,0.16336 -0.99239,0.18363 -3.71391,0.2144 -1.65311,0.0187 -3.069182,0.0332 -3.146815,0.0323 -0.102474,-0.001 -0.166588,0.12011 -0.233983,0.44281 -0.05106,0.24448 -0.290543,1.31128 -0.532191,2.37067 l -0.439359,1.92616 h -1.935863 c -1.802699,0 -1.933072,-0.0102 -1.895273,-0.14816 z m 11.070684,-8.0762 c 0.77567,-0.2597 1.26059,-1.00872 1.32591,-2.04801 0.0336,-0.53428 0.0154,-0.63605 -0.15126,-0.84645 -0.10418,-0.13154 -0.28919,-0.27858 -0.41113,-0.32676 -0.12794,-0.0506 -1.3201,-0.10276 -2.81864,-0.12342 -2.43507,-0.0336 -2.59984,-0.0264 -2.64364,0.1151 -0.0257,0.083 -0.18153,0.77955 -0.34629,1.5479 -0.16477,0.76835 -0.31888,1.48273 -0.34248,1.5875 l -0.0429,0.1905 h 2.57131 c 1.69719,0 2.66915,-0.0327 2.85911,-0.0964 z m 5.07147,8.05992 c -0.60183,-0.20806 -1.19254,-0.82311 -1.35834,-1.41434 -0.24856,-0.88632 -0.0149,-2.41573 0.52329,-3.42552 0.36754,-0.68958 1.08061,-1.33279 1.77073,-1.59726 0.54432,-0.2086 0.55682,-0.20933 4.09951,-0.23798 2.34071,-0.0189 3.5905,-0.0594 3.66184,-0.11864 0.0596,-0.0494 0.1083,-0.25451 0.1083,-0.45572 0,-0.65083 0.14027,-0.62943 -4.12517,-0.62943 -3.51416,0 -3.74878,-0.009 -3.74806,-0.14817 8.1e-4,-0.15671 0.35022,-1.7623 0.51591,-2.37066 l 0.098,-0.35984 h 4.42507 c 4.24681,0 4.44812,0.007 4.99694,0.17663 0.45649,0.141 0.65284,0.25977 0.9733,0.58878 0.77165,0.79223 0.86143,1.69103 0.37601,3.76426 -0.16354,0.6985 -0.5092,2.1844 -0.76813,3.302 -0.50025,2.15922 -0.6611,2.60851 -1.0306,2.87867 -0.22454,0.16417 -0.38139,0.16992 -5.14227,0.18876 -4.63473,0.0183 -4.93683,0.0104 -5.37633,-0.14154 z m 7.68916,-2.82706 c 0.14919,-0.13513 0.23113,-0.38334 0.40297,-1.22066 l 0.0391,-0.1905 h -2.57745 -2.57745 l -0.25762,0.21677 c -0.46877,0.39444 -0.41448,1.09505 0.10139,1.30842 0.10206,0.0422 1.20081,0.0687 2.44166,0.059 2.05389,-0.0162 2.27146,-0.0317 2.4274,-0.17298 z m 4.33351,2.86075 c 0,-0.0738 0.24845,-1.2461 0.55213,-2.60518 1.38375,-6.19301 1.48415,-6.54484 2.04605,-7.16981 0.23734,-0.26398 0.58435,-0.52093 0.94017,-0.69617 l 0.56399,-0.27775 3.55231,-0.0247 c 3.372,-0.0235 3.58116,-0.016 4.12067,0.14792 0.57941,0.17599 1.27663,0.62924 1.59966,1.0399 0.42231,0.53688 0.55032,0.98774 0.54719,1.92722 -0.002,0.73573 -0.0627,1.14445 -0.3494,2.37067 -0.19053,0.81491 -0.54772,2.36749 -0.79375,3.45016 l -0.44733,1.9685 h -1.80551 c -1.18098,0 -1.80552,-0.0301 -1.80552,-0.0871 0,-0.11185 0.54509,-2.66151 0.80497,-3.76522 0.7314,-3.10632 0.76146,-3.39959 0.38688,-3.77418 l -0.24749,-0.24749 h -1.98142 -1.98142 l -0.19251,0.20493 c -0.15595,0.16599 -0.33549,0.82942 -0.94519,3.4925 -0.41396,1.80816 -0.80101,3.47807 -0.8601,3.71091 l -0.10744,0.42333 -1.79847,0.0228 c -1.59425,0.0203 -1.79847,0.008 -1.79847,-0.11127 z m 16.53283,0.0419 c -1.81235,-0.35964 -2.59713,-1.84687 -2.14228,-4.0598 0.46635,-2.26886 0.95174,-4.11594 1.21175,-4.61109 0.50736,-0.96622 1.62671,-1.84974 2.62762,-2.07405 0.21127,-0.0473 1.85793,-0.0887 3.75212,-0.0941 3.30145,-0.01 3.38669,-0.006 3.87934,0.17983 0.6075,0.22863 1.27569,0.82031 1.50384,1.33163 0.30468,0.68287 0.29097,1.34572 -0.059,2.85481 -0.34407,1.48347 -0.51567,1.87999 -0.91933,2.12429 -0.25021,0.15144 -0.52265,0.1644 -4.28885,0.20404 l -4.02167,0.0423 -0.0271,0.3306 c -0.04,0.48901 0.0428,0.70966 0.32042,0.8532 0.21135,0.10929 0.81295,0.12854 4.01832,0.12854 h 3.76975 l -0.0535,0.27516 c -0.0294,0.15135 -0.17542,0.78952 -0.32443,1.41817 l -0.27094,1.143 -4.30895,0.0123 c -2.36992,0.007 -4.47013,-0.0197 -4.66712,-0.0588 z m 7.13894,-6.79502 c 0.25664,-0.29853 0.27264,-0.75238 0.0349,-0.99012 -0.16012,-0.16012 -0.28222,-0.16933 -2.24491,-0.16933 h -2.07557 l -0.2958,0.27517 c -0.21709,0.20194 -0.3151,0.38146 -0.36833,0.67465 -0.0399,0.21972 -0.0506,0.4214 -0.0238,0.44819 0.0268,0.0268 1.11084,0.0375 2.40902,0.0238 l 2.36031,-0.0249 z m 3.25299,6.77805 c 4.3e-4,-0.0582 0.0979,-0.52493 0.21654,-1.03717 0.11867,-0.51223 0.4784,-2.09338 0.79941,-3.51366 0.321,-1.42029 0.71923,-3.17289 0.88496,-3.89467 0.16572,-0.72178 0.41682,-1.82668 0.55801,-2.45533 0.14118,-0.62865 0.38846,-1.7171 0.54951,-2.41876 0.16104,-0.70167 0.29281,-1.30175 0.29281,-1.3335 0,-0.0318 0.81915,-0.0577 1.82033,-0.0577 1.11849,0 1.82033,0.0316 1.82033,0.0821 0,0.0952 -0.31829,1.54163 -0.93215,4.23595 -0.23871,1.04775 -0.5285,2.34315 -0.64397,2.87866 -0.11547,0.53552 -0.43481,1.94522 -0.70964,3.13267 -0.27483,1.18745 -0.5978,2.6162 -0.71772,3.175 -0.11991,0.5588 -0.2387,1.08268 -0.26398,1.16417 -0.0419,0.13507 -0.20631,0.14816 -1.86057,0.14816 -1.39567,0 -1.81446,-0.0244 -1.81387,-0.10583 z M 79.170103,128.27037 c -0.02536,-0.041 0.141774,-0.69847 0.371422,-1.46095 0.229648,-0.76249 0.881525,-2.92939 1.448616,-4.81534 0.567091,-1.88595 1.159023,-3.8481 1.315406,-4.36033 0.582467,-1.90788 1.119924,-3.69126 1.633022,-5.41867 0.290469,-0.9779 0.603671,-2.0066 0.696004,-2.286 0.09233,-0.2794 0.467933,-1.4986 0.834665,-2.70933 0.986462,-3.25672 1.225971,-3.99133 1.552692,-4.76235 0.602139,-1.42099 1.895448,-3.031786 3.231539,-4.024847 0.879743,-0.653877 2.314618,-1.339086 3.430197,-1.638055 l 0.889,-0.238246 7.362554,-0.04458 7.36256,-0.04458 0.0601,-0.294241 c 0.0331,-0.161833 0.0419,-0.323758 0.0196,-0.359834 -0.0223,-0.03607 -1.9e-4,-0.06559 0.0491,-0.06559 0.0498,0 0.0918,-0.17863 0.0945,-0.402166 0.003,-0.221192 0.0313,-0.541954 0.0635,-0.712805 l 0.0586,-0.310639 1.48437,1.030305 c 0.8164,0.566668 2.23557,1.56173 3.15372,2.211249 l 1.66935,1.180944 -3.40772,2.266855 c -1.87424,1.24677 -3.42811,2.26793 -3.45304,2.26923 -0.0249,0.001 -0.03,-0.38013 -0.0112,-0.84762 l 0.0341,-0.84998 -6.84681,0.0263 c -7.585752,0.0292 -7.139631,-0.003 -8.267631,0.59426 -0.601294,0.31832 -1.405902,1.15944 -1.693994,1.77085 -0.205067,0.43521 -1.437869,4.48242 -3.309698,10.86553 -0.491599,1.6764 -1.185261,4.0386 -1.541469,5.24933 -0.356209,1.21074 -0.666655,2.26801 -0.689881,2.3495 -0.03932,0.13798 0.08807,0.14811 1.851481,0.14727 l 1.893708,-9.1e-4 0.757898,-2.64493 c 0.416845,-1.45471 0.810235,-2.8259 0.874202,-3.04709 l 0.116304,-0.40217 3.486131,-0.004 c 5.805899,-0.007 6.764329,-0.10573 8.531169,-0.88109 0.98352,-0.43161 1.90371,-1.02775 3.2523,-2.10695 l 1.016,-0.81305 6.3709,0.0185 c -2.46108,2.98944 -2.60469,3.20415 -4.87362,5.27715 -1.99064,1.81874 -4.95756,3.20605 -7.55095,3.67411 -0.79892,0.14419 -1.45233,0.18377 -3.640667,0.22057 -1.46685,0.0247 -2.69623,0.0735 -2.731955,0.10857 -0.05727,0.0562 -0.220053,0.59749 -1.034185,3.43902 -0.106735,0.37254 -0.343568,1.17264 -0.526296,1.778 l -0.332232,1.10067 -7.503721,0.0216 c -4.264476,0.0123 -7.52363,-0.0106 -7.549841,-0.053 z m 18.029219,-16.85948 c -1.582172,-1.11111 -2.888946,-2.05701 -2.903942,-2.102 -0.01499,-0.045 0.479409,-0.40401 1.098677,-0.79783 0.619268,-0.39382 2.108943,-1.35029 3.310388,-2.1255 1.201445,-0.77521 2.203155,-1.40948 2.226035,-1.40948 0.0431,0 -0.0268,1.10439 -0.10052,1.5875 l -0.042,0.27517 h 5.4462 c 6.52968,0 7.13787,-0.0484 9.25114,-0.73663 1.64192,-0.53471 2.96222,-1.33058 4.11976,-2.4834 1.16734,-1.16256 1.99288,-2.60284 2.41493,-4.213211 0.28684,-1.094464 0.36065,-2.790157 0.16619,-3.818158 -0.42484,-2.245864 -2.14615,-3.971428 -4.67345,-4.684989 -0.66907,-0.188908 -0.71148,-0.190088 -7.7354,-0.215242 -3.88445,-0.01391 -7.09158,0.0045 -7.12696,0.041 -0.0683,0.07035 -1.10846,3.51148 -1.33171,4.405461 l -0.13214,0.529167 h -2.872052 -2.872051 l 0.03904,-0.232834 c 0.03514,-0.209522 0.985403,-3.382697 2.09813,-7.006166 0.228801,-0.745067 0.553195,-1.803512 0.720874,-2.352101 l 0.304871,-0.997434 10.175658,0.02767 10.17565,0.02767 0.90999,0.226407 c 2.66678,0.663501 4.77496,2.104743 6.19041,4.232045 1.34474,2.021012 1.9559,4.025338 2.06182,6.761807 0.11112,2.870766 -0.61358,5.659338 -2.08766,8.033128 -2.30469,3.71134 -5.73652,6.12411 -10.1363,7.12637 -0.82243,0.18735 -0.92546,0.1901 -8.16981,0.21801 l -7.33688,0.0283 -0.0538,0.52608 c -0.0858,0.83911 -0.14228,1.1615 -0.20239,1.15525 -0.0308,-0.003 -1.350569,-0.91491 -2.932742,-2.02603 z" />
                          </g>
                        </svg>
                    </div>
                </div>
                <div class="title">PadPanel</div>
                <div class="subtitle">Kiosk Administration</div>
                \(errorHTML)
                <form action="/login" method="POST">
                    <div class="form-group">
                        <label>Username</label>
                        <input type="text" name="username" value="\(defaultUser)" autocomplete="username" required>
                    </div>
                    <div class="form-group">
                        <label>Password</label>
                        <input type="password" name="password" placeholder="Enter password" autocomplete="current-password" autofocus required>
                    </div>
                    <button type="submit" class="btn">
                        <span class="material-symbols-outlined">login</span> Sign In
                    </button>
                </form>
                <div class="footer">Protected by PadPanel Security</div>
            </div>
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
