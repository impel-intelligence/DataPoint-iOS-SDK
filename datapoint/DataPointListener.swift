import Foundation

/// App lifecycle transitions while the task screen is presented (maps to `UIApplication` notifications).
public enum DataPointAppLifecycleState: String {
    /// `UIApplication.didEnterBackgroundNotification`
    case didEnterBackground
    /// `UIApplication.willEnterForegroundNotification` (returning from background; does not fire on cold launch).
    case willEnterForeground
}

/// Callback interface for task-related events. Set via `DataPoint.setListener`.
public protocol DataPointListener: AnyObject {
    /// A task was completed. `payload` is the raw JSON string from the WebView, or `nil`.
    func onTaskCompleted(_ payload: String?)

    /// The WebView requested that the host app show an ad. The task screen is closed before this fires.
    func onAdRequested()

    /// No tasks are currently available; the task screen is closed before this fires.
    func noTaskAvailable()

    /// The task screen was dismissed (user, WebView, or `closeTasks()`).
    func onClosed()

    /// An error occurred.
    func onError(message: String, code: Int)

    /// Host app entered background or is returning to foreground while the task UI is visible.
    func onAppLifecycleEvent(_ state: DataPointAppLifecycleState)
}

public extension DataPointListener {
    func onAppLifecycleEvent(_ state: DataPointAppLifecycleState) {}
}
