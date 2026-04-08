import Foundation
import UIKit
import WebKit

/// Main entry point for the DataPoint SDK (Android `DataPoint` parity).
public enum DataPoint {

    private enum State {
        case uninitialized
        case initializing
        case initialized
        case failed
    }

    private static let lock = NSLock()
    private static var state: State = .uninitialized
    private static var preferences: DataPointPreferences?
    private static var environment: Environment = .production
    private static var apiKey: String?
    private static var userId: String?
    private static weak var activeTaskController: TaskWebViewController?
    private static var isCallbackDispatched = false

    private static let mainQueue = DispatchQueue.main
    private static let worker = DispatchQueue(label: "com.datapoint.sdk.worker", qos: .userInitiated)

    /// Enable SDK debug logging (default: `false`).
    public static var isLoggingEnabled: Bool {
        get { DataPointLogger.isEnabled }
        set { DataPointLogger.isEnabled = newValue }
    }

    private static weak var listener: DataPointListener?

    // MARK: - Public API

    /// Initialize the SDK once before `showTasks`.
    public static func initialize(
        apiKey: String,
        userId: String? = nil,
        environment: Environment = .production,
        callback: InitCallback? = nil
    ) {
        DataPointLogger.d(
            "initialize() env=\(environment.rawValue) apiKey=\(LogSanitizer.secretLength(apiKey)) " +
            "userId=\(LogSanitizer.secretLength(userId))"
        )

        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            DataPointLogger.e("initialize() failed: apiKey is blank")
            postOnMain { callback?.onError(message: "apiKey cannot be empty", code: ErrorCode.invalidConfiguration.rawValue) }
            return
        }

        Self.environment = environment
        Self.apiKey = apiKey
        Self.userId = userId

        let prefs = DataPointPreferences()
        Self.preferences = prefs

        guard moveToInitializing() else {
            DataPointLogger.w("initialize() ignored – already initializing")
            return
        }

        if prefs.isSessionValid(), prefs.apiKey == apiKey {
            DataPointLogger.d("Existing session is still valid – reusing")
            prefs.userId = userId ?? prefs.userId
            transitionToInitialized()
            postOnMain { callback?.onSuccess() }
            return
        }

        mainQueue.async {
            AdvertisingIdentifierProvider.fetchAdvertisingId { advertisingId, limitAdTracking in
                DataPointLogger.d(
                    "Advertising ID: " +
                    (limitAdTracking ? "omitted (limit ad tracking)" : (advertisingId == nil ? "unavailable" : "present(len=\(advertisingId!.count))"))
                )

                let sdkInfo = DeviceInfoCollector.collectSdkInfo()
                let appInfo = DeviceInfoCollector.collectAppInfo(sha256Cert: nil)
                let deviceInfo = DeviceInfoCollector.collectDeviceInfo()
                let displayInfo = DeviceInfoCollector.collectDisplayInfo()
                let networkInfo = DeviceInfoCollector.collectNetworkInfo()
                let localeInfo = DeviceInfoCollector.collectLocaleInfo()
                let batteryInfo = DeviceInfoCollector.collectBatteryInfo()
                let identifiers = DeviceInfoCollector.collectIdentifiers(
                    advertisingId: advertisingId,
                    installId: prefs.installId,
                    vendorId: UIDevice.current.identifierForVendor?.uuidString
                )
                let privacy = DeviceInfoCollector.collectPrivacy(limitAdTracking: limitAdTracking)

                worker.async {
                    let ts = Int64(Date().timeIntervalSince1970)
                    let result = DataPointApi.validate(
                        baseURL: SdkConstants.apiBaseURL(for: environment),
                        apiKey: apiKey,
                        userId: userId,
                        deviceId: prefs.deviceId,
                        timestamp: ts,
                        environment: environment.rawValue,
                        sdkInfo: sdkInfo,
                        appInfo: appInfo,
                        deviceInfo: deviceInfo,
                        displayInfo: displayInfo,
                        networkInfo: networkInfo,
                        localeInfo: localeInfo,
                        batteryInfo: batteryInfo,
                        identifiersInfo: identifiers,
                        privacyInfo: privacy
                    )

                    switch result {
                    case .success(let data):
                        prefs.sessionToken = data.sessionToken
                        prefs.sessionExpiry = Date().timeIntervalSince1970 + TimeInterval(data.expiresIn)
                        prefs.userId = data.userId
                        prefs.externalUserId = data.externalUserId.isEmpty ? nil : data.externalUserId
                        prefs.apiKey = apiKey
                        prefs.appId = data.appId.isEmpty ? nil : data.appId
                        transitionToInitialized()
                        DataPointLogger.d("Initialization successful")
                        postOnMain { callback?.onSuccess() }

                    case .error(let message, let http):
                        transitionToFailed()
                        let code = DataPointApi.httpCodeToErrorCode(http)
                        DataPointLogger.e("Initialization failed (HTTP \(http)): \(LogSanitizer.safeErrorSnippet(message))")
                        postOnMain { callback?.onError(message: message, code: code) }
                    }
                }
            }
        }
    }

    public static func setListener(_ listener: DataPointListener?) {
        Self.listener = listener
    }

    /// Presents the task wall modally from `presentingViewController`.
    public static func showTasks(from presentingViewController: UIViewController) {
        DataPointLogger.d("showTasks()")

        guard state == .initialized else {
            DataPointLogger.e("showTasks() – SDK not initialized")
            listener?.onError(
                message: "SDK not initialized. Call initialize() first.",
                code: ErrorCode.sdkNotInitialized.rawValue
            )
            return
        }

        if activeTaskController != nil {
            DataPointLogger.w("showTasks() – task screen already visible")
            listener?.onError(message: "Task screen is already showing", code: ErrorCode.taskAlreadyShowing.rawValue)
            return
        }

        guard let prefs = preferences else {
            listener?.onError(message: "SDK not initialized", code: ErrorCode.sdkNotInitialized.rawValue)
            return
        }

        if !prefs.isSessionValid() {
            DataPointLogger.d("Session expired – re-initializing before showing tasks")
            reinitializeAndShow(presentingViewController: presentingViewController)
            return
        }

        launchTaskScreen(presentingViewController: presentingViewController, prefs: prefs)
    }

    /// Dismisses the task screen if it is currently visible.
    public static func closeTasks() {
        DataPointLogger.d("closeTasks()")
        guard let vc = activeTaskController else { return }
        notifyClosedFromWebView()
        mainQueue.async {
            vc.dismiss(animated: true)
        }
    }

    /// Clears all persisted SDK data (`UserDefaults`) and resets in-memory SDK state so the next
    /// `initialize()` performs a full setup. Dismisses the task screen first if it is visible.
    public static func clearPersistedData(completion: (() -> Void)? = nil) {
        DataPointLogger.d("clearPersistedData()")
        postOnMain {
            if let vc = activeTaskController {
                vc.dismiss(animated: true) {
                    performPersistedDataClear()
                    completion?()
                }
            } else {
                performPersistedDataClear()
                completion?()
            }
        }
    }

    private static func performPersistedDataClear() {
        lock.lock()
        activeTaskController = nil
        isCallbackDispatched = false
        preferences = nil
        apiKey = nil
        userId = nil
        state = .uninitialized
        lock.unlock()

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: SdkConstants.prefDeviceId)
        defaults.removeObject(forKey: SdkConstants.prefSessionToken)
        defaults.removeObject(forKey: SdkConstants.prefSessionExpiry)
        defaults.removeObject(forKey: SdkConstants.prefUserId)
        defaults.removeObject(forKey: SdkConstants.prefExternalUserId)
        defaults.removeObject(forKey: SdkConstants.prefApiKey)
        defaults.removeObject(forKey: SdkConstants.prefAppId)
        defaults.removeObject(forKey: SdkConstants.prefInstallId)
    }

    public static func setAge(_ age: Int, callback: DataPointCallback? = nil) {
        setAttributesInternal(["age": age], callback: callback)
    }

    public static func setAgeRange(_ ageRange: String, callback: DataPointCallback? = nil) {
        setAttributesInternal(["age_range": ageRange], callback: callback)
    }

    public static func setOccupation(_ occupation: String, callback: DataPointCallback? = nil) {
        setAttributesInternal(["occupation": occupation], callback: callback)
    }

    public static func setGender(_ gender: String, callback: DataPointCallback? = nil) {
        setAttributesInternal(["gender": gender], callback: callback)
    }

    public static func setUserAttributes(_ attributes: [String: String], callback: DataPointCallback? = nil) {
        var anyMap: [String: Any] = [:]
        attributes.forEach { anyMap[$0.key] = $0.value }
        setAttributesInternal(anyMap, callback: callback)
    }

    public static func setAppUserId(_ appUserId: String, callback: DataPointCallback? = nil) {
        guard !appUserId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            DataPointLogger.e("setAppUserId() failed: appUserId is blank")
            postOnMain {
                callback?.onError(message: "appUserId cannot be empty", code: ErrorCode.invalidConfiguration.rawValue)
            }
            return
        }

        guard state == .initialized else {
            postOnMain {
                callback?.onError(
                    message: "SDK not initialized. Call initialize() first.",
                    code: ErrorCode.sdkNotInitialized.rawValue
                )
            }
            return
        }

        guard let prefs = preferences else {
            postOnMain { callback?.onError(message: "SDK not initialized", code: ErrorCode.sdkNotInitialized.rawValue) }
            return
        }

        guard let token = prefs.sessionToken, !token.isEmpty else {
            postOnMain { callback?.onError(message: "No valid session token", code: ErrorCode.sessionExpired.rawValue) }
            return
        }

        worker.async {
            let result = DataPointApi.setAppUserId(
                baseURL: SdkConstants.apiBaseURL(for: Self.environment),
                sessionToken: token,
                appUserId: appUserId
            )
            switch result {
            case .success:
                DataPointLogger.d("assign_app_user_id succeeded")
                postOnMain { callback?.onSuccess() }
            case .error(let message, let http):
                let code = DataPointApi.httpCodeToErrorCode(http)
                DataPointLogger.e("assign_app_user_id failed (HTTP \(http)): \(LogSanitizer.safeErrorSnippet(message))")
                postOnMain { callback?.onError(message: message, code: code) }
            }
        }
    }

    // MARK: - Internal (TaskWebViewController)

    static func onTaskScreenCreated(_ vc: TaskWebViewController) {
        activeTaskController = vc
        isCallbackDispatched = false
    }

    static func onTaskScreenDismissed() {
        activeTaskController = nil
        if !isCallbackDispatched {
            postOnMain { listener?.onClosed() }
        }
        isCallbackDispatched = false
    }

    static func notifyTaskCompletedFromWebView(_ payload: String?) {
        isCallbackDispatched = true
        postOnMain { listener?.onTaskCompleted(payload) }
    }

    static func notifyAdRequestedFromWebView() {
        isCallbackDispatched = true
        postOnMain { listener?.onAdRequested() }
    }

    static func notifyNoTaskAvailableFromWebView() {
        isCallbackDispatched = true
        postOnMain { listener?.noTaskAvailable() }
    }

    static func notifyClosedFromWebView() {
        isCallbackDispatched = true
        postOnMain { listener?.onClosed() }
    }

    static func notifyErrorFromWebView(_ message: String, code: Int) {
        isCallbackDispatched = true
        postOnMain { listener?.onError(message: message, code: code) }
    }

    static func handleSessionExpired(from viewController: UIViewController, webView: WKWebView, onNewToken: @escaping (String) -> Void) {
        guard let prefs = preferences, let key = apiKey else { return }

        DataPointLogger.d("Session expired – re-initializing in background")

        prefs.clearSession()

        initialize(
            apiKey: key,
            userId: userId,
            environment: environment,
            callback: SessionRefreshCallback(
                success: {
                    guard let newToken = preferences?.sessionToken, !newToken.isEmpty else {
                        DataPointLogger.e("Re-init succeeded but no token available")
                        notifyErrorFromWebView(
                            "Session expired and token refresh failed",
                            code: ErrorCode.sessionExpired.rawValue
                        )
                        return
                    }
                    DataPointLogger.d("Re-init successful – delivering new token to WebView")
                    onNewToken(newToken)
                },
                failure: { message, _ in
                    DataPointLogger.e("Re-init after session expiry failed: \(LogSanitizer.safeErrorSnippet(message))")
                    notifyErrorFromWebView(
                        "Session expired and re-initialization failed: \(message)",
                        code: ErrorCode.sessionExpired.rawValue
                    )
                    mainQueue.async {
                        viewController.dismiss(animated: true)
                    }
                }
            )
        )
    }

    // MARK: - Private

    private static func moveToInitializing() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if state == .initializing {
            return false
        }
        state = .initializing
        return true
    }

    private static func transitionToInitialized() {
        lock.lock()
        state = .initialized
        lock.unlock()
    }

    private static func transitionToFailed() {
        lock.lock()
        state = .failed
        lock.unlock()
    }

    private static func reinitializeAndShow(presentingViewController: UIViewController) {
        guard let prefs = preferences, let key = apiKey else { return }

        initialize(
            apiKey: key,
            userId: userId,
            environment: environment,
            callback: ReinitShowCallback(
                presenter: presentingViewController,
                prefs: prefs
            )
        )
    }

    fileprivate static func launchTaskScreen(presentingViewController: UIViewController, prefs: DataPointPreferences) {
        let base = environment == .production ? SdkConstants.productionTaskURL : SdkConstants.sandboxTaskURL
        guard let url = URL(string: base) else {
            listener?.onError(message: "Invalid task URL", code: ErrorCode.invalidConfiguration.rawValue)
            return
        }

        let vc = TaskWebViewController(
            taskURL: url,
            sessionToken: prefs.sessionToken ?? "",
            userId: prefs.userId,
            externalUserId: prefs.externalUserId,
            appId: prefs.appId,
            environment: environment,
            apiKey: apiKey
        )

        DataPointLogger.d("Presenting TaskWebViewController, url=\(LogSanitizer.urlForLog(base))")

        presentingViewController.present(vc, animated: true)
    }

    private static func setAttributesInternal(_ attributes: [String: Any], callback: DataPointCallback?) {
        guard state == .initialized else {
            postOnMain {
                callback?.onError(
                    message: "SDK not initialized. Call initialize() first.",
                    code: ErrorCode.sdkNotInitialized.rawValue
                )
            }
            return
        }

        guard let prefs = preferences else {
            postOnMain { callback?.onError(message: "SDK not initialized", code: ErrorCode.sdkNotInitialized.rawValue) }
            return
        }

        guard let token = prefs.sessionToken, !token.isEmpty else {
            postOnMain { callback?.onError(message: "No valid session token", code: ErrorCode.sessionExpired.rawValue) }
            return
        }

        worker.async {
            let result = DataPointApi.setAttributes(
                baseURL: SdkConstants.apiBaseURL(for: Self.environment),
                sessionToken: token,
                attributes: attributes
            )
            switch result {
            case .success:
                DataPointLogger.d("Attributes set successfully")
                postOnMain { callback?.onSuccess() }
            case .error(let message, let http):
                let code = DataPointApi.httpCodeToErrorCode(http)
                DataPointLogger.e("Set attributes failed (HTTP \(http)): \(LogSanitizer.safeErrorSnippet(message))")
                postOnMain { callback?.onError(message: message, code: code) }
            }
        }
    }

    private static func postOnMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            mainQueue.async(execute: block)
        }
    }

    // MARK: - Init callback wrappers

    private final class SessionRefreshCallback: NSObject, InitCallback {
        let success: () -> Void
        let failure: (String, Int) -> Void

        init(success: @escaping () -> Void, failure: @escaping (String, Int) -> Void) {
            self.success = success
            self.failure = failure
        }

        func onSuccess() {
            success()
        }

        func onError(message: String, code: Int) {
            failure(message, code)
        }
    }

    private final class ReinitShowCallback: NSObject, InitCallback {
        weak var presenter: UIViewController?
        let prefs: DataPointPreferences

        init(presenter: UIViewController, prefs: DataPointPreferences) {
            self.presenter = presenter
            self.prefs = prefs
        }

        func onSuccess() {
            guard let presenter else { return }
            DataPoint.launchTaskScreen(presentingViewController: presenter, prefs: prefs)
        }

        func onError(message: String, code: Int) {
            DataPoint.listener?.onError(
                message: "Session expired and re-initialization failed: \(message)",
                code: ErrorCode.sessionExpired.rawValue
            )
        }
    }
}
