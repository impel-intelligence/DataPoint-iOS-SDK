import Foundation
import WebKit

/// Handles `window.webkit.messageHandlers.DataPointTask` messages (Android `DataPointTask` parity).
final class TaskBridgeMessageHandler: NSObject, WKScriptMessageHandler {

    var onCompleteTask: ((String?) -> Void)?
    var onWatchAd: (() -> Void)?
    var onNoTaskAvailable: (() -> Void)?
    var onCloseTasks: (() -> Void)?
    var onSessionExpired: (() -> Void)?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == SdkConstants.jsBridgeTask else { return }

        if let body = message.body as? [String: Any],
           let action = body["action"] as? String {
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
        default:
            DataPointLogger.w("Unknown DataPointTask action: \(action)")
        }
    }
}
