import Foundation
import WebKit

/// Handles `window.webkit.messageHandlers.DataPointTask` messages (Android `DataPointTask` parity).
final class TaskBridgeMessageHandler: NSObject, WKScriptMessageHandler {

    var onCompleteTask: ((String?) -> Void)?
    var onWatchAd: (() -> Void)?
    var onNoTaskAvailable: (() -> Void)?
    var onCloseTasks: (() -> Void)?
    var onSessionExpired: (() -> Void)?
    /// `(url, mode)` — `mode` is `"external"` for the system browser, `nil`/other for in-app.
    var onOpenExternalUrl: ((String, String?) -> Void)?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == SdkConstants.jsBridgeTask else { return }

        // The injected shim posts `action`; the web app's direct postMessage
        // fallback posts `method`. Accept either so both paths route.
        if let body = message.body as? [String: Any],
           let action = (body["action"] as? String) ?? (body["method"] as? String) {
            DispatchQueue.main.async { [weak self] in
                self?.route(action: action, payload: body["payload"])
            }
            return
        }

        if let body = message.body as? String {
            DispatchQueue.main.async { [weak self] in
                self?.route(action: body, payload: nil)
            }
        }
    }

    private func route(action: String, payload: Any?) {
        switch action {
        case "completeTask":
            let str: String?
            switch payload {
            case let s as String:
                str = s
            case let d as [String: Any]:
                if let data = try? JSONSerialization.data(withJSONObject: d),
                   let json = String(data: data, encoding: .utf8) {
                    str = json
                } else {
                    str = nil
                }
            case nil:
                str = nil
            default:
                str = String(describing: payload!)
            }
            onCompleteTask?(str)
        case "watchAdInstead":
            onWatchAd?()
        case "noTaskAvailable":
            onNoTaskAvailable?()
        case "closeTasks":
            onCloseTasks?()
        case "sessionExpired":
            onSessionExpired?()
        case "openExternalUrl":
            // Payload is either the bare URL or `{ url, mode }`.
            switch payload {
            case let s as String:
                onOpenExternalUrl?(s, nil)
            case let d as [String: Any]:
                if let url = d["url"] as? String {
                    onOpenExternalUrl?(url, d["mode"] as? String)
                } else {
                    DataPointLogger.w("openExternalUrl payload has no url")
                }
            default:
                DataPointLogger.w("openExternalUrl called without a URL")
            }
        default:
            DataPointLogger.w("Unknown DataPointTask action: \(action)")
        }
    }
}
