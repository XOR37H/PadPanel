import SwiftUI
import WebKit

/// A modal sheet presenting the local WebUI for on-device administration.
/// Loads http://127.0.0.1:<webServerPort> in an embedded WKWebView with zero external dependencies.
struct LocalSettingsSheetView: View {
    @ObservedObject var settings = SettingsManager.shared
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationView {
            LocalSettingsWebView(
                port: settings.webServerPort,
                onClose: {
                    isPresented = false
                }
            )
            .navigationTitle("PadPanel Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                    .font(.body.weight(.semibold))
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

/// Embedded WKWebView pointing to the local loopback server (127.0.0.1)
struct LocalSettingsWebView: UIViewRepresentable {
    let port: Int
    var onClose: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(onClose: onClose)
    }

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "padpanel")

        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.bounces = true
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.05, green: 0.07, blue: 0.09, alpha: 1.0)

        // Ensure web server is listening
        WebServerManager.shared.start()

        if let url = URL(string: "http://127.0.0.1:\(port)/") {
            let request = URLRequest(url: url)
            webView.load(request)
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var onClose: (() -> Void)?

        init(onClose: (() -> Void)?) {
            self.onClose = onClose
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "padpanel", let body = message.body as? String, body == "closeSettings" {
                DispatchQueue.main.async {
                    self.onClose?()
                }
            }
        }
    }
}
