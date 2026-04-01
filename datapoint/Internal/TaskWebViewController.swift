import Network
import UIKit
import WebKit

/// Full-screen task UI (Android `TaskWebActivity` parity).
final class TaskWebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {

    private let taskURL: URL
    private var sessionToken: String
    private let userId: String?
    private let externalUserId: String?
    private let appId: String?
    private let environment: Environment
    private let apiKey: String?

    private var webView: WKWebView!
    private let taskBridge = TaskBridgeMessageHandler()
    private let consoleBridge = ConsoleBridgeMessageHandler()
    private var audioHelper: WebViewAudioVolumeHelper?
    private var networkMonitor: NWPathMonitor?
    private let networkQueue = DispatchQueue(label: "com.datapoint.sdk.network")
    private var pendingReloadURL: URL?
    private var hasReloadedAfterOffline = false

    private let errorContainer = UIView()
    private let errorLabel = UILabel()

    init(
        taskURL: URL,
        sessionToken: String,
        userId: String?,
        externalUserId: String?,
        appId: String?,
        environment: Environment,
        apiKey: String?
    ) {
        self.taskURL = taskURL
        self.sessionToken = sessionToken
        self.userId = userId
        self.externalUserId = externalUserId
        self.appId = appId
        self.environment = environment
        self.apiKey = apiKey
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        DataPoint.onTaskScreenCreated(self)

        buildErrorOverlay()
        buildWebView()
        setupBridgeCallbacks()
        setupNetworkMonitoring()
        loadTaskPage()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isBeingDismissed {
            DataPoint.onTaskScreenDismissed()
        }
    }

    deinit {
        networkMonitor?.cancel()
        audioHelper?.stopObserving()
        if let webView {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: SdkConstants.jsBridgeTask)
        }
    }

    func updateSessionToken(_ token: String) {
        sessionToken = token
        let escaped = Self.escapeForJS(token)
        webView?.evaluateJavaScript(
            """
            if (window.DataPointApp) {
                window.DataPointApp.getToken = function() { return '\(escaped)'; };
            }
            """
        )
        if let host = taskURL.host {
            setCookie(name: "session_token", value: token, host: host)
        }
    }

    // MARK: - Layout

    private func buildErrorOverlay() {
        errorContainer.backgroundColor = .black
        errorContainer.isHidden = true
        errorLabel.textColor = .white
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0
        errorLabel.text = NSLocalizedString("No internet connection.", comment: "DataPoint offline")
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        errorContainer.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(errorContainer)
        errorContainer.addSubview(errorLabel)

        NSLayoutConstraint.activate([
            errorContainer.topAnchor.constraint(equalTo: view.topAnchor),
            errorContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            errorContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            errorContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            errorLabel.centerXAnchor.constraint(equalTo: errorContainer.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: errorContainer.centerYAnchor),
            errorLabel.leadingAnchor.constraint(greaterThanOrEqualTo: errorContainer.leadingAnchor, constant: 24),
            errorLabel.trailingAnchor.constraint(lessThanOrEqualTo: errorContainer.trailingAnchor, constant: -24)
        ])
    }

    private func buildWebView() {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptEnabled = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.websiteDataStore = .default()

        config.userContentController.add(taskBridge, name: SdkConstants.jsBridgeTask)
        injectDataPointTaskShim(into: config.userContentController)
        injectDataPointApp(into: config.userContentController)

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.backgroundColor = .clear
        wv.isOpaque = false
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.allowsBackForwardNavigationGestures = true
        wv.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(wv)
        NSLayoutConstraint.activate([
            wv.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            wv.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            wv.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        webView = wv

        let helper = WebViewAudioVolumeHelper()
        helper.attach(to: wv)
        audioHelper = helper

        let close = UIButton(type: .system)
        close.setTitle(NSLocalizedString("Close", comment: ""), for: .normal)
        close.setTitleColor(.white, for: .normal)
        close.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        close.layer.cornerRadius = 8
        close.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        close.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(close)
        NSLayoutConstraint.activate([
            close.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8)
        ])
    }

    @objc private func closeTapped() {
        DataPoint.notifyClosedFromWebView()
        dismiss(animated: true)
    }

    private func setupBridgeCallbacks() {
        consoleBridge.onConsoleMessage = { level, message in
            DataPointLogger.d("WebView console [\(level)] \(message)")
        }

        taskBridge.onCompleteTask = { [weak self] payload in
            DataPoint.notifyTaskCompletedFromWebView(payload)
            self?.dismissAfterCallback()
        }
        taskBridge.onWatchAd = { [weak self] in
            DataPoint.notifyAdRequestedFromWebView()
            self?.dismissAfterCallback()
        }
        taskBridge.onNoTaskAvailable = { [weak self] in
            DataPoint.notifyNoTaskAvailableFromWebView()
            self?.dismissAfterCallback()
        }
        taskBridge.onCloseTasks = { [weak self] in
            DataPoint.notifyClosedFromWebView()
            self?.dismissAfterCallback()
        }
        taskBridge.onSessionExpired = { [weak self] in
            guard let self, let webView = self.webView else { return }
            DataPoint.handleSessionExpired(from: self, webView: webView) { [weak self] newToken in
                self?.updateSessionToken(newToken)
                let escaped = Self.escapeForJS(newToken)
                webView.evaluateJavaScript("if (typeof onNewTokenGenerate === 'function') { onNewTokenGenerate('\(escaped)'); }", completionHandler: nil)
            }
        }
    }

    private func dismissAfterCallback() {
        dismiss(animated: true)
    }

    // MARK: - Injection

    private func injectDataPointTaskShim(into ucc: WKUserContentController) {
        let name = SdkConstants.jsBridgeTask
        let js = """
        (function() {
            if (window.\(name) && window.\(name).__dp) return;
            function post(action, payload) {
                try {
                    window.webkit.messageHandlers.\(name).postMessage({ action: action, payload: payload });
                } catch (e) {}
            }
            window.\(name) = {
                __dp: true,
                completeTask: function(payload) { post('completeTask', payload); },
                watchAdInstead: function() { post('watchAdInstead', null); },
                noTaskAvailable: function() { post('noTaskAvailable', null); },
                closeTasks: function() { post('closeTasks', null); },
                sessionExpired: function() { post('sessionExpired', null); }
            };
        })();
        """
        ucc.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }

    private func injectDataPointApp(into ucc: WKUserContentController) {
        let token = Self.escapeForJS(sessionToken)
        let uuid = Self.escapeForJS(userId ?? "")
        let sdkVersion = Self.escapeForJS(SdkConstants.sdkVersion)
        let platform = Self.escapeForJS(SdkConstants.platform)
        let env = Self.escapeForJS(environment.rawValue)
        let apiKeyEsc = Self.escapeForJS(apiKey ?? "")
        let appIdEsc = Self.escapeForJS(appId ?? Bundle.main.bundleIdentifier ?? "")

        let js = """
        (function() {
            if (window.\(SdkConstants.jsBridgeApp)) return;
            window.\(SdkConstants.jsBridgeApp) = {
                getToken: function() { return '\(token)'; },
                getUUID: function() { return '\(uuid)'; },
                getSdkVersion: function() { return '\(sdkVersion)'; },
                getPlatform: function() { return '\(platform)'; },
                getEnvironment: function() { return '\(env)'; },
                getApiKey: function() { return '\(apiKeyEsc)'; },
                getAppId: function() { return '\(appIdEsc)'; }
            };
        })();
        """
        ucc.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }

    private static func escapeForJS(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    // MARK: - Load

    private func loadTaskPage() {
        pendingReloadURL = taskURL

        guard let host = taskURL.host else {
            DataPointLogger.e("Invalid task URL")
            return
        }

        setCookie(name: "session_token", value: sessionToken, host: host)
        if let userId {
            setCookie(name: "user_id", value: userId, host: host)
        }

        let request = URLRequest(url: taskURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        webView.load(request)
        hideErrorUI()
    }

    private func setCookie(name: String, value: String, host: String) {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .path: "/"
        ]
        if host.hasPrefix(".") {
            properties[.domain] = host
        } else {
            properties[.domain] = host
        }
        properties[.secure] = "TRUE"

        if let cookie = HTTPCookie(properties: properties) {
            webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) {}
        }
    }

    // MARK: - Network

    private func setupNetworkMonitoring() {
        let monitor = NWPathMonitor()
        networkMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                guard let self else { return }
                if path.status == .satisfied {
                    if self.errorContainer.isHidden == false, !self.hasReloadedAfterOffline {
                        self.hasReloadedAfterOffline = true
                        self.hideErrorUI()
                        if let url = self.pendingReloadURL {
                            DataPointLogger.d("Reloading WebView after connection restored")
                            self.webView.load(URLRequest(url: url))
                        }
                    }
                } else {
                    self.hasReloadedAfterOffline = false
                    self.showErrorUI()
                }
            }
        }
        monitor.start(queue: networkQueue)
    }

    private func showErrorUI() {
        errorContainer.isHidden = false
        webView.isHidden = true
    }

    private func hideErrorUI() {
        errorContainer.isHidden = true
        webView.isHidden = false
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url,
              let host = url.host else {
            decisionHandler(.cancel)
            return
        }
        if trustedHost(host) {
            decisionHandler(.allow)
        } else {
            DataPointLogger.d("Blocked navigation to untrusted host: \(host)")
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if isConnectivityError(error) {
            showErrorUI()
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if isConnectivityError(error) {
            showErrorUI()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        hideErrorUI()
    }

    private func trustedHost(_ host: String) -> Bool {
        SdkConstants.trustedHosts.contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    private func isConnectivityError(_ error: Error) -> Bool {
        let ns = error as NSError
        guard ns.domain == NSURLErrorDomain else { return false }
        switch ns.code {
        case NSURLErrorNotConnectedToInternet,
             NSURLErrorNetworkConnectionLost,
             NSURLErrorCannotFindHost,
             NSURLErrorCannotConnectToHost,
             NSURLErrorDNSLookupFailed:
            return true
        default:
            return false
        }
    }

    // MARK: WKUIDelegate

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default) { _ in
            completionHandler()
        })
        present(alert, animated: true)
    }
}

private final class ConsoleBridgeMessageHandler: NSObject, WKScriptMessageHandler {
    var onConsoleMessage: ((String, String) -> Void)?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        let level = (body["level"] as? String) ?? "log"
        let text = (body["message"] as? String) ?? ""
        onConsoleMessage?(level, text)
    }
}
